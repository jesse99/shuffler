#import "NewTagController.h"

@implementation NewTagController

- (id)init
{
	self = [super initWithWindowNibName:@"NewTag"];

	if (self)
	{
		[self showWindow:self];
		[self.window makeKeyAndOrderFront:NSApp];
	}
	
	return self;
}

- (IBAction)pressedOK:(id)sender
{
	[self.window close];
	[NSApp stopModalWithCode:NSOKButton];
}

- (IBAction)pressedCancel:(id)sender
{
	[self.window close];
	[NSApp stopModalWithCode:NSCancelButton];
}

@end
