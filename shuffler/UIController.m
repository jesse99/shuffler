#import "UIController.h"

@implementation UIController

- (id)init
{
	self = [super initWithWindowNibName:@"UIWindow"];

    if (self)
	{
        [self.window makeKeyAndOrderFront:self];	// note that we need to call the window method to load the controls
		[_tagsPopup selectItem:nil];
		[_tagsLabel setStringValue:@""];
		
		NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
		NSArray* tags = [defaults objectForKey:@"tags"];
		for (NSUInteger i = tags.count - 1; i < tags.count; --i)
		{
			[_tagsMenu insertItemWithTitle:tags[i] action:@selector(selectTag:) keyEquivalent:@"" atIndex:2];
		}
    }
    
	return self;
}

- (void)windowDidLoad
{
    [super windowDidLoad];
}

- (void)setPath:(NSString*)path
{
	[self.window setTitle:path.lastPathComponent];
}

- (IBAction)selectRating:(id)sender
{
	NSString* rating = _ratingPopup.titleOfSelectedItem;
	LOG_INFO("rating = %s", STR(rating));
}

- (IBAction)selectScaling:(id)sender
{
	NSString* title = _scalingPopup.titleOfSelectedItem;
	if ([title characterAtIndex:title.length-1] == '%')
	{
		double scaling = title.doubleValue/100.0;
		LOG_INFO("scaling = %.2f", scaling);
	}
	else
	{
		LOG_INFO("scaling = %s", STR(title));	// May be "None" or "Max"
	}
}

- (void)selectTag:(NSMenuItem*)sender
{
	NSString* name = [sender title];
	NSString* tags = [self _toggleTag:name];
	[_tagsLabel setStringValue:tags];
}

- (IBAction)selectNoneTag:(NSMenuItem*)sender
{
	[_tagsLabel setStringValue:@""];
}

- (IBAction)selectNewTag:(NSMenuItem*)sender
{
	// TODO: implement this
}

- (BOOL)validateMenuItem:(NSMenuItem*)item
{
	BOOL enabled = true;
	
	if (item.action == @selector(selectNoneTag:))
	{
		[item setState:_tagsLabel.stringValue.length == 0];
	}
	else if (item.action == @selector(selectTag:))
	{
		NSArray* tags = [_tagsLabel.stringValue componentsSeparatedByString:@" • "];
		[item setState:[tags containsObject:item.title]];
	}
	
	return enabled;
}

- (NSString*)_toggleTag:(NSString*)tag
{
	NSMutableArray* tags;
	if (_tagsLabel.stringValue.length > 0)
		tags = [[_tagsLabel.stringValue componentsSeparatedByString:@" • "] mutableCopy];
	else
		tags = [NSMutableArray new];
	
	if ([tags containsObject:tag])
	{
		[tags removeObject:tag];
	}
	else
	{
		[tags addObject:tag];
		[tags sortUsingSelector:@selector(caseInsensitiveCompare:)];
	}
	
	return [tags componentsJoinedByString:@" • "];
}

@end
