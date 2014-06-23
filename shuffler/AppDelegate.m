#import "AppDelegate.h"

#include "Carbon/Carbon.h"

#import "Files.h"
#import "MainWindow.h"

@implementation AppDelegate
{
	Files* _files;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	NSString* root = @"/Users/jessejones/Documents/Desktop Pictures";	// TODO: don't hard code this
	_files = [[Files alloc] init:root];
	
	[self _setDesktop];
	[self _registerHotKeys];
}

- (void)_setDesktop
{
	[self _changeDesktop];
	
	[self performSelector:@selector(_setDesktop) withObject:self afterDelay:60.0];	// TODO: use a pref for the delay
}

- (void)_changeDesktop
{
	NSString* path = [_files randomImagePath];
	[_window update:path];
}

static OSStatus OnHotKeyEvent(EventHandlerCallRef nextHandler, EventRef theEvent, void *userData)
{
    EventHotKeyID key;
    GetEventParameter(theEvent, kEventParamDirectObject, typeEventHotKeyID, NULL, sizeof(key), NULL, &key);
	
    AppDelegate* delegate = [NSApp delegate];
    switch (key.id)
	{
        case 1:
			NSBeep();
			break;
			
        case 2:
			[delegate _changeDesktop];
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
