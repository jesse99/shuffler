extern const NSUInteger NormalRating;
extern const NSUInteger GoodRating;
extern const NSUInteger GreatRating;
extern const NSUInteger FantasticRating;
extern const NSUInteger UncategorizedRating;

NSString* ratingToName(NSUInteger rating);

// Used to select a file to display.
@interface Files : NSObject

- (id)init:(NSString*)dirPath dbPath:(NSString*)dbPath;

- (bool)filterBy:(NSString*)rating andTags:(NSArray*)tag includeUncategorized:(bool)withUncategorized;

- (NSString*)root;
- (NSString*)randomPath:(NSArray*)shown;

- (NSUInteger)numUnfiltered;
- (NSUInteger)numFiltered;

- (NSUInteger)numShownForRating:(NSUInteger)rating;
- (NSUInteger)totalForRating:(NSUInteger)rating;

@end
