#import <Cocoa/Cocoa.h>

@class MainWindow;

@interface AppDelegate : NSObject <NSApplicationDelegate>

@property (assign) IBOutlet MainWindow *window;
@property (strong) IBOutlet NSMenu *tagsMenu;

@end
