#import "ImgurImage.h"

#import "ImgurSession.h"

@implementation ImgurImage
{
	NSString* _path;
}

- (id)init:(NSString*)path
{
	self = [super init];
	
	if (self)
	{
		ASSERT(path);
		_path = path;
	}
	
	return self;
}

- (NSData*)load
{
//	NSError* error = nil;
//	IMGImage* image = [[IMGImage alloc] initWithGalleryID:_path error:&error];
//	if (!image)
//		LOG_ERROR("   %s", STR(error.localizedFailureReason));
	
	NSURL* url = [NSURL URLWithString:_path];
	NSData* data = [NSData dataWithContentsOfURL:url];
	return data;
}

- (void)open
{
	[[NSWorkspace sharedWorkspace] openFile:_path];
}

- (void)showInFinder
{
	[[NSWorkspace sharedWorkspace] selectFile:_path inFileViewerRootedAtPath:@""];
}

- (bool)trash:(NSError**)error
{
	NSURL* url = [[NSURL alloc] initFileURLWithPath:_path];
	NSURL* newURL = nil;
	return [[NSFileManager defaultManager] trashItemAtURL:url resultingItemURL:&newURL error:error];
}

- (NSString*)name
{
	return _path.lastPathComponent;
}

- (NSString*)description
{
	return _path;
}

@end
