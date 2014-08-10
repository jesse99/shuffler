// The window which displays the current image.
@interface MainWindow : NSWindow

- (void)update:(NSString*)path imageData:(NSData*)data scaling:(double)scaling;

@property (readonly) NSString *path;
@property (readonly) double maxScaling;
@property (strong) IBOutlet NSImageView *image1;
@property (strong) IBOutlet NSImageView *image2;

@end
