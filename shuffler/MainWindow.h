// The window which displays the current image.
@interface MainWindow : NSWindow

- (void)update:(NSString*)path scaling:(double)scaling;

@property (readonly) NSString *path;
@property (strong) IBOutlet NSImageView *image1;
@property (strong) IBOutlet NSImageView *image2;

@end
