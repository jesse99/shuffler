#import "Shuffler.h"

@interface UIController : NSWindowController

- (id)init;

- (void)setPath:(NSString*)path;

- (IBAction)selectNoneTag:(NSMenuItem*)sender;
- (IBAction)selectNewTag:(NSMenuItem*)sender;

@property (strong) IBOutlet NSMenuItem *selectNoneTag;

@property (strong) IBOutlet NSPopUpButton *ratingPopup;
@property (strong) IBOutlet NSPopUpButton *scalingPopup;
@property (strong) IBOutlet NSPopUpButton *tagsPopup;
@property (strong) IBOutlet NSMenu *tagsMenu;
@property (strong) IBOutlet NSTextField *tagsLabel;

@end
