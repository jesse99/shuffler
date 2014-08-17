#import <Cocoa/Cocoa.h>

#import "Gallery.h"
#import "StoreProtocol.h"

@class MainWindow;

@interface AppDelegate : NSObject <NSApplicationDelegate>

- (void)reloadTagsMenu;

- (void)rescheduleTimer;

@property (readonly) id<StoreProtocol> store;
@property (readonly) Gallery* gallery;

@property (assign) IBOutlet MainWindow *window;
@property (strong) IBOutlet NSMenu *tagsMenu;

@end
