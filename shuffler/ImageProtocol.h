#import <Foundation/Foundation.h>

// Encapsulates a reference to an image in an arbitrary store.
@protocol ImageProtocol <NSObject>

- (NSData*)load;

- (void)open;
- (void)showInFinder;
- (bool)trash:(NSError**)error;

// For debugging (i.e. logging).
- (NSString*)description;

// Short description of the image.
@property (readonly) NSString* name;

// Normally either a file system path or an URL.
@property (readonly) NSString* path;

@end
