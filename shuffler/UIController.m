#import "UIController.h"

#import "Database.h"
#import "MainWindow.h"

@implementation UIController
{
	MainWindow* _mainWindow;
	Database* _database;
}

#if 0
static void insertOrReplace(Database* database, NSString* table, NSArray* values)
{
	NSArray* quoted = [values map:
		^id(NSString* element)
		{
			return [NSString stringWithFormat:@"\"%@\"", element.description];
		}];
	NSString* joined = [quoted componentsJoinedByString:@", "];
	NSString* sql = [NSString stringWithFormat:@"INSERT OR REPLACE INTO %@ VALUES (%@)", table, joined];
	
	NSError* error = nil;
	if (![database update:sql error:&error])
	{
		NSString* reason = [error localizedFailureReason];
		LOG_ERROR("'%s' failed: %s", STR(sql), STR(reason));
	}
}
#endif

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

- (void)windowDidLoad
{
    [super windowDidLoad];
}

// TODO:
// query for the hash
// if not found load the file as NSData and
//   compute the hash, see http://stackoverflow.com/questions/2018550/how-do-i-create-an-md5-hash-of-a-string-in-cocoa
//   save it in the db
//   save it in member data
- (void)setPath:(NSString*)path
{
	// TODO: see DoUpdateNewImage
	[self.window setTitle:path.lastPathComponent];
}

- (IBAction)selectRating:(id)sender
{
	NSString* rating = _ratingPopup.titleOfSelectedItem;
	LOG_VERBOSE("rating = %s", STR(rating));
}

- (IBAction)selectScaling:(id)sender
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
	
	[_mainWindow update:_mainWindow.path scaling:scaling];
}

- (void)selectTag:(NSMenuItem*)sender
{
	NSString* name = [sender title];
	NSString* tags = [self _toggleTag:name];
	[_tagsLabel setStringValue:tags];
}

- (IBAction)selectNoneTag:(NSMenuItem*)sender
{
	[_tagsLabel setStringValue:@""];
}

- (IBAction)selectNewTag:(NSMenuItem*)sender
{
	// TODO: implement this
}

- (BOOL)validateMenuItem:(NSMenuItem*)item
{
	BOOL enabled = true;
	
	if (item.action == @selector(selectNoneTag:))
	{
		[item setState:_tagsLabel.stringValue.length == 0];
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

@end
