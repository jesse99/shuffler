#import "ImageProtocol.h"

@interface FileSytemImage : NSObject <ImageProtocol>

- (id)init:(NSString*)path;

- (NSData*)load;

- (void)open;
- (void)showInFinder;
- (bool)trash:(NSError**)error;

- (NSString*)description;

@property (readonly) NSString* name;
@property (readonly) NSString* path;

@end
