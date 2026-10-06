#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const LaceMotifFlower;
FOUNDATION_EXPORT NSString * const LaceMotifTulip;
FOUNDATION_EXPORT NSString * const LaceMotifVine;
FOUNDATION_EXPORT NSString * const LaceMotifGeometric;

@interface LaceView : NSView

@property (nonatomic, copy, nullable) void (^openStateDidChange)(BOOL isOpen);
@property (nonatomic, copy, nullable) void (^openProgressDidChange)(CGFloat progress);
@property (nonatomic, readonly, getter=isOpen) BOOL open;
@property (nonatomic, readonly, getter=isDragging) BOOL dragging;
@property (nonatomic, copy, readonly) NSString *motifName;

- (instancetype)initWithFrame:(NSRect)frameRect startAnimation:(BOOL)startAnimation;
- (void)toggleLace;
- (void)setLaceOpen:(BOOL)open animated:(BOOL)animated;
- (BOOL)setMotifNamed:(NSString *)motifName;
- (NSRect)interactionRectInWindow;
- (BOOL)shouldCaptureMouseAtWindowPoint:(NSPoint)windowPoint;
- (void)setBarHoveredFromPolling:(BOOL)hovered;
- (BOOL)writePreviewToPath:(NSString *)path error:(NSError **)error;
- (BOOL)writeScenePreviewToPath:(NSString *)path error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
