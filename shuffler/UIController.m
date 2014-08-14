#import "UIController.h"

#import <CommonCrypto/CommonDigest.h>

#import "AppDelegate.h"
#import "Database.h"
#import "Files.h"
#import "MainWindow.h"
#import "NewTagController.h"

@implementation UIController
{
	MainWindow* _mainWindow;
	Database* _database;
	NSString* _hash;
	
	NSString* _rating;
}

- (id)init:(MainWindow*)window dbPath:(NSString*)dbPath
{
	self = [super initWithWindowNibName:@"UIWindow"];

    if (self)
	{
		_mainWindow = window;
		if (dbPath)
			_database = [self _createDatabase:dbPath];
		
        [self.window makeKeyAndOrderFront:self];	// note that we need to call the window method to load the controls
		[_tagsPopup selectItem:nil];
		[_tagsLabel setStringValue:@""];
		[self _populateTagsMenu];
    }
    
	return self;
}

- (NSString*)path
{
	return _mainWindow.path;
}

- (void)setPath:(NSString*)path
{
	// Compute the hash (we do it each time because the file may have been edited)
	NSData* data = [NSData dataWithContentsOfFile:path];
	unsigned char hash[16];
	CC_MD5(data.bytes, (CC_LONG) data.length, hash);
	_hash = [NSString stringWithFormat:@"%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X",
		hash[0], hash[1], hash[2], hash[3],
		hash[4], hash[5], hash[6], hash[7],
		hash[8], hash[9], hash[10], hash[11],
		hash[12], hash[13], hash[14], hash[15]];
	
	// Try to use which ever settings the user last set
	NSInteger rating = 0;
	NSMutableString* tags = [NSMutableString stringWithString:@""];
	double scaling = 1.0;
	if (_database)
	{
		NSError* error = nil;
		NSString* sql = [NSString stringWithFormat:@"\
			SELECT rating, tags, scaling\
			   FROM Indexing, Appearance\
			WHERE\
			   Indexing.hash = '%@' AND Appearance.hash = '%@'", _hash, _hash];
		
		NSArray* rows = [_database queryRows:sql error:&error];
		if (rows)
		{
			// If the user has edited the image its hash will change and he will have
			// to re-enter tags and whatnot.
			if (rows.count > 0)
			{
				NSArray* row = rows[0];

				NSString* field = row[0];
				rating = [field integerValue];

				tags = [NSMutableString stringWithString:row[1]];
				[tags deleteCharactersInRange:NSMakeRange(tags.length - 1, 1)];
				[tags replaceOccurrencesOfString:@":" withString:@" • " options:NSLiteralSearch range:NSMakeRange(0, tags.length)];
				
				field = row[2];
				if ([field localizedCaseInsensitiveCompare:@"inf"] != NSOrderedSame)
					scaling = [field doubleValue];
				else
					scaling = INFINITY;
			}
		}
		else
		{
			NSString* reason = [error localizedFailureReason];
			LOG_ERROR("'%s' failed: %s", STR(sql), STR(reason));
		}
	}
	
	// Update our UI
	[self.window setTitle:path.lastPathComponent];
	[_ratingPopup selectItemAtIndex:rating];
	[_tagsLabel setStringValue:tags];
	_rating = [_ratingPopup titleOfSelectedItem];
	
	if (scaling == 1.0)
		[_scalingPopup selectItemWithTitle:@"None"];
	else if (scaling == INFINITY)
		[_scalingPopup selectItem:_scalingPopup.lastItem];
	else
		[_scalingPopup selectItemWithTitle:[NSString stringWithFormat:@"%d%%", (int) (100*scaling)]];
	
	// Swap in the new image
	[_mainWindow update:path imageData:data scaling:scaling];
	
	if (scaling == INFINITY)
	{
		NSMenuItem* item = [_scalingPopup lastItem];
		[item setTitle:[NSString stringWithFormat:@"Max (%.0f%%)", 100*_mainWindow.maxScaling]];
	}
}

- (void)trashedFile:(NSString*)path
{
	AppDelegate* app = [NSApp delegate];
	if (_tagsLabel.stringValue.length > 0)
	{
		NSString* rating = [_ratingPopup titleOfSelectedItem];
		[app.files trashedCategorizedFile:path withRating:rating];
	}
	else
	{
		[app.files trashedUncategorizedFile:path];
	}
}

- (IBAction)selectRating:(id)sender
{
	NSString* oldRating = [_rating copy];
	NSString* newRating = [_ratingPopup titleOfSelectedItem];
	if ([newRating compare:oldRating] != NSOrderedSame)
	{
		_rating = newRating;

		AppDelegate* app = [NSApp delegate];
		if (_tagsLabel.stringValue.length == 0)
		{
			// If the user edits an uncategorized file then it's nice
			// to move it out of uncategorized. This will make the Info
			// window a bit nicer and save the user from having to set
			// the tag (sometimes anyway).
			[self selectNoneTag:nil];
		}
		else
		{
			if (_database)
				[self _saveSettings];

			[app.files changedRatingFrom:oldRating to:newRating];
		}
		[app rescheduleTimer];
	}
}

