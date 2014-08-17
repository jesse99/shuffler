#import "ImageProtocol.h"

@class MainWindow;

@interface UIController : NSWindowController

- (id)init:(MainWindow*)window dbPath:(NSString*)dbPath;

- (void)trashedFile:(id<ImageProtocol>)image;
- (void)setImage:(id<ImageProtocol>)image;

- (IBAction)selectRating:(id)sender;
- (IBAction)selectScaling:(id)sender;
- (IBAction)selectNoneTag:(NSMenuItem*)sender;
- (IBAction)selectNewTag:(NSMenuItem*)sender;

- (NSArray*)getDatabaseTags;

@property (strong) IBOutlet NSPopUpButton *ratingPopup;
@property (strong) IBOutlet NSPopUpButton *scalingPopup;
@property (strong) IBOutlet NSPopUpButton *tagsPopup;
@property (strong) IBOutlet NSMenu *tagsMenu;
@property (strong) IBOutlet NSTextField *tagsLabel;

@property (readonly) id<ImageProtocol> image;

@end
