#import "Files.h"

#import "Database.h"
#import "Glob.h"

static int ratingToLevel(NSString* rating)
{
	if ([rating compare:@"Normal"] == NSOrderedSame)
		return 0;
	
	else if ([rating compare:@"Good"] == NSOrderedSame)
		return 1;
	
	else if ([rating compare:@"Great"] == NSOrderedSame)
		return 2;
	
	else if ([rating compare:@"Fantastic"] == NSOrderedSame)
		return 3;

	ASSERT(false);
}

// Note that these are created within a thread and then handed off to the main thread.
@implementation Files
{
	Database* _database;
	Glob* _glob;
	NSArray* _paths;
	NSArray* _filtered;
	NSUInteger _index;
}

- (id)init:(NSString*)dirPath dbPath:(NSString*)dbPath
{
	self = [super init];
	
	if (self)
	{
		// TODO:
		// maybe we should read the files all in and then filter by Indexing?
		// delegate could poke us when filtering changes
		_database = [self _createDatabase:dbPath];

		// See https://developer.apple.com/library/mac/documentation/Cocoa/Reference/ApplicationKit/Classes/nsimagerep_Class/Reference/Reference.html#//apple_ref/occ/clm/NSImageRep/imageRepWithContentsOfFile:
		NSArray* globs = @[@"*.tiff", @"*.gif", @"*.jpg", @"*.jpeg", @"*.pict", @"*.pdf", @"*.eps", @"*.png"];
		_glob = [[Glob alloc] initWithGlobs:globs];
		_paths = [self _findPaths:dirPath database:_database];	// TODO: popup a directory picker if nothing was found
		_filtered = _paths;
	}
	
	return self;
}

- (NSUInteger)numUnfiltered
{
	return _paths.count;
}

- (NSUInteger)numFiltered
{
	return _filtered.count;
}

- (NSString*)nextPath
{
	NSString* path = nil;
	
	if (_filtered && _filtered.count > 0)
	{
		_index = ++_index % _filtered.count;
		path = _filtered[_index];
	}
	
	return path;
}

- (NSString*)prevPath
{
	NSString* path = nil;
	
	if (_filtered && _filtered.count > 0)
	{
		_index = --_index % _filtered.count;
		path = _filtered[_index];
	}
	
	return path;
}

// Note that this is main thread code.
- (void)filterBy:(NSString*)rating
{
	double startTime = getTime();

	int level = ratingToLevel(rating);
	NSString* sql = [NSString stringWithFormat:@"\
		SELECT path\
		   FROM Indexing, ImagePaths\
		WHERE Indexing.rating >= %d AND Indexing.hash == ImagePaths.hash", level];
	
	NSError* error = nil;
	NSMutableArray* filtered = [_database queryRows1:sql error:&error];
	[filtered shuffle];
	_filtered = filtered;
	
	double elapsed = getTime() - startTime;
	if (_filtered)
		LOG_NORMAL("filtered %lu images to %lu images in %.1fs", _paths.count, _filtered.count, elapsed);
	else
		LOG_ERROR("Couldn't filter rows: %s", STR(error.localizedFailureReason));
}

- (NSArray*)_findPaths:(NSString*)root database:(Database*)database;
{
	NSMutableArray* paths = [NSMutableArray new];
	LOG_NORMAL("loading images from '%s'", STR(root));
	double startTime = getTime();
	
	NSError* error = nil;
	[self _enumerateDeepDir:root glob:_glob error:&error block:
		^(NSString *path)
		{
			if ([_glob matchName:path.lastPathComponent] == 1)
			{
				[paths addObject:path];
				[database insertOrIgnore:@"ImagePaths" values:@[path, @""]];
			}
			else
			{
				LOG_NORMAL("skipping '%s' (doesn't match image globs)", STR(path.lastPathComponent));
			}
		}];
	
	[paths shuffle];
	
	double elapsed = getTime() - startTime;
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


- (Database*)_createDatabase:(NSString*)dbPath
{
	Database* database = nil;
	
	if (dbPath)
	{
		// We're executing within a thread so we need our own Database instance.
		NSError* error = nil;
		database = [[Database alloc] initWithPath:dbPath error:&error];
		LOG_ERROR("Couldn't create the database at '%s': %s", STR(dbPath), STR(error.localizedFailureReason));
	}
		
	return database;
}

@end
