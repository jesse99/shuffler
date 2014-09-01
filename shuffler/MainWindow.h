#import "ImageProtocol.h"

// The window which displays the current image.
@interface MainWindow : NSWindow

- (void)update:(id<ImageProtocol>)image imageData:(NSData*)data scaling:(double)scaling;

- (void)useScreen:(NSScreen*)screen;

@property (readonly) id<ImageProtocol> image;
@property (readonly) double maxScaling;
@property (strong) IBOutlet NSImageView *image1;
@property (strong) IBOutlet NSImageView *image2;

@end
