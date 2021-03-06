#import "AppDelegate.h"

#include "Carbon/Carbon.h"

#import "Database.h"
#import "FileSystemStore.h"
#import "ImgurStore.h"
#import "InfoController.h"
#import "MainWindow.h"
#import "UIController.h"

const NSUInteger MaxHistory = 500;

@implementation AppDelegate
{
	NSTimer* _timer;
	UIController* _controller;
	NSInteger _interval;

	NSMutableArray* _shown;
	NSUInteger _index;
	
	id<StoreProtocol> _store;
	Gallery* _gallery;
	NSString* _rating;
	NSMutableArray* _tags;
	bool _includeUncategorized;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
	[self _saveDefaultPrefs];
	
	_rating = @"Normal";
	_tags = [NSMutableArray new];
	_includeUncategorized = true;
	
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	_interval = [defaults integerForKey:@"interval"];
	_timer = [NSTimer scheduledTimerWithTimeInterval:_interval target:self selector:@selector(nextImage:) userInfo:nil repeats:true];
	_shown = [NSMutableArray new];
	
	NSString* root = [defaults stringForKey:@"root"];
	_store = [[FileSystemStore alloc] init:root];

	//root = @"/tmp";				// XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	//_store = [[ImgurStore alloc] init:root];
	[self setStore:@"User Pictures"];
	
	_controller = [[UIController alloc] init:_window dbPath:_store.dbPath];
	
	[self initDatabaseMenu];
	[self reloadTagsMenu];
	
	[_controller.window setTitle:@"Scanning…"];
	[self _registerHotKeys];
		
	dispatch_queue_t concurrent = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	dispatch_queue_t main = dispatch_get_main_queue();
	dispatch_async(concurrent,
	   ^{
           Gallery* gallery = [[Gallery alloc] init:self->_store.dbPath];
		   [gallery spinup:
			   ^{
				   dispatch_async(main, ^{
                       [self _displayInitial:gallery];
                       [self useScreen2:self];
                   });
			   }];
	   });
}

- (void)initDatabaseMenu
{
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	NSDictionary* stores = [defaults dictionaryForKey:@"stores"];

	NSMutableArray* names = [NSMutableArray new];
	for (NSString* name in stores)
	{
		[names addObject:name];
	}
	[names sortUsingSelector:@selector(compare:)];

	for (NSString* name in names)
	{
		NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:name action:@selector(changeStore:) keyEquivalent:@""];
		[_databaseMenu addItem:item];
	}
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

