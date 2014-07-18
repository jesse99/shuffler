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

// Note that these are created within a thread and then handed off to the main thread.
@implementation Files
{
	NSString* _root;
	Database* _database;
	Glob* _glob;
	NSMutableArray* _paths;
	
	NSUInteger _numFiltered;
	NSMutableArray* _filtered[TopRating+1];		// [[path]]
	NSUInteger _numShown[TopRating+1];			// [count]
	NSUInteger _numTotal[TopRating+1];			// [count]
}

- (id)init:(NSString*)dirPath dbPath:(NSString*)dbPath
{
	self = [super init];
	
	if (self)
	{
		_root = [dbPath stringByDeletingLastPathComponent];
		_database = [self _createDatabase:dbPath];

		// See https://developer.apple.com/library/mac/documentation/Cocoa/Reference/ApplicationKit/Classes/nsimagerep_Class/Reference/Reference.html#//apple_ref/occ/clm/NSImageRep/imageRepWithContentsOfFile:
		NSArray* globs = @[@"*.tiff", @"*.gif", @"*.jpg", @"*.jpeg", @"*.pict", @"*.pdf", @"*.eps", @"*.png"];
		_glob = [[Glob alloc] initWithGlobs:globs];
		
		_paths = [self _findPaths:dirPath database:_database];	// TODO: popup a directory picker if nothing was found

		for (NSUInteger i = WorstRating + 1; i <= TopRating; ++i)
		{
			_filtered[i] = [[NSMutableArray alloc] initWithCapacity:1000];
		}
		_filtered[WorstRating] = [_paths mutableCopy];
		_numFiltered = _paths.count;
	}
	
	return self;
}

- (NSString*)root
{
	return _root;
}

// We update the stats used by the Database Info window but we don't
// update _filtered. For example, if the user changes the tag to
// Puppies or changes the rating from Great to Normal we'll leave
// it in _filtered and may wind up showing it when we shouldn't.
//
// We could update _filtered. For example we could re-run the
// query with the addition of ImagePaths.hash == image's hash.
// This would tell us if the image still belongs in _filtered
// and where it belongs. But then we'd have to remove the old
// entry which kind of sucks for poeple with lots of images
// because it's O(N).
- (void)trashedFile:(NSString*)path withRating:(NSString*)rating
{
	NSArray* filtered;
	
	NSUInteger index = nameToRating(rating);
	if (index == NormalRating)
	{
		filtered = _filtered[NormalRating];
		if (![filtered containsObject:path])
		{
			index = UncategorizedRating;
		}
	}
	
	filtered = _filtered[index];
	if (filtered.count > 0)			// only adjust the counts if we're using them
	{
		_numShown[index] -= 1;
		_numTotal[index] -= 1;
	}
		
	[[NSNotificationCenter defaultCenter] postNotificationName:@"Stats Changed" object:self];
}

- (void)changedRatingFrom:(NSString*)oldRating to:(NSString*)newRating for:(NSString*)path
{
	NSArray* filtered;
	
	NSUInteger index = nameToRating(oldRating);
	if (index == NormalRating)
	{
		filtered = _filtered[NormalRating];
		if (![filtered containsObject:path])
		{
			index = UncategorizedRating;
		}
	}

	filtered = _filtered[index];
	if (filtered.count > 0)			// only adjust the counts if we're using them
	{
		_numShown[index] -= 1;
		_numTotal[index] -= 1;
	}
	
	index = nameToRating(newRating);
	filtered = _filtered[index];
	if (filtered.count > 0)
	{
		_numShown[index] += 1;
		_numTotal[index] += 1;
	}

	[[NSNotificationCenter defaultCenter] postNotificationName:@"Stats Changed" object:self];
}

- (NSUInteger)numShownForRating:(NSUInteger)rating
{
	ASSERT(rating <= TopRating);
	return _numShown[rating];
}

- (NSUInteger)totalForRating:(NSUInteger)rating
{
	ASSERT(rating <= TopRating);
	return _numTotal[rating];
}

- (NSUInteger)numUnfiltered
{
	return _paths.count;
}

- (NSUInteger)numFiltered
{
	return _numFiltered;
}

- (NSString*)randomPath:(NSArray*)shown
{
	NSString* path = nil;
	
	if (_numFiltered > 0)
	{
		NSFileManager* fm = [NSFileManager defaultManager];
		
		NSUInteger rating = [self _findRandomRating];
		NSUInteger numRatings = TopRating - WorstRating + 1;
		for (NSUInteger i = 0; i < numRatings && path == nil; ++i)
		{
			NSArray* filtered = _filtered[rating];
			if (filtered.count > 0)
			{
				LOG_VERBOSE("   trying %s images", STR(ratingToName(rating)));
				
				NSUInteger offset = random() % filtered.count;
				for (NSUInteger j = 0; j < filtered.count && path == nil; ++j)
				{
					NSUInteger index = (offset + j) % filtered.count;
					NSString* candidate = filtered[index];
					
					// We'll get notified and rebuild our lists as files get deleted,
					// but not immediately...
					if (![shown containsObject:candidate])
					{
						if ([fm fileExistsAtPath:candidate])
						{
							path = candidate;
							_numShown[rating] += 1;
							
							[[NSNotificationCenter defaultCenter] postNotificationName:@"Stats Changed" object:self];
						}
					}
				}
			}
			
			if (--rating > TopRating)
				rating = TopRating;
		}
	}

	return path;
}

