// Used to select a file to display.
@interface Files : NSObject

- (id)init:(NSString*)dirPath dbPath:(NSString*)dbPath;

- (void)filterBy:(NSString*)rating;

- (NSString*)nextPath;
- (NSString*)prevPath;

- (NSUInteger)numUnfiltered;
- (NSUInteger)numFiltered;

@end
