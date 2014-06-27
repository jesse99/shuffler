// Used to select a file to display.
@interface Files : NSObject

- (id)init:(NSString*)dirPath dbPath:(NSString*)dbPath;

- (NSString*)randomImagePath;

@end
