#import "FileSystemStore.h"

#import "AppDelegate.h"
#import "FileSytemImage.h"
#import "Glob.h"

@implementation FileSystemStore
{
	NSString* _root;
	NSString* _dbPath;
	FSEventStreamRef _watcher;
	Glob* _glob;
}

static void watchCallback(ConstFSEventStreamRef streamRef,
						  void *info,
						  size_t numEvents,
						  void *eventPaths,
						  const FSEventStreamEventFlags eventFlags[],
						  const FSEventStreamEventId eventIds[])
{
	if (numEvents > 0)
	{
		AppDelegate* app = [NSApp delegate];
		[app.gallery storeChanged];
	}
}

- (id)init:(NSString*)root
{
	self = [super init];
	
	if (self)
	{
		_root = [root stringByStandardizingPath];
		_dbPath = [_root stringByAppendingPathComponent:@"shuffler.db"];

		// See https://developer.apple.com/library/mac/documentation/Cocoa/Reference/ApplicationKit/Classes/nsimagerep_Class/Reference/Reference.html#//apple_ref/occ/clm/NSImageRep/imageRepWithContentsOfFile:
		NSArray* globs = @[@"*.tiff", @"*.gif", @"*.jpg", @"*.jpeg", @"*.pict", @"*.pdf", @"*.eps", @"*.png"];
		_glob = [[Glob alloc] initWithGlobs:globs];

		FSEventStreamContext context = {0};
		context.info = (void*) CFBridgingRetain(self);
		
		_watcher = FSEventStreamCreate(NULL, watchCallback, &context, CFBridgingRetain(@[_root]), kFSEventStreamEventIdSinceNow, 15, kFSEventStreamCreateFlagIgnoreSelf);
		FSEventStreamScheduleWithRunLoop(_watcher, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
		bool started = FSEventStreamStart(_watcher);
		if (!started)
			LOG_ERROR("Failed to create a watcher for %s", STR(_root));
	}
	
	return self;
}

- (void)dealloc
{
	if (_watcher)
	{
		FSEventStreamStop(_watcher);
		FSEventStreamInvalidate(_watcher);
		FSEventStreamRelease(_watcher);
		
		CFBridgingRelease((__bridge CFTypeRef)(self));
	}
}
	
- (NSString*)name
{
	NSString* dirName = [_root lastPathComponent];
	return dirName;
}

- (id<ImageProtocol>)create:(NSString*)path
{
	return [[FileSytemImage alloc] init:path];
}

- (bool)enumerate:(void (^)(NSURL* url))block
{
	LOG_NORMAL("enumerating images from '%s'", STR(_root));
	double startTime = getTime();
	
	NSError* error = nil;
	__block NSUInteger count = 0;
	[self _enumerateDeepDir:_root glob:_glob error:&error block:
	 ^(NSString *path)
	 {
		 if ([_glob matchName:path.lastPathComponent] == 1)
		 {
			 count++;
			 NSURL* url = [NSURL fileURLWithPath:path isDirectory:FALSE];
			 block(url);
		 }
		 else
		 {
			 LOG_NORMAL("skipping '%s' (doesn't match image globs)", STR(path.lastPathComponent));
		 }
	 }];
	
	if (count == 0 && error)
	{
		LOG_ERROR("Error enumerating '%s': %s", STR(_root), STR(error.localizedFailureReason));
	}
	
	double elapsed = getTime() - startTime;
	LOG_NORMAL("found %lu images in %.1fs", count, elapsed);
	
	return count > 0;
}

- (NSData*)loadImage:(NSURL*)url
{
	NSData* data = [NSData dataWithContentsOfFile:url.path];
	return data;
}

- (bool)_enumerateDeepDir:(NSString*)path glob:(Glob*)glob error:(NSError**)outError block:(void (^)(NSString* item))block
{
	NSFileManager* fm = [NSFileManager new];
	NSMutableArray* errors = [NSMutableArray new];
	
	NSURL* at = [NSURL fileURLWithPath:path isDirectory:YES];
	NSArray* keys = @[NSURLNameKey, NSURLIsDirectoryKey, NSURLPathKey];
	NSDirectoryEnumerationOptions options = glob ? NSDirectoryEnumerationSkipsHiddenFiles : 0;
	NSDirectoryEnumerator* enumerator = [fm enumeratorAtURL:at includingPropertiesForKeys:keys options:options errorHandler:
		 ^BOOL(NSURL* url, NSError* error)
		 {
			 NSString* reason = [error localizedFailureReason];
			 NSString* mesg = [NSString stringWithFormat:@"Couldn't process %s: %s", STR(url), STR(reason)];
			 [errors addObject:mesg];
			 
			 return YES;
		 }];
	
	for (NSURL* url in enumerator)
	{
		NSNumber* isDirectory;
		NSError* error = nil;
		BOOL populated = [url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:&error];
		
		if (populated && !isDirectory.boolValue)		// note that NSDirectoryEnumerationSkipsHiddenFiles also skips hidden directories
		{
			NSString* candidate = url.path;
			if (!glob || [glob matchName:candidate])
				block(candidate);
		}
		else if (error)
		{
			NSString* reason = [error localizedFailureReason];
			NSString* mesg = [NSString stringWithFormat:@"Couldn't check NSURLIsDirectoryKey for %s: %s", STR(url), STR(reason)];
			[errors addObject:mesg];
		}
	}
	
	if (errors.count && outError)
	{
		NSString* mesg = [errors componentsJoinedByString:@"\n"];
		NSDictionary* dict = @{NSLocalizedFailureReasonErrorKey:mesg};
		*outError = [NSError errorWithDomain:@"shuffler" code:4 userInfo:dict];
	}
	return errors.count == 0;
}

@end
