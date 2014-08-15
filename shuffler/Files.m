#import "Files.h"

#import "Database.h"
#import "Glob.h"

const NSUInteger NormalRating        = 0;
const NSUInteger GoodRating          = 1;
const NSUInteger GreatRating         = 2;
const NSUInteger FantasticRating     = 3;
const NSUInteger UncategorizedRating = 4;

const NSUInteger WorstRating = NormalRating;
const NSUInteger TopRating   = UncategorizedRating;

static NSUInteger nameToRating(NSString* name)
{
	if ([name compare:@"Normal"] == NSOrderedSame)
		return NormalRating;
	
	else if ([name compare:@"Good"] == NSOrderedSame)
		return GoodRating;
	
	else if ([name compare:@"Great"] == NSOrderedSame)
		return GreatRating;
	
	else if ([name compare:@"Fantastic"] == NSOrderedSame)
		return FantasticRating;
	
	ASSERT(false);
}

NSString* ratingToName(NSUInteger rating)
{
	if (rating == NormalRating)
		return @"Normal";
	
	else if (rating == GoodRating)
		return @"Good";
	
	else if (rating == GreatRating)
		return @"Great";
	
	else if (rating == FantasticRating)
		return @"Fantastic";
	
	else if (rating == UncategorizedRating)
		return @"Uncategorized";

	ASSERT(false);
}

// This is created within a thread and then handed off to the main thread.
@implementation Files
{
	NSString* _root;
	Database* _database;
	Glob* _glob;
	FSEventStreamRef _watcher;
	
	NSUInteger _currentRating;
	NSArray* _currentTags;
	bool _includeUncategorized;
	NSUInteger _numShown[TopRating+1];	// [count]
}

static void watchCallback(ConstFSEventStreamRef streamRef,
						  void *info,
						  size_t numEvents,
						  void *eventPaths,
						  const FSEventStreamEventFlags eventFlags[],
						  const FSEventStreamEventId eventIds[])
{
	Files* files = (__bridge Files*) info;
		
	const char** paths = (const char**)eventPaths;
	for (size_t i = 0; i < numEvents; ++i)
	{
		NSString* path = [NSString stringWithUTF8String:paths[i]];
		[files _changed:path];
	}
}

