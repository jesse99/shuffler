#import "UIController.h"

#import <CommonCrypto/CommonDigest.h>

#import "Database.h"
#import "MainWindow.h"

@implementation UIController
{
	MainWindow* _mainWindow;
	Database* _database;
	NSString* _hash;
}

- (id)init:(MainWindow*)window
{
	self = [super initWithWindowNibName:@"UIWindow"];

    if (self)
	{
		_mainWindow = window;
		_database = [self _createDatabase];
		
        [self.window makeKeyAndOrderFront:self];	// note that we need to call the window method to load the controls
		[_tagsPopup selectItem:nil];
		[_tagsLabel setStringValue:@""];
		
		NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
		NSArray* tags = [defaults objectForKey:@"tags"];
		for (NSUInteger i = tags.count - 1; i < tags.count; --i)
		{
			[_tagsMenu insertItemWithTitle:tags[i] action:@selector(selectTag:) keyEquivalent:@"" atIndex:2];
		}
    }
    
	return self;
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
	[self _insertOrReplace:@"ImagePaths" values:@[path, _hash]];
	LOG_NORMAL("hash = %s", STR(_hash));
	
	// Try to use which ever settings the user last set
	NSError* error = nil;
	NSString* sql = [NSString stringWithFormat:@"\
		SELECT Indexing.rating, Indexing.tags, Appearance.scaling\
		   FROM Indexing, Appearance\
		WHERE\
		   Indexing.hash = '%@' AND Appearance.hash = '%@'", _hash, _hash];
	
	NSInteger rating = 0;
	NSString* tags = @"";
	double scaling = 1.0;
	NSArray* rows = [_database queryRows:sql error:&error];
	if (rows)
	{
		if (rows.count > 0)
		{
			NSArray* row = rows[0];

			NSString* field = row[0];
			rating = [field integerValue];

			field = row[1];
			tags = [field stringByReplacingOccurrencesOfString:@":" withString:@" • "];
			
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
	
	// Update our UI
	[self.window setTitle:path.lastPathComponent];
	[_ratingPopup selectItemAtIndex:rating];
	[_tagsLabel setStringValue:tags];
	
	if (scaling == 1.0)
		[_scalingPopup selectItemWithTitle:@"None"];
	else if (scaling == INFINITY)
		[_scalingPopup selectItemWithTitle:@"Max"];
	else
		[_scalingPopup selectItemWithTitle:[NSString stringWithFormat:@"%d%%", (int) (100*scaling)]];
	
	// Swap in the new image
	[_mainWindow update:path imageData:data scaling:scaling];
}

- (IBAction)selectRating:(id)sender
{
	[self _saveSettings];
}

- (IBAction)selectScaling:(id)sender
{
	double scaling = [self _getScaling];
	
	NSData* data = [NSData dataWithContentsOfFile:_mainWindow.path];
	[_mainWindow update:_mainWindow.path imageData:data scaling:scaling];
	[self _saveSettings];
}

- (void)selectTag:(NSMenuItem*)sender
{
	NSString* name = [sender title];
	NSString* tags = [self _toggleTag:name];
	[_tagsLabel setStringValue:tags];
	[self _saveSettings];
}

- (IBAction)selectNoneTag:(NSMenuItem*)sender
{
	[_tagsLabel setStringValue:@""];
	[self _saveSettings];
}

- (IBAction)selectNewTag:(NSMenuItem*)sender
{
	// TODO: implement this
}

- (void)_saveSettings
{
	NSInteger index = _ratingPopup.indexOfSelectedItem;
	NSString* tags = _tagsLabel.stringValue;
	tags = [tags stringByReplacingOccurrencesOfString:@" • " withString:@":"];
	[self _insertOrReplace:@"Indexing" values:@[_hash, [NSString stringWithFormat:@"%ld", (long)index], tags]];

	double scaling = [self _getScaling];
	[self _insertOrReplace:@"Appearance" values:@[_hash, @"0", [NSString stringWithFormat:@"%f", scaling]]];
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
	
	return enabled;
}

- (NSString*)_toggleTag:(NSString*)tag
{
	NSMutableArray* tags;
	if (_tagsLabel.stringValue.length > 0)
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

- (Database*)_createDatabase
{
	Database* database = nil;
	
	NSString* path = nil;
	NSError* error = nil;
	
	NSArray* dirs = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, true);
	if (dirs.count > 0)
	{
		NSFileManager* fm = [NSFileManager defaultManager];
		bool exists = [fm fileExistsAtPath:dirs[0] isDirectory:NULL];
		if (!exists)
			exists = [fm createDirectoryAtPath:dirs[0] withIntermediateDirectories:true attributes:nil error:&error];
		
		if (exists)
		{
			NSString* root = dirs[0];
			path = [root stringByAppendingPathComponent:@"shuffler.db"];
		}
	}
	else
	{
		NSString* mesg = [NSString stringWithFormat:@"Couldn't find the application support directory."];
		NSDictionary* dict = @{NSLocalizedFailureReasonErrorKey:mesg};
		error = [NSError errorWithDomain:@"shuffler" code:4 userInfo:dict];
	}
	
	if (!error)
		database = [[Database alloc] initWithPath:path error:&error];
	
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

- (void)_insertOrReplace:(NSString*)table values:(NSArray*)values
{
	NSArray* quoted = [values map:
	   ^id(NSString* element)
	   {
		   return [NSString stringWithFormat:@"\"%@\"", element.description];
	   }];
	NSString* joined = [quoted componentsJoinedByString:@", "];
	NSString* sql = [NSString stringWithFormat:@"INSERT OR REPLACE INTO %@ VALUES (%@)", table, joined];
	
	NSError* error = nil;
	if (![_database update:sql error:&error])
	{
		NSString* reason = [error localizedFailureReason];
		LOG_ERROR("'%s' failed: %s", STR(sql), STR(reason));
	}
}

@end
