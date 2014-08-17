#import "StoreProtocol.h"

// Used to manage images stored on disk.
@interface FileSystemStore : NSObject <StoreProtocol>

- (id)init:(NSString*)root;

- (id<ImageProtocol>)create:(NSString*)path;

- (bool)enumerate:(void (^)(NSURL* url))block;

- (NSData*)loadImage:(NSURL*)url;

@property (readonly) NSString* name;
@property (readonly) NSString* dbPath;

@end
