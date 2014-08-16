#import "InfoController.h"

#import "AppDelegate.h"
#import "Gallery.h"
#import "StringCategory.h"

static InfoController* _controller;

@implementation InfoController
{
	NSDictionary* _labelAttrs;
	NSDictionary* _textAttrs;
}

- (id)init
{
	self = [super initWithWindowNibName:@"DatabaseInfo"];

	if (self)
	{
		self->_labelAttrs = @{NSFontAttributeName: [NSFont fontWithName:@"Times-Bold" size:17]};	// TODO: use a pref for these?
		self->_textAttrs = @{NSFontAttributeName: [NSFont fontWithName:@"Times" size:17]};
		
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_reload:) name:@"Stats Changed" object:nil];
	}

	return self;
}

+ (void)show
{
	if (!_controller)
		_controller = [[InfoController alloc] init];
	
	if (_controller)
	{
		NSWindow* window = _controller.window;	// forces controls to load
		[_controller _reload:nil];
		
		[_controller showWindow:_controller];
		[window makeKeyAndOrderFront:NSApp];
	}
}

- (void)close:(id)sender
{
	[self.window orderOut:sender];
}

- (void)_reload:(NSNotification*)notification
{
	AppDelegate* delegate = [NSApp delegate];
	Gallery* files = delegate.files;
	
	NSString* dir = [files.root lastPathComponent];
	[self.window setTitle:dir];
    
	NSTextStorage* storage = _textView.textStorage;
	[storage beginEditing];
	[storage deleteCharactersInRange:NSMakeRange(0, storage.length)];
	
	NSUInteger shown = 0;
	NSUInteger total = 0;
	[self _addStats:files forRating:FantasticRating shown:&shown total:&total];
	[self _addStats:files forRating:GreatRating shown:&shown total:&total];
	[self _addStats:files forRating:GoodRating shown:&shown total:&total];
	[self _addStats:files forRating:NormalRating shown:&shown total:&total];
	[self _addStats:files forRating:UncategorizedRating shown:&shown total:&total];

	NSString* shownStr = [NSString formatWithThousandSeparator:[NSNumber numberWithUnsignedInteger:shown]];
	NSString* totalStr = [NSString formatWithThousandSeparator:[NSNumber numberWithUnsignedInteger:total]];
	[self _addLabel:@"Total" withText:[NSString stringWithFormat:@"%@ shown out of %@", shownStr, totalStr]];
		
	[storage endEditing];
}

- (void)_addStats:(Gallery*)files forRating:(NSUInteger)rating shown:(NSUInteger*)shown total:(NSUInteger*)total
{
	NSUInteger totalNum = [files totalForRating:rating];
	if (totalNum > 0)
	{
		NSUInteger numShown = [files numShownForRating:rating];
		NSString* shownStr = [NSString formatWithThousandSeparator:[NSNumber numberWithUnsignedInteger:numShown]];
		NSString* totalStr = [NSString formatWithThousandSeparator:[NSNumber numberWithUnsignedInteger:totalNum]];
		
		[self _addLabel:ratingToName(rating) withText:[NSString stringWithFormat:@"%@ shown out of %@", shownStr, totalStr]];
		
		*shown += numShown;
		*total += totalNum;
	}
}

- (void)_addLabel:(NSString*)label withText:(NSString*)text
{
	NSAttributedString* str = [[NSAttributedString alloc] initWithString:label attributes:_labelAttrs];
	[_textView.textStorage appendAttributedString:str];

	text = [NSString stringWithFormat:@": %@\n", text];
	str = [[NSAttributedString alloc] initWithString:text attributes:_textAttrs];
	[_textView.textStorage appendAttributedString:str];
}

@end