- (NSUInteger)_findRandomRating
{
	ASSERT(TopRating - WorstRating + 1 == 5);	// or maxWeight is busted
	
	long scaling = 5;			// fantastic images are 625x more likely to appear than normal images
	long maxWeight = scaling*scaling*scaling*scaling*scaling;
	long weight = random() % maxWeight;
	
	for (NSUInteger i = WorstRating; i <= TopRating; ++i)
	{
		if (weight <= scaling)
			return i;
		else
			weight /= scaling;
	}
	
	return TopRating;
}

// Note that this is main thread code.
- (bool)filterBy:(NSString*)rating andTags:(NSArray*)tags includeUncategorized:(bool)includeUncategorized
{
	double startTime = getTime();
	
	_numFiltered = 0;
	for (NSUInteger i = WorstRating; i <= TopRating; ++i)
	{
		NSMutableArray* filtered = _filtered[i];
		[filtered removeAllObjects];
		_numShown[i] = 0;
		_numTotal[i] = 0;
	}
	
	[self _addCategorized:rating andTags:tags];
	if (includeUncategorized)
		[self _addUnCategorized];
	
	double elapsed = getTime() - startTime;
	if (_numFiltered > 0)
		LOG_NORMAL("filtered %lu images to %lu images in %.1fs", _paths.count, _numFiltered, elapsed);
	
	[[NSNotificationCenter defaultCenter] postNotificationName:@"Stats Changed" object:self];

	return _numFiltered > 0;
}

- (void)_addCategorized:(NSString*)rating andTags:(NSArray*)tags
{
	NSError* error = nil;
	NSString* sql = [self _getQuery:rating andTags:tags];
	NSMutableArray* rows = [_database queryRows:sql error:&error];
	for (NSUInteger i = 0; rows && i < rows.count; ++i)
	{
		NSArray* row = rows[i];
		NSString* path = row[0];
		NSString* ii   = row[1];
		
		NSUInteger index = (NSUInteger) [ii integerValue];
		if (index <= TopRating)		// should always be true...
		{
			NSMutableArray* filtered = _filtered[index];
			[filtered addObject:path];
			_numFiltered += 1;
			_numTotal[index] += 1;
		}
	}

	if (!rows)
		LOG_ERROR("Categorized query failed: %s", STR(error.localizedFailureReason));
}

// Much faster to use separate queries for categorized and uncategorized.
- (void)_addUnCategorized
{
	NSMutableArray* filtered = _filtered[TopRating];

	NSError* error = nil;
	NSString* sql = @"SELECT path FROM ImagePaths WHERE length(hash) == 0";
	NSMutableArray* rows = [_database queryRows1:sql error:&error];
	for (NSUInteger i = 0; rows && i < rows.count; ++i)
	{
		NSString* path = rows[i];
		
		[filtered addObject:path];
		_numFiltered += 1;
		_numTotal[TopRating] += 1;
	}
	
	if (!rows)
		LOG_ERROR("Uncategorized query failed: %s", STR(error.localizedFailureReason));
}

// This is where we get categorized paths, i.e. those with a rating and tags.
- (NSString*)_getQuery:(NSString*)rating andTags:(NSArray*)tags
{
	NSMutableArray* predicates = [NSMutableArray new];

	int level = (int) nameToRating(rating);
	if (level > NormalRating)
		[predicates addObject:[NSString stringWithFormat:@"rating >= %d", level]];
	
	NSArray* clauses = [self _getTagsClauses:tags];
	if (clauses.count == 1)
	{
		[predicates addObject:clauses[0]];
	}
	else if (clauses.count > 1)
	{
		NSString* clause = [clauses componentsJoinedByString:@" OR "];
		[predicates addObject:[NSString stringWithFormat:@"(%@)", clause]];
	}
	
	[predicates addObject:@"Indexing.hash == ImagePaths.hash"];

	NSString* sql = [NSString stringWithFormat:@"SELECT path, rating FROM Indexing, ImagePaths WHERE %@",
		[predicates componentsJoinedByString:@" AND "]];
	LOG_VERBOSE("%s", STR(sql));
	
	return sql;
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

- (NSMutableArray*)_findPaths:(NSString*)root database:(Database*)database;
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
		if (!database)
			LOG_ERROR("Couldn't create the database at '%s': %s", STR(dbPath), STR(error.localizedFailureReason));
	}
		
	return database;
}

@end
