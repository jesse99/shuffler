#import <Cocoa/Cocoa.h>

@class Files, MainWindow;

@interface AppDelegate : NSObject <NSApplicationDelegate>

- (void)reloadTagsMenu;

@property (readonly) Files* files;

@property (assign) IBOutlet MainWindow *window;
@property (strong) IBOutlet NSMenu *tagsMenu;

@end
