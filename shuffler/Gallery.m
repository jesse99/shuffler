#import "Gallery.h"

#import "AppDelegate.h"
#import "Database.h"

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
@implementation Gallery
{
	Database* _database;
	
	NSUInteger _currentRating;
	NSArray* _currentTags;
	bool _includeUncategorized;
	NSUInteger _numShown[TopRating+1];	// [count]
}

- (id)init:(NSString*)dbPath
{
	self = [super init];
	
	if (self)
	{
		[self _createDatabase:dbPath];

		_currentTags = @[];
		_includeUncategorized = true;
	}
	
	return self;
}

- (void)spinup:(void (^)())finished
{
	[self _addUncategorized:_database finished:finished];	// TODO: popup a directory picker if nothing was found	
}

- (void)storeChanged
{
	[self _addUncategorized:_database finished:
		^{
			[[NSNotificationCenter defaultCenter] postNotificationName:@"Stats Changed" object:nil];
		}];
}

- (void)trashedCategorizedFile:(id<ImageProtocol>)image withRating:(NSString*)rating
{
	NSUInteger index = nameToRating(rating);
	if (index >= _currentRating)
	{
		_numShown[index] -= 1;
		
		[self _removePathFromDatabase:image.path];
		[[NSNotificationCenter defaultCenter] postNotificationName:@"Stats Changed" object:self];
	}
}

- (void)trashedUncategorizedFile:(id<ImageProtocol>)image
{
	if (_includeUncategorized)
	{
		if (_numShown[UncategorizedRating] > 0)		// this can be zero if we've just changed how we are filtering
			_numShown[UncategorizedRating] -= 1;

		[self _removePathFromDatabase:image.path];
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

- (id<ImageProtocol>)randomImage:(NSArray*)shown
{
	NSString* path = nil;
	
//	double startTime = getTime();
	NSError* error = nil;
	NSString* sql = [NSString stringWithFormat:@"%@ ORDER BY RANDOM() LIMIT 300", [self _getQuery]];
	NSArray* categorized = [_database queryRows:sql error:&error];

	NSMutableArray* rows = [NSMutableArray new];
	NSRange uncategorizedRange = NSMakeRange(0, 0);
	if (_includeUncategorized)
	{
		sql = [NSString stringWithFormat:@"%@ ORDER BY RANDOM() LIMIT 50", [self _getUncategorizedQuery]];
		NSArray* uncategorized = [_database queryRows:sql error:&error];
		
		if (random() % 2 == 1)
		{
			// Half the time we'll show an uncategorized file (if any exist we'll pick them
			// because they have max weight).
			[rows addObjectsFromArray:uncategorized];
			[rows addObjectsFromArray:categorized];
			uncategorizedRange = NSMakeRange(0, uncategorized.count);
		}
		else
		{
			// The other half of the time we'll try and show a categorized file (this may
			// fail if there aren't very many and they've all been shown).
			[rows addObjectsFromArray:categorized];
			[rows addObjectsFromArray:uncategorized];
			uncategorizedRange = NSMakeRange(categorized.count, uncategorized.count);
		}
	}
	else
	{
		[rows addObjectsFromArray:categorized];
	}
	
	AppDelegate* app = [NSApp delegate];
	if (rows && rows.count > 0)
	{
		long weight = ratingToWeight(TopRating);

		NSString* fallback = nil;
		NSUInteger fallbackRating = 0;
		for (NSUInteger i = 0; i < rows.count && path == nil; ++i)
		{
			NSArray* row = rows[i];
			NSString* candidate = row[0];
			if ([app.store exists:candidate])
			{
				NSString* tmp = row[1];
				NSUInteger rating = (NSUInteger) [tmp integerValue];
				fallback = candidate;
				fallbackRating = rating;
				
				if ((i >= uncategorizedRange.location && i < uncategorizedRange.location + uncategorizedRange.length) || ![shown containsObject:candidate])
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
	
	return path != nil ? [app.store create:path] : nil;
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

- (void)_addUncategorized:(Database*)database finished:(void (^)())finished;
{
	AppDelegate* app = [NSApp delegate];
	(void) [app.store enumerate:
		^(NSString* path) {
			[database insertOrIgnore:@"ImagePaths" values:@[path, @""]];
		} finished:finished];
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
