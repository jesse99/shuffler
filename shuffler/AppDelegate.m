#import "AppDelegate.h"

#include "Carbon/Carbon.h"

#import "Database.h"
#import "DatabaseInfoController.h"
#import "Files.h"
#import "MainWindow.h"
#import "UIController.h"

const double DefaultInterval = 60.0;		// TODO: use a pref for the delay
const NSUInteger MaxHistory = 500;

@implementation AppDelegate
{
	NSTimer* _timer;
	UIController* _controller;
	NSString* _dbPath;

	NSMutableArray* _shown;
	NSUInteger _index;
	
	Files* _files;
	NSString* _rating;
	NSMutableArray* _tags;
	bool _includeUncategorized;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	NSDictionary* initialSettings = @{@"root": @"~/Pictures"};
	[defaults registerDefaults:initialSettings];
	
	//	[defaults setObject:@"/Users/jessejones/Documents/1000 HD Wallpapers (By Mellori Studio)" forKey:@"root"];
//	[defaults synchronize];
		
	_rating = @"Normal";
	_tags = [NSMutableArray new];
	_includeUncategorized = true;
	
	_timer = [NSTimer scheduledTimerWithTimeInterval:DefaultInterval target:self selector:@selector(nextImage:) userInfo:nil repeats:true];
	_shown = [NSMutableArray new];
	
	NSString* root = [defaults stringForKey:@"root"];
	root = [root stringByStandardizingPath];
	_dbPath = [root stringByAppendingPathComponent:@"shuffler.db"];
	_controller = [[UIController alloc] init:_window dbPath:_dbPath];
	
	[self reloadTagsMenu];
	
	[_controller.window setTitle:@"Scanning…"];
	[self _registerHotKeys];
		
	dispatch_queue_t concurrent = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	dispatch_queue_t main = dispatch_get_main_queue();
	dispatch_async(concurrent,
	   ^{
		   Files* files = [[Files alloc] init:root dbPath:_dbPath];
		 
		   dispatch_async(main, ^{[self _displayInitial:files];});
	   });
}

- (void)reloadTagsMenu
{
	[self _clearTagsMenu];
	
	NSArray* tags = [[_controller getDatabaseTags] reverse];
	for (NSString* tag in tags)
	{
		NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:tag action:@selector(toggleTag:) keyEquivalent:@""];
		[_tagsMenu insertItem:item atIndex:2];
	}
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

- (void)applicationWillTerminate:(NSNotification *)notification
{
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	[defaults synchronize];
}

- (void)_displayInitial:(Files*)files
{
	_files = files;
		
	if (_files && _files.numWithNoFilter > 0)
		(void) [_files filterBy:_rating andTags:_tags includeUncategorized:_includeUncategorized];
	
	if (_files && _files.numFiltered > 0)
	{
		[self nextImage:self];
		[self.window display];		// not sure why we need this, but without it we don't see the very first image
	}
	else
	{
		if (_files.numWithNoFilter == 0)
			[_controller.window setTitle:@"No Files"];
		else
			[_controller.window setTitle:@"No Matches"];
	}
}

- (IBAction)showInfo:(id)sender
{
	// Showing the database info should be relatively uncommon so
	// we'll take the opportunity to clean up the database. Note
	// that this is 1) in the background 2) very fast, 40K images
	// takes under a second on a 2009 Mac Pro.
	[self compactDatabase];
	
	[DatabaseInfoController show];
}

- (IBAction)copyPath:(id)sender
{
	NSString* path = _controller.path;
	
	NSPasteboard* pb = [NSPasteboard generalPasteboard];
	NSArray* types = @[NSStringPboardType];
	[pb declareTypes:types owner:self];
	
	[pb setString:path forType:NSStringPboardType];
}

- (IBAction)openFile:(id)sender
{
	NSString* path = _controller.path;
	
	[[NSWorkspace sharedWorkspace] openFile:path];
}

- (IBAction)showFileInFinder:(id)sender
{
	NSString* path = _controller.path;
	
	[[NSWorkspace sharedWorkspace] selectFile:path inFileViewerRootedAtPath:@""];
}

