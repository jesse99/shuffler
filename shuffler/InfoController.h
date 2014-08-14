#import <Cocoa/Cocoa.h>

@interface InfoController : NSWindowController

+ (void)show;

@property (strong) IBOutlet NSTextView *textView;

@end
