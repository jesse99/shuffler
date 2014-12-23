#import "MainWindow.h"


@implementation MainWindow
{
	NSScreen* _screen;
	NSImageView* _images[2];
	NSUInteger _index;
	double _maxScaling;
	int _leftBorder;
}

// We can't make a borderless window in IB so we need to use a subclass
// so that we can still use IB to set our window up.
- (id)initWithContentRect:(NSRect)contentRect styleMask:(NSUInteger)style backing:(NSBackingStoreType)buffering defer:(BOOL)flag
{
	// This is awfully goofy: we create a brand new window to replace the one that we
	// were told to create. We do this because the init method that takes a screen is
	// not the designated initializor and there doesn't seem to be a good way to put
	// it on the right screen.
	if (style != NSBorderlessWindowMask)
	{
		NSScreen* screen = [self _getScreen];
		contentRect = screen.visibleFrame;
		contentRect.origin.x = 0.0;
		contentRect.origin.y = 0.0;
		self = [[MainWindow alloc] initWithContentRect:contentRect styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:false screen:screen];
		
		_screen = screen;
		_leftBorder = 430;	// TODO: make this a pref

		[self setBackgroundColor:[NSColor clearColor]];
		[self setExcludedFromWindowsMenu:true];
		[self setIgnoresMouseEvents:true];
		[self setLevel:CGWindowLevelForKey(kCGDesktopIconWindowLevelKey)];
		[self setOpaque:false];
	}
	else
	{
		self = [super initWithContentRect:contentRect styleMask:style backing:buffering defer:flag];
	}
	
	_maxScaling = 1.0;
	
	return self;
}

- (void)useScreen:(NSScreen*)screen
{
	_screen = screen;
	if (screen.frame.origin.x == 0)
		_leftBorder = 430;
	else
		_leftBorder = 0;
	[self setFrame:_screen.visibleFrame display:NO];
}

- (void)update:(id<ImageProtocol>)image imageData:(NSData*)data scaling:(double)scaling
{
	if (!_images[0])
		[self _postInit];
	
	NSImageRep* rep = [[NSBitmapImageRep alloc] initWithData:data];
	if (rep)
	{
		NSSize size = NSMakeSize(rep.pixelsWide, rep.pixelsHigh);
		NSSize windSize = self.frame.size;
		_maxScaling = MIN(windSize.width/size.width, windSize.height/size.height);
		
		if (scaling == INFINITY)
		{
			if (_maxScaling > 1.0)
			{
				size.width  *= _maxScaling;
				size.height *= _maxScaling;
				[rep setSize:size];
			}
		}
		else if (scaling != 1.0)
		{
			size.width  *= scaling;
			size.height *= scaling;
			[rep setSize:size];
		}
		
		// Load the image (we need to use a two step process here because just
		// creating an NSImage won't always give us a valid size).
		NSImage* bitmap = [[NSImage alloc] initWithSize:size];
		[bitmap addRepresentation:rep];

		// Fade the old view out and the new view in.
		NSAnimationContext* context = [NSAnimationContext currentContext];
		[context setDuration:1.0];
		
		[_images[_index].animator setAlphaValue:0.0];
		_index = (_index + 1) % 2;
		[_images[_index].animator setAlphaValue:1.0];

		// Set the frame and image for the new view. Note that we get nicer
		// results if we do this after the fades.
        [_images[_index] setImage:bitmap];
        [_images[_index] setFrame:[self _doGetViewRect:size]];
		_image = image;
		LOG_VERBOSE("selected '%s'", STR(image));
	}
	else
	{
		LOG_ERROR("failed to load '%s'", STR(image));
	}
}

- (void)_postInit
{
	[_image1 setImageScaling:NSScaleProportionally];
	[_image1 setImageFrameStyle:NSImageFrameNone];
	_images[0] = _image1;
	
	[_image2 setImageScaling:NSScaleProportionally];
	[_image2 setImageFrameStyle:NSImageFrameNone];
	_images[1] = _image2;
	
    [_image1.superview setWantsLayer:true];
	[self orderFront:self];
}

// This is the view rect for the view within the window (the window is transparent and
// fills the screen).
- (NSRect)_doGetViewRect:(NSSize)imageSize
{
	NSRect result;
	
	// For the vertical component we can use the full window. If the image
	// is too tall it will be scaled. If the image is shorter than the window
	// it will be centered.
	NSSize windSize = self.frame.size;
	result.origin.y = 0.0f;
	result.size.height = windSize.height;
	
	// For the horizontal component we want to center the image, but if it
	// intersects the left border we need to push it to the right.
	result.origin.x = MAX(windSize.width/2 - imageSize.width/2, _leftBorder);
	result.size.width = MIN(imageSize.width, windSize.width - result.origin.x);
	
	return result;
}

- (NSScreen*)_getScreen
{
	NSArray* screens = [NSScreen screens];	// 0 is the primary screen
	NSScreen* screen = screens.count > 1 ? screens[0] : screens[0];	// TODO: use a pref

	return screen;
}

@end
