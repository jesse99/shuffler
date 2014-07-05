@class MainWindow;

@interface UIController : NSWindowController

- (id)init:(MainWindow*)window dbPath:(NSString*)dbPath;

- (void)setPath:(NSString*)path;

- (IBAction)selectRating:(id)sender;
- (IBAction)selectScaling:(id)sender;
- (IBAction)selectNoneTag:(NSMenuItem*)sender;
- (IBAction)selectNewTag:(NSMenuItem*)sender;

@property (strong) IBOutlet NSPopUpButton *ratingPopup;
@property (strong) IBOutlet NSPopUpButton *scalingPopup;
@property (strong) IBOutlet NSPopUpButton *tagsPopup;
@property (strong) IBOutlet NSMenu *tagsMenu;
@property (strong) IBOutlet NSTextField *tagsLabel;

@property (readonly) NSString *path;

@end
