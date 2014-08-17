#import "ImageProtocol.h"

// Used to interact with images stored in an arbitrary location
// (e.g. the file system or a web site).
@protocol StoreProtocol <NSObject>

// Returns true if the path or URL still exists.
- (bool)exists:(NSString*)path;

// Path should be appripate for the store, typically either a
// file system path or an URL.
- (id<ImageProtocol>)create:(NSString*)path;

// Enumerates over all the images in the store. Returns false if the images
// could not be enumerated.
- (bool)enumerate:(void (^)(id<ImageProtocol> image))block;

// True if images can be permanently deleted instead of black listed.
@property (readonly) bool canDeleteImages;

// Short description of the store.
@property (readonly) NSString* name;

@property (readonly) NSString* dbPath;

@end