- (IBAction)selectScaling:(id)sender
{
	double scaling = [self _getScaling];
	
	NSData* data = [NSData dataWithContentsOfFile:_mainWindow.path];
	[_mainWindow update:_mainWindow.path imageData:data scaling:scaling];

	if (_tagsLabel.stringValue.length == 0)
		[self selectNoneTag:nil];
	else if (_database)
		[self _saveSettings];

	if (scaling == INFINITY)
	{
		NSMenuItem* item = [_scalingPopup lastItem];
		[item setTitle:[NSString stringWithFormat:@"Max (%.0f%%)", 100*_mainWindow.maxScaling]];
	}

	AppDelegate* app = [NSApp delegate];
	[app rescheduleTimer];
}

- (void)_selectTagByTitle:(NSString*)name
{
	bool wasUncategorized = _tagsLabel.stringValue.length == 0;
	
	NSString* tags = [self _toggleTag:name];
	[_tagsLabel setStringValue:tags];
	
	if (_database)
		[self _saveSettings];	// this is what saves the new hash into the database
	
	AppDelegate* app = [NSApp delegate];
	if (wasUncategorized)
	{
		NSString* rating = [_ratingPopup titleOfSelectedItem];
		[app.files changedUncategorizedToCategorized:rating];
	}

	[app rescheduleTimer];
}

- (void)selectTag:(NSMenuItem*)sender
{
	[self _selectTagByTitle:sender.title];
}

- (IBAction)selectNoneTag:(NSMenuItem*)sender
{
	bool wasUncategorized = _tagsLabel.stringValue.length == 0;
	
	[_tagsLabel setStringValue:@"None"];
	if (_database)
		[self _saveSettings];

	if (wasUncategorized)
	{
		AppDelegate* app = [NSApp delegate];
		NSString* rating = [_ratingPopup titleOfSelectedItem];
		[app.files changedUncategorizedToCategorized:rating];
	}

	AppDelegate* app = [NSApp delegate];
	[app rescheduleTimer];
}

- (IBAction)selectNewTag:(NSMenuItem*)sender
{
	NewTagController* controller = [[NewTagController alloc] init];
	NSInteger button = [NSApp runModalForWindow:controller.window];
	if (button == NSOKButton)
	{
		NSString* name = controller.textField.stringValue;
		[self _addTag:name];
		
		[self _clearTagsMenu];
		[self _populateTagsMenu];

		AppDelegate* app = [NSApp delegate];
		[app reloadTagsMenu];

		[self _selectTagByTitle:name];
	}
}

- (void)_addTag:(NSString*)tag
{
	if (_database)
	{
		NSError* error = nil;
		tag = [_database escapeValue:tag];
		NSString* sql = [NSString stringWithFormat:@"INSERT INTO Tags VALUES (\"%@\");", tag];
		if (![_database update:sql error:&error])
		{
			LOG_ERROR("'%s' failed: %s", STR(sql), STR(error.localizedFailureReason));
		}
	}
}

- (NSArray*)getDatabaseTags
{
	NSArray* tags = nil;
	
	if (_database)
	{
		NSError* error = nil;
		NSString* sql = @"SELECT name FROM Tags ORDER BY name";
		tags = [_database queryRows1:sql error:&error];
		if (!tags)
		{
			LOG_ERROR("'%s' failed: %s", STR(sql), STR(error.localizedFailureReason));
		}
	}
	
	return tags != nil ? tags : @[];
}

- (void)_clearTagsMenu
{
	while (true)
	{
		NSMenuItem* item = [_tagsMenu itemAtIndex:2];
		if ([item isSeparatorItem])
			break;
		
		[_tagsMenu removeItemAtIndex:2];
	}
}

- (void)_populateTagsMenu
{
	NSArray* tags = [self getDatabaseTags];
	for (NSUInteger i = tags.count - 1; i < tags.count; --i)
	{
		[_tagsMenu insertItemWithTitle:tags[i] action:@selector(selectTag:) keyEquivalent:@"" atIndex:2];
	}
}

- (void)_saveSettings
{
	ASSERT(_database);
	ASSERT(_mainWindow.path.length > 0);
	
	NSInteger index = _ratingPopup.indexOfSelectedItem;
	NSString* tags = _tagsLabel.stringValue;
	tags = [tags stringByReplacingOccurrencesOfString:@" • " withString:@":"];
	tags = [tags stringByAppendingString:@":"];
	[_database insertOrReplace:@"Indexing" values:@[_hash, [NSString stringWithFormat:@"%ld", (long)index], tags]];

	double scaling = [self _getScaling];
	[_database insertOrReplace:@"Appearance" values:@[_hash, @"0", [NSString stringWithFormat:@"%f", scaling]]];

	[_database insertOrReplace:@"ImagePaths" values:@[_mainWindow.path, _hash]];
}

