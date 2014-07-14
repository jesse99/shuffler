#import "StringCategory.h"

@implementation NSString (StringCategory)

+(NSString*)formatWithThousandSeparator:(NSNumber*)number
{
	NSNumberFormatter* formatter = [NSNumberFormatter new];

	[formatter setFormatterBehavior: NSNumberFormatterBehavior10_4];
	[formatter setNumberStyle: NSNumberFormatterDecimalStyle];

	return [formatter stringFromNumber:number];
}

@end
