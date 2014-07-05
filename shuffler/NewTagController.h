#import <Cocoa/Cocoa.h>

@interface NewTagController : NSWindowController

- (id)init;

@property (strong) IBOutlet NSTextField *textField;

- (IBAction)pressedOK:(id)sender;
- (IBAction)pressedCancel:(id)sender;

@end
