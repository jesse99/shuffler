#import <Cocoa/Cocoa.h>
#import "Shuffler.h"

int main(int argc, const char * argv[])
{
	// We hard-code the log file path to ensure that we can always log.
	NSString* path = [@"~/Library/Logs/shuffler.log" stringByExpandingTildeInPath];
	setupLogging(path.UTF8String);
	setLevel("VERBOSE");				// TODO: probably should get this from a pref
	
	double msecs = 1000*[NSDate timeIntervalSinceReferenceDate];
	srandom((uint) msecs);

	return NSApplicationMain(argc, argv);
}