- (void)_displayInitial:(Gallery*)gallery
{
	_gallery = gallery;
		
	if (_gallery && _gallery.numWithNoFilter > 0)
		(void) [_gallery filterBy:_rating andTags:_tags includeUncategorized:_includeUncategorized];
	
	if (_gallery && _gallery.numFiltered > 0)
	{
		[self nextImage:self];
		[self.window display];		// not sure why we need this, but without it we don't see the very first image
	}
	else
	{
		if (_gallery.numWithNoFilter == 0)
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
	if (_store.canDeleteImages)
		[self compactDatabase];
	
	[InfoController show];
}

- (IBAction)copyPath:(id)sender
{
	NSString* path = _controller.image.path;
	
	NSPasteboard* pb = [NSPasteboard generalPasteboard];
	NSArray* types = @[NSStringPboardType];
	[pb declareTypes:types owner:self];
	
	[pb setString:path forType:NSStringPboardType];
}

- (IBAction)openFile:(id)sender
{
	[_controller.image open];
}

- (IBAction)showFileInFinder:(id)sender
{
	[_controller.image showInFinder];
}

- (IBAction)trashFile:(id)sender
{
	if (_index < _shown.count)
	{
		id<ImageProtocol> image = _shown[_index];
		[_shown removeObjectAtIndex:_index];
		--_index;
		
		[self nextImage:self];
		[self rescheduleTimer];
		
		NSError* error = nil;
		BOOL trashed = [image trash:&error];
		if (trashed)
			[_controller trashedFile:image];
		else
			LOG_ERROR("failed to trash %s: %s", STR(image), STR(error.localizedFailureReason));
	}
	else
	{
		NSBeep();
	}
}

- (IBAction)setInterval:(NSMenuItem*)sender
{
	if (sender.tag != _interval)
	{
		_interval = sender.tag;
		
		NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
		[defaults setInteger:_interval forKey:@"interval"];
		[defaults synchronize];
	}

	[self rescheduleTimer];
}

- (void)rescheduleTimer
{
	[_timer setFireDate:[NSDate dateWithTimeIntervalSinceNow:_interval]];
}

// This gets a bit confusing but these rating and tags apply to what we will show
// not to the current image. The settings that apply to the current image are set
// in UIController.
- (IBAction)changeRating:(NSMenuItem *)sender
{
	if (_gallery && [_rating compare:sender.title] != NSOrderedSame)
	{		
		_rating = sender.title;
		
		// For now we do this in the main thread because it gets all squirrelly if
		// we queue up multiple threads and have them finish at different times.
		if (![_gallery filterBy:_rating andTags:_tags includeUncategorized:_includeUncategorized])
			[_controller.window setTitle:@"No Matches"];
	}
}

- (void)changeStore:(NSMenuItem*)sender
{
	[self setStore:sender.title];
}

- (void)setStore:(NSString*)name
{
//	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
//	NSDictionary* stores = [defaults dictionaryForKey:@"stores"];
//	NSDictionary* store = stores[sender.title];
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

	if (![_gallery filterBy:_rating andTags:_tags includeUncategorized:_includeUncategorized])
		[_controller.window setTitle:@"No Matches"];
}

- (IBAction)toggleNoneTag:(id)sender
{
	[_tags removeAllObjects];
	[_tags addObject:@"None"];
	
	if (![_gallery filterBy:_rating andTags:_tags includeUncategorized:_includeUncategorized])
		[_controller.window setTitle:@"No Matches"];
}

- (IBAction)toggleUncategorizedTag:(id)sender
{
	_includeUncategorized = !_includeUncategorized;
	if (![_gallery filterBy:_rating andTags:_tags includeUncategorized:_includeUncategorized])
		[_controller.window setTitle:@"No Matches"];
}

- (IBAction)nextImage:(id)sender
{
	if (_gallery)
	{
		id<ImageProtocol> image = nil;
		if (_index + 1 < _shown.count)
		{
			image = _shown[++_index];
		}
		else
		{
			image = [_gallery randomImage:_shown];
			if (image)
			{
				[_shown addObject:image];
				
				NSUInteger max = MIN(_gallery.numFiltered/2, 2000);
				if (_shown.count > max)
					[_shown removeObjectsInRange:NSMakeRange(0, max/2)];
				
				_index = _shown.count - 1;
			}
		}
		
		if (image)
		{
			[_controller setImage:image];
			[self rescheduleTimer];
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
		id<ImageProtocol> image = _shown[--_index];
		[_controller setImage:image];
		[self rescheduleTimer];
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
           Database* db = [[Database alloc] initWithPath:self->_store.dbPath error:&error];
		   if (!db)
		   {
               LOG_ERROR("Couldn't create the database at '%s': %s", STR(self->_store.dbPath), STR(error.localizedFailureReason));
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
	NSString* sql = @"SELECT path, hash FROM ImagePaths";
	NSMutableArray* rows = [db queryRows:sql error:&error];
	for (NSUInteger i = 0; rows && i < rows.count; ++i)
	{
		NSArray* row = rows[i];
		NSString* path = row[0];
		NSString* hash = row[1];
		
		// if path does not exist then,
		if (![_store exists:path])
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

- (IBAction)useScreen1:(id)sender
{
	NSArray* screens = [NSScreen screens];
	[self.window useScreen:screens[0]];
	
	[_controller setImage:_controller.image];
}

- (IBAction)useScreen2:(id)sender
{
	NSArray* screens = [NSScreen screens];
	[self.window useScreen:screens[1]];
	
	[_controller setImage:_controller.image];
}

- (IBAction)useScreen3:(id)sender
{
    NSArray* screens = [NSScreen screens];
    [self.window useScreen:screens[2]];
    
    [_controller setImage:_controller.image];
}

- (BOOL)validateMenuItem:(NSMenuItem*)item
{
	BOOL enabled = true;
	
	if (item.action == @selector(changeRating:))
	{
		[item setState:[_rating compare:item.title] == NSOrderedSame];
		enabled = _gallery != nil;
	}
	else if (item.action == @selector(setInterval:))
	{
		[item setState:item.tag == _interval];
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
	
    AppDelegate* delegate = (AppDelegate*) [NSApp delegate];
    switch (key.id)
	{
        case 1:
			[delegate prevImage:delegate];
			[delegate rescheduleTimer];
			break;
			
        case 2:
			[delegate nextImage:delegate];
			[delegate rescheduleTimer];
			break;
    }
	
    return noErr;
}

- (void)_registerHotKeys
{
//	const uint F18 = 79;		// TODO: may want a pref for these
//	const uint F19 = 80;
    
    const uint F1 = 0x7A;
    const uint F2 = 0x78;
	
    EventHotKeyRef ref;
    EventHotKeyID key;
    EventTypeSpec type;
    type.eventClass = kEventClassKeyboard;
    type.eventKind = kEventHotKeyPressed;
	
    InstallApplicationEventHandler(&OnHotKeyEvent, 1, &type, NULL, NULL);
	
    key.signature = 'shf1';
    key.id = 1;
    RegisterEventHotKey(F1, 0, key, GetApplicationEventTarget(), 0, &ref);
	
    key.signature = 'shf2';
    key.id = 2;
    RegisterEventHotKey(F2, 0, key, GetApplicationEventTarget(), 0, &ref);
}

- (void)_saveDefaultPrefs
{
	NSDictionary* user = @{@"type": @"file system", @"paths": @[@"~/Pictures"]};
	NSDictionary* cosplay = @{@"type": @"imgur", @"albums": @[@"http://imgur.com/gallery/ywIqy"]};

	// TODO: delete this
	NSDictionary* desktop = @{@"type": @"file system", @"paths": @[@"~/Documents/Desktop Pictures"]};
//	NSDictionary* mellori = @{@"type": @"file system", @"paths": @[@"~/Documents/1000 HD Wallpapers (By Mellori Studio)"]};

	NSDictionary* initialSettings = @{@"stores": @{@"User Pictures": user, @"Desktop Pictures": desktop, @"Imgur Cosplay": cosplay}, @"interval": @60};
//	NSDictionary* initialSettings = @{@"stores": @{@"User Pictures": user, @"Mellori Wallpapers": mellori, @"Imgur Cosplay": cosplay}, @"interval": @60};
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];

	[defaults registerDefaults:initialSettings];
//	[defaults setObject:@"~/Documents/Desktop Pictures" forKey:@"root"];
	
	// TODO: delete this
//	[defaults synchronize];
}

@end
