// Used to select a file to display.
@interface Files : NSObject

- (id)init:(NSString*)dirPath dbPath:(NSString*)dbPath;

- (bool)filterBy:(NSString*)rating andTags:(NSArray*)tags withNone:(bool)withNone withUncategorized:(bool)withUncategorized;

- (NSString*)nextPath;
- (NSString*)prevPath;

- (NSUInteger)numUnfiltered;
- (NSUInteger)numFiltered;

@end
