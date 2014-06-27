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
	Files* _files;
	NSMutableArray* _history;
	NSUInteger _index;
	UIController* _controller;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	NSDictionary* initialSettings = @{
		@"tags": @[@"Animals", @"Art", @"Celebrities", @"Fantasy", @"Movies", @"Nature", @"Sports"],
		@"root": @"~/Pictures"};
	[defaults registerDefaults:initialSettings];
	
	_history = [NSMutableArray new];
	_timer = [NSTimer scheduledTimerWithTimeInterval:DefaultInterval target:self selector:@selector(_selectNewImage) userInfo:nil repeats:true];
	
	NSString* dbPath = [self _findDbPath];
	_controller = [[UIController alloc] init:_window dbPath:dbPath];
	
	[_controller.window setTitle:@"Scanning…"];
	[self _registerHotKeys];
		
	dispatch_queue_t concurrent = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	dispatch_queue_t main = dispatch_get_main_queue();
	dispatch_async(concurrent,
	   ^{
		   NSString* root = [defaults stringForKey:@"root"];
		   root = [root stringByStandardizingPath];
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
	_history = [NSMutableArray new];
	_index = 0;
	
	[self _selectNewImage];
	[self.window display];		// not sure why we need this, but without it we don't see the very first image
}

// TODO: need to update UI window when the image changes
- (void)_selectNewImage
{
	if (_files)
	{
		if (_history.count == 0 || _index+1 == _history.count)
		{
			NSString* path = [_files randomImagePath];
			[_controller setPath:path];
			
			[_history addObject:path];
			if (_history.count > 2*MaxHistory)
				[_history removeObjectsInRange:NSMakeRange(0, MaxHistory)];
			
			_index = _history.count - 1;
		}
		else
		{
			[self _nextImage];
		}
	}
}

- (void)_prevImage
{
	if (_files)
	{
		if (_index > 0)
			[_controller setPath:_history[--_index]];
		else
			NSBeep();
	}
}

- (void)_nextImage
{
	if (_files)
	{
		if (_index+1 < _history.count)
			[_controller setPath:_history[++_index]];
		else
			[self _selectNewImage];
	}
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

- (NSString*)_findDbPath
{
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
	
	return path;
}

@end
