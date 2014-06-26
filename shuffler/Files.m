#import "Files.h"

#import "Glob.h"

@implementation Files
{
	Glob* _glob;
	NSArray* _paths;
}

- (id)init:(NSString*)dirPath
{
	self = [super init];
	
	if (self)
	{
		// See https://developer.apple.com/library/mac/documentation/Cocoa/Reference/ApplicationKit/Classes/nsimagerep_Class/Reference/Reference.html#//apple_ref/occ/clm/NSImageRep/imageRepWithContentsOfFile:
		NSArray* globs = @[@"*.tiff", @"*.gif", @"*.jpg", @"*.jpeg", @"*.pict", @"*.pdf", @"*.eps", @"*.png"];
		_glob = [[Glob alloc] initWithGlobs:globs];
		_paths = [self _findPaths:dirPath];	// TODO: popup a directory picker if nothing was found
	}
	
	return self;
}

- (NSString*)randomImagePath
{
	NSUInteger index = random() % _paths.count;
	return _paths[index];
}

- (NSArray*)_findPaths:(NSString*)root;
{
	NSMutableArray* paths = [NSMutableArray new];
	LOG_NORMAL("loading images from '%s'", STR(root));
	double start_time = getTime();
	
	NSError* error = nil;
	[self _enumerateDeepDir:root glob:_glob error:&error block:
		^(NSString *item)
		{
			if ([_glob matchName:item.lastPathComponent] == 1)
				[paths addObject:item];
			else
				LOG_NORMAL("skipping '%s' (doesn't match image globs)", STR(item.lastPathComponent));
		}];
	
	double elapsed = getTime() - start_time;
	LOG_NORMAL("found %lu images in %.1fs", paths.count, elapsed);

	return paths;
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
