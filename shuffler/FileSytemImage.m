#import "FileSytemImage.h"

@implementation FileSytemImage
{
	NSString* _path;
}

- (id)init:(NSString*)path
{
	self = [super init];
	
	if (self)
	{
		_path = path;
	}
	
	return self;
}

- (NSData*)load
{
	NSData* data = [NSData dataWithContentsOfFile:_path];
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

- (BOOL)isEqual:(id)object
{
	if(![object isKindOfClass: [FileSytemImage class]])
		return NO;
	
	return [[object path] isEqual: _path];
}

- (NSString*)description
{
	return _path;
}

@end
