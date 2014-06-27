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
	NSDictionary* initial = @{@"tags": @[@"Animals", @"Art", @"Celebrities", @"Fantasy", @"Movies", @"Nature", @"Sports"]};
	[defaults registerDefaults:initial];
	
	NSString* root = @"/Users/jessejones/Documents/Desktop Pictures/Asian8";	// TODO: don't hard code this
	_files = [[Files alloc] init:root];
	_history = [NSMutableArray new];
	_timer = [NSTimer scheduledTimerWithTimeInterval:DefaultInterval target:self selector:@selector(_selectNewImage) userInfo:nil repeats:true];
	
	_controller = [[UIController alloc] init:_window];
	
	[self _selectNewImage];
	[self.window display];		// not sure why we need this, but without it we don't see the very first image

	[self _registerHotKeys];
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	[defaults synchronize];
}

// TODO: need to update UI window when the image changes
- (void)_selectNewImage
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

- (void)_prevImage
{
	if (_index > 0)
		[_controller setPath:_history[--_index]];
	else
		NSBeep();
}

- (void)_nextImage
{
	if (_index+1 < _history.count)
		[_controller setPath:_history[++_index]];
	else
		[self _selectNewImage];
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