- (IBAction)trashFile:(id)sender
{
	if (_index < _shown.count)
	{
		NSString* path = _shown[_index];
		[_shown removeObjectAtIndex:_index];
		--_index;
		
		[self nextImage:self];
		[_timer setFireDate:[NSDate dateWithTimeIntervalSinceNow:DefaultInterval]];
		
		NSURL* url = [[NSURL alloc] initFileURLWithPath:path];
		NSURL* newURL = nil;
		NSError* error = nil;
		BOOL trashed = [[NSFileManager defaultManager] trashItemAtURL:url resultingItemURL:&newURL error:&error];
		if (trashed)
			[_controller trashedFile:path];
		else
			LOG_ERROR("failed to trash %s: %s", STR(path), STR(error.localizedFailureReason));
	}
	else
	{
		NSBeep();
	}
}

- (IBAction)changeRating:(NSMenuItem *)sender
{
	if (_files && [_rating compare:sender.title] != NSOrderedSame)
	{		
		_rating = sender.title;
		[_timer setFireDate:[NSDate dateWithTimeIntervalSinceNow:DefaultInterval]];
		
		// For now we do this in the main thread because it gets all squirrelly if
		// we queue up multiple threads and have them finish at different times.
		if (![_files filterBy:_rating andTags:_tags includeUncategorized:_includeUncategorized])
			[_controller.window setTitle:@"No Matches"];
	}
}

- (void)toggleTag:(NSMenuItem*)sender
{
	NSString* tag = sender.title;
	NSUInteger index = [_tags indexOfObject:tag];
	if (index != NSNotFound)
	{
		[_tags removeObjectAtIndex:index];
	}
	else
	{
		index = [_tags indexOfObject:@"None"];
		if (index != NSNotFound)
			[_tags removeObjectAtIndex:index];

		[_tags addObject:tag];
		[_tags sortUsingSelector:@selector(compare:)];
	}

	if (![_files filterBy:_rating andTags:_tags includeUncategorized:_includeUncategorized])
		[_controller.window setTitle:@"No Matches"];
	else
		[_timer setFireDate:[NSDate dateWithTimeIntervalSinceNow:DefaultInterval]];
}

- (IBAction)toggleNoneTag:(id)sender
{
	[_tags removeAllObjects];
	[_tags addObject:@"None"];
	
	if (![_files filterBy:_rating andTags:_tags includeUncategorized:_includeUncategorized])
		[_controller.window setTitle:@"No Matches"];
	else
		[_timer setFireDate:[NSDate dateWithTimeIntervalSinceNow:DefaultInterval]];
}

- (IBAction)toggleUncategorizedTag:(id)sender
{
	_includeUncategorized = !_includeUncategorized;
	if (![_files filterBy:_rating andTags:_tags includeUncategorized:_includeUncategorized])
		[_controller.window setTitle:@"No Matches"];
	else
		[_timer setFireDate:[NSDate dateWithTimeIntervalSinceNow:DefaultInterval]];
}

- (IBAction)nextImage:(id)sender
{
	if (_files)
	{
		NSString* path = nil;
		if (_index + 1 < _shown.count)
		{
			path = _shown[++_index];
		}
		else
		{
			path = [_files randomPath:_shown];
			if (path)
			{
				[_shown addObject:path];
				
				NSUInteger max = MIN(_files.numFiltered/2, 2000);
				if (_shown.count > max)
					[_shown removeObjectsInRange:NSMakeRange(0, max/2)];
				
				_index = _shown.count - 1;
			}
		}
		
		if (path)
		{
			[_controller setPath:path];
			[_timer setFireDate:[NSDate dateWithTimeIntervalSinceNow:DefaultInterval]];
		}
		else
		{
			NSBeep();
		}
	}
}

- (IBAction)prevImage:(id)sender
{
	if (_index > 0)
	{
		NSString* path = _shown[--_index];
		[_controller setPath:path];
		[_timer setFireDate:[NSDate dateWithTimeIntervalSinceNow:DefaultInterval]];
	}
	else
	{
		NSBeep();
	}
}

