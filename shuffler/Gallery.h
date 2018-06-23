#import "ImageProtocol.h"

extern const NSUInteger NormalRating;
extern const NSUInteger GoodRating;
extern const NSUInteger GreatRating;
extern const NSUInteger FantasticRating;
extern const NSUInteger UncategorizedRating;

NSString* ratingToName(NSUInteger rating);

// Uses a store object to interact with the images the user has selected to show.
@interface Gallery : NSObject

- (id)init:(NSString*)dbPath;
- (void)spinup:(void (^)(void))finished;

- (void)trashedCategorizedFile:(id<ImageProtocol>)image withRating:(NSString*)rating;
- (void)trashedUncategorizedFile:(id<ImageProtocol>)image;
- (void)storeChanged;

- (void)changedRatingFrom:(NSString*)oldRating to:(NSString*)newRating;
- (void)changedUncategorizedToCategorized:(NSString*)rating;

- (bool)filterBy:(NSString*)rating andTags:(NSArray*)tag includeUncategorized:(bool)withUncategorized;

- (id<ImageProtocol>)randomImage:(NSArray*)shown;

- (NSUInteger)numWithNoFilter;
- (NSUInteger)numFiltered;

- (NSUInteger)numShownForRating:(NSUInteger)rating;
- (NSUInteger)totalForRating:(NSUInteger)rating;

@end