- (id)init:(NSString*)dirPath dbPath:(NSString*)dbPath
{
	self = [super init];
	
	if (self)
	{
		_root = [dbPath stringByDeletingLastPathComponent];
		[self _createDatabase:dbPath];

		// See https://developer.apple.com/library/mac/documentation/Cocoa/Reference/ApplicationKit/Classes/nsimagerep_Class/Reference/Reference.html#//apple_ref/occ/clm/NSImageRep/imageRepWithContentsOfFile:
		NSArray* globs = @[@"*.tiff", @"*.gif", @"*.jpg", @"*.jpeg", @"*.pict", @"*.pdf", @"*.eps", @"*.png"];
		_glob = [[Glob alloc] initWithGlobs:globs];
		
		_currentTags = @[];
		_includeUncategorized = true;
		
		[self _addUncategorized:dirPath database:_database];	// TODO: popup a directory picker if nothing was found
		
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

- (NSString*)root
{
	return _root;
}

- (void)_changed:(NSString*)path
{
	[self _addUncategorized:path database:_database];
	[[NSNotificationCenter defaultCenter] postNotificationName:@"Stats Changed" object:self];
}

- (void)trashedCategorizedFile:(NSString*)path withRating:(NSString*)rating
{
	NSUInteger index = nameToRating(rating);
	if (index >= _currentRating)
	{
		_numShown[index] -= 1;
		
		[self _removePathFromDatabase:path];
		[[NSNotificationCenter defaultCenter] postNotificationName:@"Stats Changed" object:self];
	}
}

- (void)trashedUncategorizedFile:(NSString*)path
{
	if (_includeUncategorized)
	{
		if (_numShown[UncategorizedRating] > 0)		// this can be zero if we've just changed how we are filtering
			_numShown[UncategorizedRating] -= 1;

		[self _removePathFromDatabase:path];
		[[NSNotificationCenter defaultCenter] postNotificationName:@"Stats Changed" object:self];
	}
}

- (void)_removePathFromDatabase:(NSString*)path
{
	NSString* hash = @"";
	NSError* error = nil;
	NSString* sql = [NSString stringWithFormat:@"SELECT hash FROM ImagePaths WHERE path == \"%@\"", path];
	NSMutableArray* rows = [_database queryRows1:sql error:&error];
	if (rows && rows.count == 1)
	{
		hash = rows[0];
	}
	else
	{
		LOG_ERROR("'%s' query failed: %s", STR(sql), STR(error.localizedFailureReason));
	}
	
	if (hash.length > 0)
	{
		sql = [NSString stringWithFormat:@"DELETE FROM Appearance WHERE hash == \"%@\"", hash];
		if (![_database update:sql error:&error])
		{
			LOG_ERROR("'%s' update failed: %s", STR(sql), STR(error.localizedFailureReason));
		}

		sql = [NSString stringWithFormat:@"DELETE FROM Indexing WHERE hash == \"%@\"", hash];
		if (![_database update:sql error:&error])
		{
			LOG_ERROR("'%s' update failed: %s", STR(sql), STR(error.localizedFailureReason));
		}
	}

	sql = [NSString stringWithFormat:@"DELETE FROM ImagePaths WHERE path == \"%@\"", path];
	if (![_database update:sql error:&error])
	{
		LOG_ERROR("'%s' update failed: %s", STR(sql), STR(error.localizedFailureReason));
	}
}

- (void)changedRatingFrom:(NSString*)oldRating to:(NSString*)newRating
{
	bool changed = false;
	
	NSUInteger index = nameToRating(oldRating);
	if (index >= _currentRating)
	{
		_numShown[index] -= 1;
		changed = true;
	}

	index = nameToRating(newRating);
	if (index >= _currentRating)
	{
		_numShown[index] += 1;
		changed = true;
	}
	
	if (changed)
		[[NSNotificationCenter defaultCenter] postNotificationName:@"Stats Changed" object:self];
}

- (void)changedUncategorizedToCategorized:(NSString*)rating
{
	bool changed = false;

	if (_includeUncategorized)
	{
		if (_numShown[UncategorizedRating] > 0)		// this can be zero if we've just changed how we are filtering
			_numShown[UncategorizedRating] -= 1;
		changed = true;
	}

	NSUInteger index = nameToRating(rating);
	if (index >= _currentRating)
	{
		_numShown[index] += 1;
		changed = true;
	}

	if (changed)
		[[NSNotificationCenter defaultCenter] postNotificationName:@"Stats Changed" object:self];
}

// Note that this is main thread code.
- (bool)filterBy:(NSString*)ratingName andTags:(NSArray*)tags includeUncategorized:(bool)includeUncategorized
{
	NSUInteger rating = nameToRating(ratingName);
	if (rating != _currentRating || ![tags isEqualToArray:_currentTags] || includeUncategorized !=_includeUncategorized)
	{
		_currentRating = rating;
		_currentTags = [tags copy];
		_includeUncategorized = includeUncategorized;
		
		for (NSUInteger i = 0; i <= TopRating; ++i)
			_numShown[i] = 0;
			
		[[NSNotificationCenter defaultCenter] postNotificationName:@"Stats Changed" object:self];
	}

	NSString* sql = [NSString stringWithFormat:@"%@ LIMIT 1", [self _getCountQuery]];
	NSUInteger count = [self _runCountQuery:sql];
	if (count == 0 && _includeUncategorized)
	{
		sql = [NSString stringWithFormat:@"%@ LIMIT 1", [self _getCountUncategorizedQuery]];
		count = [self _runCountQuery:sql];
	}
	return count > 0;
}

- (NSUInteger)numShownForRating:(NSUInteger)rating
{
	ASSERT(rating <= TopRating);
	return _numShown[rating];
}

- (NSUInteger)totalForRating:(NSUInteger)rating
{
	ASSERT(rating <= TopRating);
	
	NSUInteger count = 0;
	
	if (rating >= _currentRating)
	{
		NSString* sql;
		if (rating != UncategorizedRating)
		{
			NSString* name = ratingToName(rating);
			sql = [self _getCountQueryForRating:name];
		}
		else if (_includeUncategorized)
		{
			sql = [self _getCountUncategorizedQuery];
		}
		
		count = [self _runCountQuery:sql];
	}
	
	return count;
}

- (NSUInteger)numFiltered
{
	NSString* sql = [self _getCountQuery];
	NSUInteger count = [self _runCountQuery:sql];
	
	if (_includeUncategorized)
	{
		sql = [self _getCountUncategorizedQuery];
		count += [self _runCountQuery:sql];
	}
	
	return count;
}

- (NSUInteger)numWithNoFilter
{
	NSString* sql = @"SELECT COUNT(path) FROM ImagePaths";
	
	return [self _runCountQuery:sql];
}

static long ratingToWeight(NSUInteger rating)
{
	long scaling = 5;			// fantastic images are 125x more likely to appear than normal images
	
	long weight = 1;
	for (NSUInteger i = NormalRating; i <= TopRating; ++i)
	{
		weight *= scaling;
	}
	
	return weight;
}

- (NSString*)randomPath:(NSArray*)shown
{
	NSString* path = nil;
	
//	double startTime = getTime();
	NSMutableArray* rows = [NSMutableArray new];
	
	NSError* error = nil;
	NSString* sql;
	if (_includeUncategorized && random() % 2 == 1)
	{
		// If we land here and find a useable image we'll always pick it
		// because they have max weight.
		sql = [NSString stringWithFormat:@"%@ ORDER BY RANDOM() LIMIT 50", [self _getUncategorizedQuery]];
		[rows addObjectsFromArray:[_database queryRows:sql error:&error]];
	}
	
	sql = [NSString stringWithFormat:@"%@ ORDER BY RANDOM() LIMIT 300", [self _getQuery]];
	[rows addObjectsFromArray:[_database queryRows:sql error:&error]];

	if (rows && rows.count > 0)
	{
		long weight = ratingToWeight(TopRating);

		NSFileManager* fm = [NSFileManager defaultManager];
		NSString* fallback = nil;
		NSUInteger fallbackRating = 0;
		for (NSUInteger i = 0; i < rows.count && path == nil; ++i)
		{
			NSArray* row = rows[i];
			NSString* candidate = row[0];
			if ([fm fileExistsAtPath:candidate])
			{
				NSString* tmp = row[1];
				NSUInteger rating = (NSUInteger) [tmp integerValue];
				fallback = candidate;
				fallbackRating = rating;
				
				if (![shown containsObject:candidate])
				{
					weight -= ratingToWeight(rating);
					if (weight <= 0)
					{
						path = candidate;
						_numShown[rating] += 1;
						
						[[NSNotificationCenter defaultCenter] postNotificationName:@"Stats Changed" object:self];
					}
				}
			}
			else
			{
				[self _removePathFromDatabase:candidate];
			}
		}
		
		if (!path && fallback)
		{
			LOG_NORMAL("Showing a path that has already been shown");
			path = fallback;
			_numShown[fallbackRating] += 1;
			
			[[NSNotificationCenter defaultCenter] postNotificationName:@"Stats Changed" object:self];
		}
				
//		double elapsed = getTime() - startTime;
//		LOG_VERBOSE("ran queries in %.1fs", elapsed);
	}
	else
	{
		LOG_ERROR("'%s' query failed: %s", STR(sql), STR(error.localizedFailureReason));
	}
	
	return path;
}

- (NSUInteger)_runCountQuery:(NSString*)sql
{
	NSError* error = nil;
	NSUInteger count = 0;
	NSMutableArray* rows = [_database queryRows1:sql error:&error];
	if (rows && rows.count == 1)
	{
		NSString* text = rows[0];
		count = (NSUInteger) [text integerValue];
	}
	else
	{
		LOG_ERROR("'%s' query failed: %s", STR(sql), STR(error.localizedFailureReason));
	}
	
	return count;
}

- (NSString*)_getCountQueryForRating:(NSString*)rating
{
	NSMutableArray* predicates = [NSMutableArray new];
	
	int level = (int) nameToRating(rating);
	[predicates addObject:[NSString stringWithFormat:@"rating == %d", level]];
	
	[self _addTagsPredicates:predicates];
	[predicates addObject:@"Indexing.hash == ImagePaths.hash"];
	
	NSString* sql = [NSString stringWithFormat:@"SELECT COUNT(path) FROM Indexing, ImagePaths WHERE %@",
					 [predicates componentsJoinedByString:@" AND "]];
	
	return sql;
}

- (NSString*)_getCountQuery
{
	NSMutableArray* predicates = [NSMutableArray new];
	
	if (_currentRating > NormalRating)
		[predicates addObject:[NSString stringWithFormat:@"rating >= %lu", (unsigned long)_currentRating]];
	
	[self _addTagsPredicates:predicates];
	[predicates addObject:@"Indexing.hash == ImagePaths.hash"];
	
	NSString* sql = [NSString stringWithFormat:@"SELECT COUNT(path) FROM Indexing, ImagePaths WHERE %@",
					 [predicates componentsJoinedByString:@" AND "]];
	
	return sql;
}

- (NSString*)_getQuery
{
	NSMutableArray* predicates = [NSMutableArray new];
	
	if (_currentRating > NormalRating)
		[predicates addObject:[NSString stringWithFormat:@"rating >= %lu", (unsigned long)_currentRating]];
	
	[self _addTagsPredicates:predicates];
	[predicates addObject:@"Indexing.hash == ImagePaths.hash"];
	
	NSString* sql = [NSString stringWithFormat:@"SELECT path, rating FROM Indexing, ImagePaths WHERE %@",
					 [predicates componentsJoinedByString:@" AND "]];
	//LOG_VERBOSE("%s", STR(sql));
	
	return sql;
}

// Much faster to do these via separate qeurries.
- (NSString*)_getCountUncategorizedQuery
{
	NSString* sql = @"SELECT COUNT(path) FROM ImagePaths WHERE length(hash) == 0";
	
	return sql;
}

- (NSString*)_getUncategorizedQuery
{
	NSString* sql = @"SELECT path, 4 FROM ImagePaths WHERE length(hash) == 0";	// 4 == uncategorized
	//LOG_VERBOSE("%s", STR(sql));
	
	return sql;
}

- (void)_addTagsPredicates:(NSMutableArray*)predicates
{
	NSArray* clauses = [self _getTagsClauses:_currentTags];
	if (clauses.count == 1)
	{
		[predicates addObject:clauses[0]];
	}
	else if (clauses.count > 1)
	{
		NSString* clause = [clauses componentsJoinedByString:@" OR "];
		[predicates addObject:[NSString stringWithFormat:@"(%@)", clause]];
	}
}

- (NSArray*)_getTagsClauses:(NSArray*)tags
{
	NSMutableArray* clauses = [NSMutableArray new];
	
	if (tags.count > 0)
	{
		tags = [tags map:^id(NSString* tag) {return [NSString stringWithFormat:@"*%@:*", tag];}];
		NSString* globs = [tags componentsJoinedByString:@""];
		[clauses addObject:[NSString stringWithFormat:@"tags GLOB '%@'", globs]];
	}
	
	return clauses;
}

- (void)_addUncategorized:(NSString*)root database:(Database*)database;
{
	LOG_NORMAL("loading images from '%s'", STR(root));
	double startTime = getTime();
	
	NSError* error = nil;
	__block NSUInteger count = 0;
	[self _enumerateDeepDir:root glob:_glob error:&error block:
		^(NSString *path)
		{
			if ([_glob matchName:path.lastPathComponent] == 1)
			{
				++count;
				[database insertOrIgnore:@"ImagePaths" values:@[path, @""]];
			}
			else
			{
				LOG_NORMAL("skipping '%s' (doesn't match image globs)", STR(path.lastPathComponent));
			}
		}];
		
	double elapsed = getTime() - startTime;
	LOG_NORMAL("found %lu images in %.1fs", count, elapsed);
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


- (void)_createDatabase:(NSString*)dbPath
{
	if (dbPath)
	{
		// We're executing within a thread so we need our own Database instance.
		NSError* error = nil;
		_database = [[Database alloc] initWithPath:dbPath error:&error];
		if (!_database)
			LOG_ERROR("Couldn't create the database at '%s': %s", STR(dbPath), STR(error.localizedFailureReason));
	}
	
	if (_database)
	{
		NSUInteger count = [self _runCountQuery:@"SELECT COUNT(name) FROM Tags"];
		if (count == 0)
		{
			LOG_NORMAL("Adding default tags");
			[_database insertOrIgnore:@"Tags" values:@[@"Animals"]];
			[_database insertOrIgnore:@"Tags" values:@[@"Art"]];
			[_database insertOrIgnore:@"Tags" values:@[@"Celebrities"]];
			[_database insertOrIgnore:@"Tags" values:@[@"Fantasy"]];
			[_database insertOrIgnore:@"Tags" values:@[@"Nature"]];
			[_database insertOrIgnore:@"Tags" values:@[@"Sports"]];
		}
	}
}

@end
