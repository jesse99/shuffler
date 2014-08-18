#import "StoreProtocol.h"
#import "ImgurSession.h"

// Used to manage images stored on <www.imgur.com>.
@interface ImgurStore : NSObject <StoreProtocol, IMGSessionDelegate>

- (id)init:(NSString*)root;

- (bool)exists:(NSString*)path;
- (id<ImageProtocol>)create:(NSString*)path;

- (void)enumerate:(void (^)(NSString* path))block finished:(void (^)())finished;

-(void)imgurSessionRateLimitExceeded;
-(void)imgurSessionNeedsExternalWebview:(NSURL*)url completion:(void(^)())completion;
-(void)imgurRequestFailed:(NSError*)error;
-(void)imgurReachabilityChanged:(AFNetworkReachabilityStatus)status;

@property (readonly) bool canDeleteImages;
@property (readonly) NSString* name;
@property (readonly) NSString* dbPath;

@end
