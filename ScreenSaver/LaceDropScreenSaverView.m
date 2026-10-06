#import <ScreenSaver/ScreenSaver.h>
#import "LaceView.h"

@interface LaceDropScreenSaverView : ScreenSaverView
@property (nonatomic, strong) LaceView *laceView;
@end

@implementation LaceDropScreenSaverView

- (instancetype)initWithFrame:(NSRect)frame isPreview:(BOOL)isPreview {
    self = [super initWithFrame:frame isPreview:isPreview];
    if (self) {
        self.animationTimeInterval = 1.0 / 60.0;
        self.wantsLayer = YES;
        self.layer.backgroundColor = NSColor.blackColor.CGColor;

        self.laceView = [[LaceView alloc] initWithFrame:self.bounds startAnimation:YES];
        self.laceView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [self.laceView setLaceOpen:YES animated:NO];
        [self addSubview:self.laceView];
    }
    return self;
}

- (BOOL)isOpaque {
    return YES;
}

- (void)drawRect:(NSRect)rect {
    NSGradient *background = [[NSGradient alloc]
        initWithStartingColor:[NSColor colorWithRed:0.025 green:0.045 blue:0.095 alpha:1.0]
                  endingColor:[NSColor colorWithRed:0.08 green:0.17 blue:0.38 alpha:1.0]];
    [background drawInRect:self.bounds angle:-34.0];
}

- (void)animateOneFrame {
    [self setNeedsDisplay:YES];
}

- (BOOL)hasConfigureSheet {
    return NO;
}

@end