- (double)_getScaling
{
	double scaling;
	
	NSString* title = _scalingPopup.titleOfSelectedItem;
	if ([title characterAtIndex:title.length-1] == '%')
	{
		scaling = title.doubleValue/100.0;
	}
	else if ([title localizedCaseInsensitiveCompare:@"None"] == NSOrderedSame)
	{
		scaling = 1.0;
	}
	else
	{
		scaling = INFINITY;
	}
	
	return scaling;
}

- (BOOL)windowShouldClose:(id)sender
{
	return FALSE;
}

- (BOOL)validateMenuItem:(NSMenuItem*)item
{
	BOOL enabled = true;
	
	if (item.action == @selector(selectNoneTag:))
	{
		[item setState:[_tagsLabel.stringValue compare:@"None"] == NSOrderedSame];
	}
	else if (item.action == @selector(selectTag:))
	{
		NSArray* tags = [_tagsLabel.stringValue componentsSeparatedByString:@" • "];
		[item setState:[tags containsObject:item.title]];
	}
	else if (item.action == @selector(selectNewTag:))
	{
		[item setState:0];
	}
	else if (item.action == @selector(orderOut:))
	{
		enabled = false;
	} 
	
	return enabled;
}

- (NSString*)_toggleTag:(NSString*)tag
{
	NSMutableArray* tags;
	if (_tagsLabel.stringValue.length > 0 && [_tagsLabel.stringValue compare:@"None"] != NSOrderedSame)
		tags = [[_tagsLabel.stringValue componentsSeparatedByString:@" • "] mutableCopy];
	else
		tags = [NSMutableArray new];
	
	if ([tags containsObject:tag])
	{
		[tags removeObject:tag];
	}
	else
	{
		[tags addObject:tag];
		[tags sortUsingSelector:@selector(caseInsensitiveCompare:)];
	}
	
	return [tags componentsJoinedByString:@" • "];
}

- (Database*)_createDatabase:(NSString*)path
{
	NSError* error = nil;
	Database* database = [[Database alloc] initWithPath:path error:&error];
	
	if (database)
	{
		bool created = true;
		
		if (created)
			created = [database update:@"\
				CREATE TABLE IF NOT EXISTS Indexing(\
				   hash TEXT NOT NULL PRIMARY KEY\
				      CONSTRAINT valid_hash_len CHECK(length(hash) >= 8),\
				   rating INTEGER NOT NULL\
				      CONSTRAINT valid_rating CHECK(rating >= 0 AND rating <= 3),\
				   tags TEXT NOT NULL\
				      CONSTRAINT valid_tags CHECK(length(tags) = 0 OR substr(tags, -1) = ':')\
				)" error:&error];
		
		if (created)
			created = [database update:@"\
				CREATE TABLE IF NOT EXISTS Appearance(\
				   hash TEXT NOT NULL PRIMARY KEY\
				      CONSTRAINT valid_hash_len CHECK\(length(hash) >= 8),\
				   alignment INTEGER NOT NULL,\
				   scaling INTEGER NOT NULL\
				)" error:&error];
		
		if (created)
			created = [database update:@"\
				CREATE TABLE IF NOT EXISTS Directories(\
				   path TEXT NOT NULL PRIMARY KEY\
				      CONSTRAINT absolute_path CHECK(substr(path, 1, 1) = '/'),\
				   process_time INTEGER NOT NULL\
				      CONSTRAINT valid_process_time CHECK(process_time > 0)\
				)" error:&error];
		
		if (created)
			created = [database update:@"\
					   CREATE TABLE IF NOT EXISTS ImagePaths(\
					   path TEXT NOT NULL PRIMARY KEY\
					   CONSTRAINT absolute_path CHECK(substr(path, 1, 1) = '/'),\
					   hash TEXT NOT NULL\
					   )" error:&error];
		
		if (created)
			created = [database update:@"\
				CREATE TABLE IF NOT EXISTS Tags(\
				   name TEXT NOT NULL PRIMARY KEY\
				)" error:&error];
		
		if (!created)
		{
			NSString* reason = [error localizedFailureReason];
			NSString* mesg = [NSString stringWithFormat:@"Couldn't initialize the database at '%@': %@", path, reason];
			
			NSAlert* alert = [[NSAlert alloc] init];
			[alert setAlertStyle:NSWarningAlertStyle];
			[alert setMessageText:@"Image settings will not be persisted."];
			[alert setInformativeText:mesg];
			[alert runModal];
		}
	}
	else
	{
		NSString* reason = [error localizedFailureReason];
		NSString* mesg = [NSString stringWithFormat:@"Couldn't create a database at '%@': %@", path, reason];
		
		NSAlert* alert = [[NSAlert alloc] init];
		[alert setAlertStyle:NSWarningAlertStyle];
		[alert setMessageText:@"Image settings will not be persisted."];
		[alert setInformativeText:mesg];
		[alert runModal];
	}
	return database;
}

@end