- (void)compactDatabase
{
	LOG_NORMAL("compacting database");
	
	dispatch_queue_t concurrent = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	dispatch_queue_t main = dispatch_get_main_queue();
	dispatch_async(concurrent,
	   ^{
		   NSError* error = nil;
		   Database* db = [[Database alloc] initWithPath:_dbPath error:&error];
		   if (!db)
		   {
			   LOG_ERROR("Couldn't create the database at '%s': %s", STR(_dbPath), STR(error.localizedFailureReason));
			   NSBeep();
			   return;
		   }
		   
		   int count = [self _compactDatabase:db];
		   LOG_NORMAL("removed %d records", count);
		   
		   dispatch_async(main, ^{
			   [[NSNotificationCenter defaultCenter] postNotificationName:@"Stats Changed" object:self];
		   });
	   });
}

- (int)_compactDatabase:(Database*)db
{
	int count = 0;
	NSError* error = nil;
	
	// Enumerate path and hash from ImagePaths,
	NSFileManager* fm = [NSFileManager defaultManager];
	NSString* sql = @"SELECT path, hash FROM ImagePaths";
	NSMutableArray* rows = [db queryRows:sql error:&error];
	for (NSUInteger i = 0; rows && i < rows.count; ++i)
	{
		NSArray* row = rows[i];
		NSString* path = row[0];
		NSString* hash = row[1];
		
		// if path does not exist then,
		if (![fm fileExistsAtPath:path])
		{
			// update ImagePaths,
			path = [path stringByReplacingOccurrencesOfString:@"'" withString:@"''"];
			[self _compactRow:db table:@"ImagePaths" key:@"path" value:path];
			++count;
			
			// and if the hash is not empty then,
			if (hash.length > 0)
			{
				// update Indexing and Appearance.
				[self _compactRow:db table:@"Indexing" key:@"hash" value:hash];
				[self _compactRow:db table:@"Appearance" key:@"hash" value:hash];
			}
		}
	}
	
	if (error)
		LOG_ERROR("Compaction error: %s", STR(error.localizedFailureReason));
	return count;
}

- (void)_compactRow:(Database*)db table:(NSString*)table key:(NSString*)key value:(NSString*)value
{
	NSError* error = nil;
	NSString* sql = [NSString stringWithFormat:@"DELETE FROM %@ WHERE %@=='%@'", table, key, value];
	if (![db update:sql error:&error])
		LOG_ERROR("Compaction error for row: %s", STR(error.localizedFailureReason));
}

- (BOOL)validateMenuItem:(NSMenuItem*)item
{
	BOOL enabled = true;
	
	if (item.action == @selector(changeRating:))
	{
		[item setState:[_rating compare:item.title] == NSOrderedSame];
		enabled = _files != nil;
	}
	else if (item.action == @selector(toggleTag:) || item.action == @selector(toggleNoneTag:))
	{
		[item setState:[_tags containsObject:item.title]];
	}
	else if (item.action == @selector(toggleUncategorizedTag:))
	{
		[item setState:_includeUncategorized];
	}
	
	return enabled;
}

static OSStatus OnHotKeyEvent(EventHandlerCallRef nextHandler, EventRef theEvent, void *userData)
{
    EventHotKeyID key;
    GetEventParameter(theEvent, kEventParamDirectObject, typeEventHotKeyID, NULL, sizeof(key), NULL, &key);
	
    AppDelegate* delegate = [NSApp delegate];
    switch (key.id)
	{
        case 1:
			[delegate prevImage:delegate];
			[delegate->_timer setFireDate:[NSDate dateWithTimeIntervalSinceNow:DefaultInterval]];
			break;
			
        case 2:
			[delegate nextImage:delegate];
			[delegate->_timer setFireDate:[NSDate dateWithTimeIntervalSinceNow:DefaultInterval]];
			break;
    }
	
    return noErr;
}

- (void)_registerHotKeys
{
	const uint F18 = 79;		// TODO: may want a pref for these
	const uint F19 = 80;
	
    EventHotKeyRef ref;
    EventHotKeyID key;
    EventTypeSpec type;
    type.eventClass = kEventClassKeyboard;
    type.eventKind = kEventHotKeyPressed;
	
    InstallApplicationEventHandler(&OnHotKeyEvent, 1, &type, NULL, NULL);
	
    key.signature = 'shf1';
    key.id = 1;
    RegisterEventHotKey(F18, 0, key, GetApplicationEventTarget(), 0, &ref);
	
    key.signature = 'shf2';
    key.id = 2;
    RegisterEventHotKey(F19, 0, key, GetApplicationEventTarget(), 0, &ref);
}

@end
