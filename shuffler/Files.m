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
	
	NSUInteger _currentRating;
	NSArray* _currentTags;
	bool _includeUncategorized;
	NSUInteger _numShown[TopRating+1];	// [count]
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
		
		_currentTags = @[];
		_includeUncategorized = true;
		
		[self _addUncategorized:dirPath database:_database];	// TODO: popup a directory picker if nothing was found
	}
	
	return self;
}

- (NSString*)root
{
	return _root;
}

- (void)trashedCategorizedFile:(NSString*)path withRating:(NSString*)rating
{
	NSUInteger index = nameToRating(rating);
	if (index >= _currentRating)
	{
		_numShown[index] -= 1;
		
		[[NSNotificationCenter defaultCenter] postNotificationName:@"Stats Changed" object:self];
	}
}

- (void)trashedUncategorizedFile:(NSString*)path
{
	if (_includeUncategorized)
	{
		_numShown[UncategorizedRating] -= 1;

		[[NSNotificationCenter defaultCenter] postNotificationName:@"Stats Changed" object:self];
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

- (void)changedUncategorizedToRating:(NSString*)rating
{
	bool changed = false;

	if (_includeUncategorized)
	{
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
		_currentTags = tags;
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
	
	NSString* name = ratingToName(rating);
	NSString* sql = [self _getCountQueryForRating:name];
	NSUInteger count = [self _runCountQuery:sql];
	
	return count;
}

- (NSUInteger)numFiltered
{
	NSString* sql = [self _getCountQuery];
	NSUInteger count = [self _runCountQuery:sql];
	
	if (_includeUncategorized)
	{
		sql = [NSString stringWithFormat:@"%@ LIMIT 1", [self _getCountUncategorizedQuery]];
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
	for (NSUInteger i = 0; i <= TopRating; ++i)
	{
		weight *= scaling;
	}
	
	return weight;
}

- (NSString*)randomPath:(NSArray*)shown
{
	NSString* path = nil;
	
	double startTime = getTime();
	NSString* sql = nil;
	if (_includeUncategorized && random() % 2 == 0)	// if we have uncategorized images we want to show them often
	{
		sql = [NSString stringWithFormat:@"%@ LIMIT 1", [self _getCountUncategorizedQuery]];
		NSUInteger count = [self _runCountQuery:sql];
		if (count > 0)
			sql = [NSString stringWithFormat:@"%@ ORDER BY RANDOM() LIMIT 100", [self _getUncategorizedQuery]];
	}
	if (!sql)
		sql = [NSString stringWithFormat:@"%@ ORDER BY RANDOM() LIMIT 100", [self _getQuery]];

	NSError* error = nil;
	NSMutableArray* rows = [_database queryRows:sql error:&error];
	if (rows)
	{
		long weight = ratingToWeight(TopRating);

		NSFileManager* fm = [NSFileManager defaultManager];
		NSString* fallback = nil;
		NSUInteger fallbackRating = 0;
		for (NSUInteger i = 0; i < rows.count && path == nil; ++i)
		{
			NSArray* row = rows[i];
			NSString* candidate = row[0];
			if (![shown containsObject:candidate])
			{
				if ([fm fileExistsAtPath:candidate])
				{
					NSString* tmp = row[1];
					NSUInteger rating = (NSUInteger) [tmp integerValue];
					fallback = candidate;
					fallbackRating = rating;
					
					weight -= ratingToWeight(rating);
					if (weight <= 0)
					{
						path = candidate;
						_numShown[rating] += 1;
						
						[[NSNotificationCenter defaultCenter] postNotificationName:@"Stats Changed" object:self];
					}
				}
			}
		}
		
		if (!path && fallback)
		{
			LOG_NORMAL("Showing a path that has already been shown");
			path = fallback;
			_numShown[fallbackRating] += 1;
			
			[[NSNotificationCenter defaultCenter] postNotificationName:@"Stats Changed" object:self];
		}
				
		double elapsed = getTime() - startTime;
		LOG_VERBOSE("ran '%s' in %.1fs", STR(sql), elapsed);
	}
	else
	{
		LOG_ERROR("'%s' query failed: %s", STR(sql), STR(error.localizedFailureReason));
	}
	
	return path;
}

- (NSUInteger)_runCountQuery:(NSString*)sql
{
	double startTime = getTime();

	NSError* error = nil;
	NSUInteger count = 0;
	NSMutableArray* rows = [_database queryRows1:sql error:&error];
	if (rows && rows.count == 1)
	{
		NSString* text = rows[0];
		count = (NSUInteger) [text integerValue];
		
		double elapsed = getTime() - startTime;
		LOG_VERBOSE("ran '%s' in %.1fs", STR(sql), elapsed);
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
	LOG_VERBOSE("%s", STR(sql));
	
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
	LOG_VERBOSE("%s", STR(sql));
	
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
	LOG_VERBOSE("%s", STR(sql));
	
	return sql;
}

// Much faster to do these via separate qeurries.
- (NSString*)_getCountUncategorizedQuery
{
	NSString* sql = @"SELECT COUNT(path) FROM ImagePaths WHERE length(hash) == 0";
	LOG_VERBOSE("%s", STR(sql));
	
	return sql;
}

- (NSString*)_getUncategorizedQuery
{
	NSString* sql = @"SELECT path, 0 FROM ImagePaths WHERE length(hash) == 0";
	LOG_VERBOSE("%s", STR(sql));
	
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
