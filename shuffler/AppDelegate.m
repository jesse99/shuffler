#import "AppDelegate.h"

#include "Carbon/Carbon.h"

#import "Files.h"
#import "MainWindow.h"
#import "UIController.h"

const double DefaultInterval = 60.0;		// TODO: use a pref for the delay
const NSUInteger MaxHistory = 500;

@implementation AppDelegate
{
	NSTimer* _timer;
	UIController* _controller;

	Files* _files;
	NSString* _rating;
	NSMutableArray* _tags;
	bool _includeNone;
	bool _includeUncategorized;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	NSDictionary* initialSettings = @{
		@"tags": @[@"Animals", @"Art", @"Celebrities", @"Fantasy", @"Movies", @"Nature", @"Sports"],
		@"root": @"~/Pictures"};
	[defaults registerDefaults:initialSettings];
		
	_rating = @"Normal";
	_tags = [NSMutableArray new];
	_timer = [NSTimer scheduledTimerWithTimeInterval:DefaultInterval target:self selector:@selector(_nextImage) userInfo:nil repeats:true];
	
	NSString* root = [defaults stringForKey:@"root"];
	root = [root stringByStandardizingPath];
	NSString* dbPath = [root stringByAppendingPathComponent:@"shuffler.db"];
	_controller = [[UIController alloc] init:_window dbPath:dbPath];
	
	NSArray* tags = [[defaults arrayForKey:@"tags"] reverse];
	for (NSString* tag in tags)
	{
		NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:tag action:@selector(toggleTag:) keyEquivalent:@""];
		[_tagsMenu insertItem:item atIndex:0];
	}
	
	[_controller.window setTitle:@"Scanning…"];
	[self _registerHotKeys];
		
	dispatch_queue_t concurrent = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	dispatch_queue_t main = dispatch_get_main_queue();
	dispatch_async(concurrent,
	   ^{
		   Files* files = [[Files alloc] init:root dbPath:dbPath];
		 
		   dispatch_async(main, ^{[self _displayInitial:files];});
	   });
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	[defaults synchronize];
}

- (void)_displayInitial:(Files*)files
{
	_files = files;
	
	if (_files && _files.numFiltered > 0)
	{
		[self _nextImage];
		[self.window display];		// not sure why we need this, but without it we don't see the very first image
	}
	else
	{
		if (_files.numUnfiltered == 0)
			[_controller.window setTitle:@"No Files"];
		else
			[_controller.window setTitle:@"No Matches"];
	}
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
	NSString* path = _controller.path;
	
	[self _nextImage];
	[_timer setFireDate:[NSDate dateWithTimeIntervalSinceNow:DefaultInterval]];
	
	NSURL* url = [[NSURL alloc] initFileURLWithPath:path];
	NSURL* newURL = nil;
	NSError* error = nil;
	BOOL trashed = [[NSFileManager defaultManager] trashItemAtURL:url resultingItemURL:&newURL error:&error];
	if (!trashed)
		LOG_ERROR("failed to trash %s: %s", STR(path), STR(error.localizedFailureReason));
}

- (IBAction)changeRating:(NSMenuItem *)sender
{
	if (_files && [_rating compare:sender.title] != NSOrderedSame)
	{
		_rating = sender.title;
		
		// For now we do this in the main thread because it gets all squirrelly if
		// we queue up multiple threads and have them finish at different times.
		if (![_files filterBy:_rating andTags:_tags withNone:_includeNone withUncategorized:_includeUncategorized])
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
		[_tags addObject:tag];
		[_tags sortUsingSelector:@selector(compare:)];
	}

	if (![_files filterBy:_rating andTags:_tags withNone:_includeNone withUncategorized:_includeUncategorized])
		[_controller.window setTitle:@"No Matches"];
}

- (IBAction)toggleNoneTag:(id)sender
{
	_includeNone = !_includeNone;
	if (![_files filterBy:_rating andTags:_tags withNone:_includeNone withUncategorized:_includeUncategorized])
		[_controller.window setTitle:@"No Matches"];
}

- (IBAction)toggleUncategorizedTag:(id)sender
{
	_includeUncategorized = !_includeUncategorized;
	if (![_files filterBy:_rating andTags:_tags withNone:_includeNone withUncategorized:_includeUncategorized])
		[_controller.window setTitle:@"No Matches"];
}

- (void)_nextImage
{
	if (_files)
	{
		NSString* path = [_files nextPath];
		if (path)
			[_controller setPath:path];
		else
			NSBeep();
	}
}

- (void)_prevImage
{
	if (_files)
	{
		NSString* path = [_files prevPath];
		if (path)
			[_controller setPath:path];
		else
			NSBeep();
	}
}

- (BOOL)validateMenuItem:(NSMenuItem*)item
{
	BOOL enabled = true;
	
	if (item.action == @selector(changeRating:))
	{
		[item setState:[_rating compare:item.title] == NSOrderedSame];
		enabled = _files != nil;
	}
	else if (item.action == @selector(toggleTag:))
	{
		[item setState:[_tags containsObject:item.title]];
	}
	else if (item.action == @selector(toggleNoneTag:))
	{
		[item setState:_includeNone];
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
			[delegate _prevImage];
			[delegate->_timer setFireDate:[NSDate dateWithTimeIntervalSinceNow:DefaultInterval]];
			break;
			
        case 2:
			[delegate _nextImage];
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
