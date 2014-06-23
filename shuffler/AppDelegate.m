#import "AppDelegate.h"

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
}

- (void)_setDesktop
{
	NSString* path = [_files randomImagePath];
	[_window update:path];
	
	[self performSelector:@selector(_setDesktop) withObject:self afterDelay:30.0];	// TODO: use a pref for the delay
}

@end
