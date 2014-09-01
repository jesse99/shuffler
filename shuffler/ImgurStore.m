#import "ImgurStore.h"

#import "AppDelegate.h"
#import "ImgurImage.h"

@implementation ImgurStore
{
	NSString* _root;
	NSString* _dbPath;
	FSEventStreamRef _watcher;
}

- (id)init:(NSString*)root
{
	self = [super init];
	
	if (self)
	{
		_root = [root stringByStandardizingPath];
		_dbPath = [_root stringByAppendingPathComponent:@"shuffler.db"];

		[IMGSession anonymousSessionWithClientID:@"d004fa3f064cec9" withDelegate:self];
	}
	
	return self;
}

-(void)imgurSessionRateLimitExceeded
{
	LOG_ERROR("imgur rate limit exceeded");
}

-(void)imgurSessionNeedsExternalWebview:(NSURL*)url completion:(void(^)())completion
{
    //open imgur website to authenticate with callback url in safari
	[[NSWorkspace sharedWorkspace] openURL:url];
	
    //save the completion block for later use when imgur responds with url callback
}

-(void)imgurRequestFailed:(NSError*)error
{
	LOG_ERROR("imgur request failed: %s", STR(error.localizedFailureReason));
}

-(void)imgurReachabilityChanged:(AFNetworkReachabilityStatus)status
{
	LOG_ERROR("imgur reachability changed: %d", (int) status);
}

- (bool)canDeleteImages
{
	return false;
}

- (NSString*)name
{
	NSString* dirName = [_root lastPathComponent];
	return dirName;
}

- (bool)exists:(NSString*)path
{
//	NSFileManager* fm = [NSFileManager defaultManager];
//	bool exists = [fm fileExistsAtPath:path];
//	return exists;
	return true;
}

- (id<ImageProtocol>)create:(NSString*)path
{
	return [[ImgurImage alloc] init:path];
}

- (void)enumerate:(void (^)(NSString* path))block finished:(void (^)())finished
{
	[IMGAlbumRequest albumWithID:@"VCnYv" success:^(IMGAlbum *album) {
		for (IMGImage* image in album.images)
		{
			block(image.url.absoluteString);
		}
		LOG_NORMAL("found %lu images in %s", album.images.count, STR(_root));
		finished();
	} failure:^(NSError *error) {
		LOG_ERROR("found err: %s", STR(error.localizedFailureReason));
		finished();
	}];
	

#if 0
	[IMGGalleryRequest hotGalleryPage:0 success:
		^(NSArray *objects)
		{
			for (id<IMGGalleryObjectProtocol> obj in objects)
			{
				LOG_ERROR("%s", STR(obj.title));
				LOG_ERROR("   %s", STR(obj.link));
				block([NSURL URLWithString:obj.objectID]);
			}

			LOG_NORMAL("found %lu images in %s", objects.count, STR(_root));
			finished();
		}
		failure:^(NSError *error)
		{
			LOG_ERROR("found err: %s", STR(error.localizedFailureReason));
			finished();
		}];
#endif
}

@end
