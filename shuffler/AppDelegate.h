#import <Cocoa/Cocoa.h>

@class Gallery, MainWindow;

@interface AppDelegate : NSObject <NSApplicationDelegate>

- (void)reloadTagsMenu;

- (void)rescheduleTimer;

@property (readonly) Gallery* files;

@property (assign) IBOutlet MainWindow *window;
@property (strong) IBOutlet NSMenu *tagsMenu;

@end
