#import "LaceView.h"
#import "LaceMetalView.h"
#import <QuartzCore/QuartzCore.h>

NSString * const LaceMotifFlower = @"flower";
NSString * const LaceMotifTulip = @"tulip";
NSString * const LaceMotifVine = @"vine";
NSString * const LaceMotifGeometric = @"geometric";

static NSString *LaceResourceNameForMotif(NSString *motifName) {
    if ([motifName isEqualToString:LaceMotifFlower]) return @"LaceTexture-Flower";
    if ([motifName isEqualToString:LaceMotifTulip]) return @"LaceTexture-Tulip";
    if ([motifName isEqualToString:LaceMotifVine]) return @"LaceTexture-Vine";
    if ([motifName isEqualToString:LaceMotifGeometric]) return @"LaceTexture-Geometric";
    return nil;
}

typedef struct {
    CGPoint position;
    CGPoint previous;
    CGPoint rest;
    NSInteger column;
    NSInteger row;
    BOOL topAnchor;
} LaceParticle;

typedef NS_ENUM(uint8_t, LaceConstraintKind) {
    LaceConstraintStructural,
    LaceConstraintShear,
    LaceConstraintBend,
};

typedef struct {
    NSInteger a;
    NSInteger b;
    CGFloat restLength;
    LaceConstraintKind kind;
} LaceConstraint;

typedef struct {
    float u;
    float v;
} LaceTextureCoordinate;

@interface LaceBarOverlayView : NSView
@property (nonatomic) BOOL hovered;
@property (nonatomic) BOOL laceOpen;
@end

@implementation LaceBarOverlayView

- (BOOL)isFlipped { return YES; }
- (BOOL)isOpaque { return NO; }
- (nullable NSView *)hitTest:(NSPoint)point { (void)point; return nil; }

- (void)setHovered:(BOOL)hovered {
    if (_hovered == hovered) return;
    _hovered = hovered;
    [self setNeedsDisplay:YES];
}

- (void)setLaceOpen:(BOOL)laceOpen {
    if (_laceOpen == laceOpen) return;
    _laceOpen = laceOpen;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    CGContextRef context = NSGraphicsContext.currentContext.CGContext;
    if (!context) return;
    CGFloat width = self.hovered ? 190.0 : 176.0;
    NSRect bar = NSMakeRect((NSWidth(self.bounds) - width) * 0.5, 0.0, width, 26.0);
    CGPathRef path = CGPathCreateWithRoundedRect(bar, 11.0, 11.0, NULL);
    CGContextSaveGState(context);
    CGContextSetShadowWithColor(context, CGSizeMake(0.0, 3.0), 8.0,
                                [NSColor colorWithWhite:0.0 alpha:0.42].CGColor);
    CGContextAddPath(context, path);
    CGContextSetFillColorWithColor(context, [NSColor colorWithWhite:0.025 alpha:0.985].CGColor);
    CGContextFillPath(context);
    CGContextSetShadowWithColor(context, CGSizeZero, 0.0, NULL);

    CGFloat indicatorAlpha = self.hovered ? 0.95 : 0.58;
    CGFloat chevronY = NSMidY(bar) + (self.laceOpen ? 1.5 : -1.0);
    CGContextBeginPath(context);
    if (self.laceOpen) {
        CGContextMoveToPoint(context, NSMidX(bar) - 5.0, chevronY + 2.0);
        CGContextAddLineToPoint(context, NSMidX(bar), chevronY - 2.0);
        CGContextAddLineToPoint(context, NSMidX(bar) + 5.0, chevronY + 2.0);
    } else {
        CGContextMoveToPoint(context, NSMidX(bar) - 5.0, chevronY - 2.0);
        CGContextAddLineToPoint(context, NSMidX(bar), chevronY + 2.0);
        CGContextAddLineToPoint(context, NSMidX(bar) + 5.0, chevronY - 2.0);
    }
    CGContextSetStrokeColorWithColor(context,
        [NSColor colorWithRed:0.77 green:0.94 blue:1.0 alpha:indicatorAlpha].CGColor);
    CGContextSetLineWidth(context, 1.45);
    CGContextStrokePath(context);
    CGContextRestoreGState(context);
    CGPathRelease(path);
}

@end

static inline CGPoint LacePointAdd(CGPoint a, CGPoint b) {
    return CGPointMake(a.x + b.x, a.y + b.y);
}

static inline CGPoint LacePointSubtract(CGPoint a, CGPoint b) {
    return CGPointMake(a.x - b.x, a.y - b.y);
}

static inline CGPoint LacePointScale(CGPoint value, CGFloat scale) {
    return CGPointMake(value.x * scale, value.y * scale);
}

static inline CGFloat LacePointLength(CGPoint value) {
    return hypot(value.x, value.y);
}

static inline CGFloat LaceClamp(CGFloat value, CGFloat minimum, CGFloat maximum) {
    return fmax(minimum, fmin(maximum, value));
}

static inline CGFloat LaceSmoothStep(CGFloat value) {
    value = LaceClamp(value, 0.0, 1.0);
    return value * value * (3.0 - 2.0 * value);
}

static CGAffineTransform LaceTriangleTransform(CGPoint source0,
                                               CGPoint source1,
                                               CGPoint source2,
                                               CGPoint destination0,
                                               CGPoint destination1,
                                               CGPoint destination2) {
    CGFloat sx1 = source1.x - source0.x;
    CGFloat sy1 = source1.y - source0.y;
    CGFloat sx2 = source2.x - source0.x;
    CGFloat sy2 = source2.y - source0.y;
    CGFloat determinant = sx1 * sy2 - sx2 * sy1;
    if (fabs(determinant) < 0.00001) return CGAffineTransformIdentity;

    CGFloat dx1 = destination1.x - destination0.x;
    CGFloat dy1 = destination1.y - destination0.y;
    CGFloat dx2 = destination2.x - destination0.x;
    CGFloat dy2 = destination2.y - destination0.y;
    CGFloat a = (dx1 * sy2 - dx2 * sy1) / determinant;
    CGFloat c = (-dx1 * sx2 + dx2 * sx1) / determinant;
    CGFloat b = (dy1 * sy2 - dy2 * sy1) / determinant;
    CGFloat d = (-dy1 * sx2 + dy2 * sx1) / determinant;
    CGFloat tx = destination0.x - a * source0.x - c * source0.y;
    CGFloat ty = destination0.y - b * source0.x - d * source0.y;
    return CGAffineTransformMake(a, b, c, d, tx, ty);
}

@interface LaceView () {
    LaceParticle *_particles;
    LaceConstraint *_constraints;
    NSInteger *_indices;
    CGPoint *_renderPositions;
    NSInteger _particleCount;
    NSInteger _constraintCount;
    NSInteger _columns;
    NSInteger _rows;
    NSInteger _constraintCapacity;
    CGFloat _cellWidth;
    CGFloat _cellHeight;
    CGFloat _openAmount;
    CGFloat _openVelocity;
    CGFloat _targetOpenAmount;
    CGFloat _lastReportedOpenProgress;
    CFTimeInterval _lastTimestamp;
    CGFloat _elapsed;
    NSTrackingArea *_trackingArea;
    BOOL _hoveringBar;
    BOOL _usesTexturedLace;
    BOOL _usesMetalLace;
    BOOL _renderingStaticPreview;
    BOOL _hasPointerSample;
    BOOL _pointerActive;
    CGPoint _pointerPosition;
    CGPoint _previousPointerPosition;
    CGPoint _pointerVelocity;
    NSInteger _draggedParticleIndex;
    BOOL _draggingBar;
    BOOL _barDidMove;
    BOOL _tipPullCandidate;
    BOOL _tipPullArmed;
    CGPoint _dragTarget;
    CGPoint _dragStartMousePoint;
    CGPoint _dragStartParticlePosition;
    CGPoint _dragStartRestPosition;
    CGPoint _barDragStartPoint;
    CGFloat _barDragStartOpenAmount;
}

@property (nonatomic, strong, nullable) NSTimer *animationTimer;
@property (nonatomic, strong, nullable) LaceMetalView *metalView;
@property (nonatomic, strong, nullable) LaceBarOverlayView *barOverlayView;
@property (nonatomic, strong, nullable) NSImage *laceImage;
@property (nonatomic, copy, readwrite) NSString *motifName;

- (void)reportOpenProgressIfNeeded;

@end


@implementation LaceView

- (instancetype)initWithFrame:(NSRect)frameRect {
    return [self initWithFrame:frameRect startAnimation:YES];
}

- (instancetype)initWithFrame:(NSRect)frameRect startAnimation:(BOOL)startAnimation {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.backgroundColor = NSColor.clearColor.CGColor;
        // A moderately coarse physical mesh is enough because Metal
        // interpolates the texture between vertices. This keeps the main
        // thread comfortably below a frame budget even on older Macs.
        _columns = 25;
        _rows = 13;
        _openAmount = 0.0;
        _targetOpenAmount = 0.0;
        _lastReportedOpenProgress = -1.0;
        _draggedParticleIndex = -1;
        [self rebuildCloth];
        [self setupTexturedLace];
        self.barOverlayView = [[LaceBarOverlayView alloc] initWithFrame:self.bounds];
        self.barOverlayView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        self.barOverlayView.laceOpen = NO;
        [self addSubview:self.barOverlayView positioned:NSWindowAbove relativeTo:self.metalView];
        if (startAnimation) {
            __weak typeof(self) weakSelf = self;
            self.animationTimer = [NSTimer scheduledTimerWithTimeInterval:(1.0 / 60.0)
                                                                  repeats:YES
                                                                    block:^(NSTimer *timer) {
                [weakSelf animationTick:timer];
            }];
            [[NSRunLoop mainRunLoop] addTimer:self.animationTimer forMode:NSRunLoopCommonModes];
        }
    }
    return self;
}

- (void)dealloc {
    [self.animationTimer invalidate];
    free(_particles);
    free(_constraints);
    free(_indices);
    free(_renderPositions);
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    return YES;
}

- (BOOL)isOpen {
    return _targetOpenAmount > 0.5;
}

- (BOOL)isDragging {
    return _draggingBar || _draggedParticleIndex >= 0;
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    self.metalView.frame = self.bounds;
    [self rebuildCloth];
    [self updateTexturedGeometry];
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_trackingArea) {
        [self removeTrackingArea:_trackingArea];
    }
    _trackingArea = [[NSTrackingArea alloc] initWithRect:[self barRect]
                                                options:(NSTrackingMouseEnteredAndExited |
                                                         NSTrackingActiveAlways |
                                                         NSTrackingInVisibleRect)
                                                  owner:self
                                               userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)mouseEntered:(NSEvent *)event {
    _hoveringBar = YES;
    self.barOverlayView.hovered = YES;
    [self setNeedsDisplay:YES];
}

- (void)mouseExited:(NSEvent *)event {
    _hoveringBar = NO;
    self.barOverlayView.hovered = NO;
    [self setNeedsDisplay:YES];
}

- (void)setBarHoveredFromPolling:(BOOL)hovered {
    if (_hoveringBar == hovered) return;
    _hoveringBar = hovered;
    self.barOverlayView.hovered = hovered;
    [self updateTrackingAreas];
    [self setNeedsDisplay:YES];
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    _tipPullCandidate = NO;
    _tipPullArmed = NO;
    if (NSPointInRect(point, NSInsetRect([self barRect], -12.0, -8.0))) {
        _draggingBar = YES;
        _barDidMove = NO;
        _barDragStartPoint = point;
        _barDragStartOpenAmount = LaceClamp(_openAmount, 0.0, 1.0);
        _targetOpenAmount = _openAmount;
        _openVelocity = 0.0;
        return;
    }

    if ([self isPointInsideLace:point]) {
        NSInteger nearestIndex = -1;
        CGFloat nearestDistance = CGFLOAT_MAX;
        for (NSInteger index = 0; index < _particleCount; index++) {
            if (_particles[index].row == 0) continue;
            CGFloat distance = LacePointLength(LacePointSubtract(_particles[index].position, point));
            if (distance < nearestDistance) {
                nearestDistance = distance;
                nearestIndex = index;
            }
        }
        if (nearestIndex >= 0 && nearestDistance < 72.0) {
            _draggedParticleIndex = nearestIndex;
            _dragStartMousePoint = point;
            _dragStartParticlePosition = _particles[nearestIndex].position;
            _dragStartRestPosition = _particles[nearestIndex].rest;
            _dragTarget = _dragStartParticlePosition;
            _particles[nearestIndex].previous = _particles[nearestIndex].position;
            NSInteger centerColumn = (_columns - 1) / 2;
            BOOL nearBottomPoint = _particles[nearestIndex].row >= _rows - 2 &&
                                   labs(_particles[nearestIndex].column - centerColumn) <= 2;
            _tipPullCandidate = self.isOpen && nearBottomPoint;
        }
    }
}

- (void)mouseDragged:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (_draggingBar) {
        CGFloat deltaY = point.y - _barDragStartPoint.y;
        if (fabs(deltaY) > 4.0) _barDidMove = YES;
        _openAmount = LaceClamp(_barDragStartOpenAmount + deltaY / 310.0, 0.0, 1.0);
        _targetOpenAmount = _openAmount;
        _openVelocity = 0.0;
        self.barOverlayView.laceOpen = _targetOpenAmount > 0.5;
        [self reportOpenProgressIfNeeded];
        [self setNeedsDisplay:YES];
    } else if (_draggedParticleIndex >= 0) {
        CGPoint rawDelta = LacePointSubtract(point, _dragStartMousePoint);
        if (_tipPullCandidate && rawDelta.y > 24.0 && fabs(rawDelta.x) < 82.0) {
            _tipPullArmed = YES;
        }
        CGFloat rawDistance = LacePointLength(rawDelta);
        // The reference behaves like firm crochet, not elastic rubber. After
        // a short natural pull the resistance rises sharply and then stops.
        CGFloat maximumDistance = MIN(96.0,
                                      MAX(76.0, NSHeight(self.bounds) * 0.18));
        CGFloat softLimit = maximumDistance * 0.64;
        CGFloat effectiveDistance = rawDistance;
        if (rawDistance > softLimit) {
            CGFloat extra = rawDistance - softLimit;
            CGFloat remaining = maximumDistance - softLimit;
            effectiveDistance = softLimit + remaining * (1.0 - exp(-extra / MAX(remaining, 1.0)));
        }
        effectiveDistance = MIN(effectiveDistance, maximumDistance);
        CGPoint direction = rawDistance > 0.001
            ? LacePointScale(rawDelta, 1.0 / rawDistance)
            : CGPointZero;
        _dragTarget = LacePointAdd(_dragStartParticlePosition,
                                   LacePointScale(direction, effectiveDistance));
    }
}

- (void)mouseUp:(NSEvent *)event {
    if (_draggingBar) {
        _draggingBar = NO;
        if (_barDidMove) {
            // Roller-blind latch: the first deliberate pull opens the lace
            // and leaves it down. A second tug on the bottom point releases it.
            BOOL pulledFarEnough = _openAmount > MAX(0.15, _barDragStartOpenAmount + 0.12);
            BOOL shouldLatchOpen = _barDragStartOpenAmount > 0.50 || pulledFarEnough;
            [self setLaceOpen:shouldLatchOpen animated:YES];
        } else {
            [self toggleLace];
        }
        return;
    }
    if (_draggedParticleIndex >= 0) {
        BOOL shouldRetract = _tipPullArmed;
        // Release without preserving a catapult velocity: the whole local
        // patch settles back smoothly instead of snapping or oscillating.
        for (NSInteger index = 0; index < _particleCount; index++) {
            _particles[index].previous = _particles[index].position;
        }
        _draggedParticleIndex = -1;
        _tipPullCandidate = NO;
        _tipPullArmed = NO;
        if (shouldRetract) {
            [self setLaceOpen:NO animated:YES];
        }
    }
}

- (void)toggleLace {
    [self setLaceOpen:!self.isOpen animated:YES];
}

- (void)setLaceOpen:(BOOL)open animated:(BOOL)animated {
    _targetOpenAmount = open ? 1.0 : 0.0;
    self.barOverlayView.laceOpen = open;
    if (!animated) {
        _openAmount = _targetOpenAmount;
        _openVelocity = 0.0;
        [self resetParticlesToCurrentPose];
        [self setNeedsDisplay:YES];
        [self reportOpenProgressIfNeeded];
    }
    if (self.openStateDidChange) {
        self.openStateDidChange(open);
    }
}

- (void)reportOpenProgressIfNeeded {
    CGFloat progress = LaceClamp(_openAmount, 0.0, 1.0);
    if (fabs(progress - _lastReportedOpenProgress) < 0.001) return;
    _lastReportedOpenProgress = progress;
    if (self.openProgressDidChange) {
        self.openProgressDidChange(progress);
    }
}

- (NSRect)barRect {
    CGFloat width = _hoveringBar ? 190.0 : 176.0;
    return NSMakeRect((NSWidth(self.bounds) - width) * 0.5, 0.0, width, 26.0);
}

- (NSRect)interactionRectInWindow {
    return [self convertRect:NSInsetRect([self barRect], -12.0, -8.0) toView:nil];
}

- (BOOL)isPointInsideLace:(CGPoint)point {
    if (LaceClamp(_openAmount, 0.0, 1.0) < 0.12) return NO;
    CGFloat clothWidth = MIN(NSWidth(self.bounds) - 28.0, 1080.0);
    CGFloat clothHeight = MIN(NSHeight(self.bounds) - 24.0, 430.0);
    CGFloat left = (NSWidth(self.bounds) - clothWidth) * 0.5;
    CGFloat u = (point.x - left) / MAX(clothWidth, 1.0);
    if (u < 0.0 || u > 1.0 || point.y < 0.0) return NO;
    CGFloat triangularDepth = (1.0 - fabs(u * 2.0 - 1.0)) * clothHeight;
    return point.y <= triangularDepth + 34.0;
}

- (BOOL)shouldCaptureMouseAtWindowPoint:(NSPoint)windowPoint {
    if (self.isDragging) return YES;
    CGPoint localPoint = [self convertPoint:windowPoint fromView:nil];
    if (NSPointInRect(localPoint, NSInsetRect([self barRect], -12.0, -8.0))) return YES;
    return [self isPointInsideLace:localPoint];
}

- (void)setupTexturedLace {
    [self setMotifNamed:LaceMotifFlower];
}

- (BOOL)setMotifNamed:(NSString *)motifName {
    NSString *resourceName = LaceResourceNameForMotif(motifName);
    if (!resourceName) return NO;

    NSBundle *resourceBundle = [NSBundle bundleForClass:self.class];
    NSString *texturePath = [resourceBundle pathForResource:resourceName ofType:@"png"];
    if (!texturePath) texturePath = [NSBundle.mainBundle pathForResource:resourceName ofType:@"png"];
    if (!texturePath) return NO;
    NSImage *image = [[NSImage alloc] initWithContentsOfFile:texturePath];
    if (!image) return NO;

    _usesTexturedLace = YES;
    NSURL *textureURL = [NSURL fileURLWithPath:texturePath];
    if (self.metalView) {
        NSError *textureError = nil;
        if (![self.metalView setTextureURL:textureURL error:&textureError]) {
            NSLog(@"LaceDrop texture switch error: %@", textureError.localizedDescription);
            return NO;
        }
    } else {
        self.metalView = [[LaceMetalView alloc] initWithFrame:self.bounds
                                                   textureURL:textureURL
                                                      columns:_columns
                                                         rows:_rows];
        _usesMetalLace = self.metalView.isRendererReady;
        if (_usesMetalLace) {
            [self addSubview:self.metalView positioned:NSWindowBelow relativeTo:nil];
        } else {
            self.metalView = nil;
            NSLog(@"LaceDrop: Metal renderer unavailable, using Core Graphics fallback.");
        }
    }
    self.laceImage = image;
    self.motifName = [motifName copy];
    [self updateTexturedGeometry];
    if (!_usesMetalLace) [self setNeedsDisplay:YES];
    return YES;
}

- (void)updateTexturedGeometry {
    if (!_usesMetalLace || !self.metalView || _particleCount == 0) return;
    if (!_renderPositions) {
        _renderPositions = calloc((NSUInteger)(_columns * _rows), sizeof(CGPoint));
    }
    for (NSInteger row = 0; row < _rows; row++) {
        for (NSInteger column = 0; column < _columns; column++) {
            NSInteger gridIndex = row * _columns + column;
            NSInteger particleIndex = [self indexForColumn:column row:row];
            _renderPositions[gridIndex] = _particles[particleIndex].position;
        }
    }
    CGFloat visibleAmount = LaceClamp(_openAmount, 0.0, 1.0);
    CGFloat opacity = LaceSmoothStep(LaceClamp((visibleAmount - 0.025) / 0.20, 0.0, 1.0));
    [self.metalView updateParticlePositions:_renderPositions count:_particleCount opacity:opacity];
}

- (NSInteger)indexForColumn:(NSInteger)column row:(NSInteger)row {
    if (column < 0 || column >= _columns || row < 0 || row >= _rows || !_indices) {
        return -1;
    }
    return _indices[row * _columns + column];
}

- (void)addConstraintFrom:(NSInteger)a to:(NSInteger)b kind:(LaceConstraintKind)kind {
    if (a < 0 || b < 0 || a == b) return;
    if (_constraintCount >= _constraintCapacity) {
        _constraintCapacity = MAX(256, _constraintCapacity * 2);
        _constraints = realloc(_constraints, sizeof(LaceConstraint) * _constraintCapacity);
    }
    CGPoint delta = LacePointSubtract(_particles[b].rest, _particles[a].rest);
    _constraints[_constraintCount++] = (LaceConstraint){a, b, LacePointLength(delta), kind};
}

- (void)rebuildCloth {
    if (NSWidth(self.bounds) < 10.0 || NSHeight(self.bounds) < 10.0) return;

    free(_particles);
    free(_constraints);
    free(_indices);
    _particles = NULL;
    _constraints = NULL;
    _indices = NULL;
    _particleCount = 0;
    _constraintCount = 0;
    _constraintCapacity = 0;

    NSInteger gridSize = _columns * _rows;
    _indices = malloc(sizeof(NSInteger) * gridSize);
    for (NSInteger index = 0; index < gridSize; index++) _indices[index] = -1;

    _particles = calloc(gridSize, sizeof(LaceParticle));
    CGFloat clothWidth = MIN(NSWidth(self.bounds) - 28.0, 1080.0);
    CGFloat left = (NSWidth(self.bounds) - clothWidth) * 0.5;
    // The lace is sewn directly to the top edge. The black notch is painted
    // over it, matching the reference without an artificial gap.
    CGFloat top = 0.0;
    CGFloat clothHeight = MIN(NSHeight(self.bounds) - top - 24.0, 430.0);
    _cellWidth = clothWidth / (_columns - 1);
    _cellHeight = clothHeight / (_rows - 1);

    for (NSInteger column = 0; column < _columns; column++) {
        NSInteger maximumRow = _rows - 1;
        for (NSInteger row = 0; row <= maximumRow; row++) {
            CGFloat x = left + column * _cellWidth;
            CGFloat y = top + row * _cellHeight;
            NSInteger particleIndex = _particleCount++;
            _indices[row * _columns + column] = particleIndex;
            LaceParticle particle;
            particle.position = CGPointMake(x, y);
            particle.previous = particle.position;
            particle.rest = particle.position;
            particle.column = column;
            particle.row = row;
            particle.topAnchor = (row == 0);
            _particles[particleIndex] = particle;
        }
    }

    for (NSInteger row = 0; row < _rows; row++) {
        for (NSInteger column = 0; column < _columns; column++) {
            NSInteger current = [self indexForColumn:column row:row];
            if (current < 0) continue;
            [self addConstraintFrom:current to:[self indexForColumn:column + 1 row:row]
                              kind:LaceConstraintStructural];
            [self addConstraintFrom:current to:[self indexForColumn:column row:row + 1]
                              kind:LaceConstraintStructural];
            [self addConstraintFrom:current to:[self indexForColumn:column + 1 row:row + 1]
                              kind:LaceConstraintShear];
            [self addConstraintFrom:current to:[self indexForColumn:column - 1 row:row + 1]
                              kind:LaceConstraintShear];
            [self addConstraintFrom:current to:[self indexForColumn:column + 2 row:row]
                              kind:LaceConstraintBend];
            [self addConstraintFrom:current to:[self indexForColumn:column row:row + 2]
                              kind:LaceConstraintBend];
        }
    }
    [self resetParticlesToCurrentPose];
    [self updateTexturedGeometry];
}

- (CGPoint)collapsedPositionForParticle:(LaceParticle)particle {
    CGFloat phase = particle.column * 0.74 + particle.row * 0.91;
    // Closing preserves the full stitched width. Only the vertical dimension
    // gathers into a thin band along the physical screen edge.
    CGFloat x = particle.rest.x + sin(phase) * 0.75;
    CGFloat y = -2.0 + particle.row * 0.58 + cos(phase * 1.17) * 0.65;
    return CGPointMake(x, y);
}

- (CGPoint)goalForParticle:(LaceParticle)particle openAmount:(CGFloat)amount {
    CGPoint collapsed = [self collapsedPositionForParticle:particle];
    CGFloat eased = LaceSmoothStep(amount);
    CGPoint goal = CGPointMake(collapsed.x + (particle.rest.x - collapsed.x) * eased,
                               collapsed.y + (particle.rest.y - collapsed.y) * eased);
    CGFloat fold = sin(particle.column * 0.66 + particle.row * 1.19 + _elapsed * 1.25);
    CGFloat foldStrength = sin(M_PI * amount) * (1.0 - (CGFloat)particle.row / _rows * 0.35);
    goal.x += fold * foldStrength * 2.2;
    goal.y += cos(particle.column * 0.39 - particle.row * 0.71 + _elapsed * 1.1)
        * foldStrength * 3.0;

    // A real crocheted piece never settles into a mathematically flat plane.
    // Keep a few sub-pixel tension ripples even when it is fully open.
    CGFloat rowAmount = (CGFloat)particle.row / MAX(1.0, (CGFloat)(_rows - 1));
    CGFloat columnAmount = (CGFloat)particle.column / MAX(1.0, (CGFloat)(_columns - 1));
    CGFloat hangingEnvelope = amount * rowAmount * (0.42 + 0.58 * sin(M_PI * columnAmount));
    goal.x += sin(particle.column * 0.81 + particle.row * 0.47) * hangingEnvelope * 0.85;
    goal.y += cos(particle.column * 0.56 - particle.row * 0.63) * hangingEnvelope * 1.35;
    return goal;
}

- (void)resetParticlesToCurrentPose {
    for (NSInteger index = 0; index < _particleCount; index++) {
        CGPoint goal = [self goalForParticle:_particles[index] openAmount:_openAmount];
        _particles[index].position = goal;
        _particles[index].previous = goal;
    }
}

- (void)animationTick:(NSTimer *)timer {
    CFTimeInterval now = CACurrentMediaTime();
    CGFloat deltaTime = _lastTimestamp > 0.0 ? (CGFloat)(now - _lastTimestamp) : (1.0 / 60.0);
    _lastTimestamp = now;
    deltaTime = LaceClamp(deltaTime, 1.0 / 120.0, 1.0 / 30.0);
    [self samplePointerWithDeltaTime:deltaTime];
    BOOL restingClosed = _targetOpenAmount <= 0.0 && _openAmount <= 0.0 &&
                         fabs(_openVelocity) < 0.0001 && !self.isDragging;
    if (restingClosed) return;
    [self advanceSimulation:deltaTime];
    [self reportOpenProgressIfNeeded];
    [self updateTexturedGeometry];
    if (!_usesMetalLace) [self setNeedsDisplay:YES];
}

- (void)samplePointerWithDeltaTime:(CGFloat)deltaTime {
    if (!self.window) {
        _pointerActive = NO;
        _hasPointerSample = NO;
        return;
    }

    NSPoint screenPoint = NSEvent.mouseLocation;
    NSPoint windowPoint = [self.window convertPointFromScreen:screenPoint];
    CGPoint localPoint = [self convertPoint:windowPoint fromView:nil];
    _pointerActive = NSPointInRect(localPoint, NSInsetRect(self.bounds, -90.0, -90.0));

    if (_hasPointerSample && deltaTime > 0.0) {
        CGPoint rawVelocity = LacePointScale(LacePointSubtract(localPoint, _previousPointerPosition),
                                             1.0 / deltaTime);
        CGFloat speed = LacePointLength(rawVelocity);
        if (speed > 1500.0) rawVelocity = LacePointScale(rawVelocity, 1500.0 / speed);
        _pointerVelocity = LacePointAdd(LacePointScale(_pointerVelocity, 0.76),
                                        LacePointScale(rawVelocity, 0.24));
    } else {
        _pointerVelocity = CGPointZero;
        _hasPointerSample = YES;
    }
    _previousPointerPosition = localPoint;
    _pointerPosition = localPoint;
}

- (void)advanceSimulation:(CGFloat)deltaTime {
    _elapsed += deltaTime;

    CGFloat stiffness = 78.0;
    CGFloat damping = 17.5;
    CGFloat acceleration = (_targetOpenAmount - _openAmount) * stiffness - _openVelocity * damping;
    _openVelocity += acceleration * deltaTime;
    _openAmount += _openVelocity * deltaTime;
    if (fabs(_targetOpenAmount - _openAmount) < 0.0005 && fabs(_openVelocity) < 0.005) {
        _openAmount = _targetOpenAmount;
        _openVelocity = 0.0;
    }
    _openAmount = LaceClamp(_openAmount, -0.025, 1.025);
    CGFloat visibleAmount = LaceClamp(_openAmount, 0.0, 1.0);

    CGFloat deltaSquared = deltaTime * deltaTime;
    CGFloat goalSpring = 0.070 + (1.0 - visibleAmount) * 0.060;
    for (NSInteger index = 0; index < _particleCount; index++) {
        LaceParticle *particle = &_particles[index];
        CGPoint goal = [self goalForParticle:*particle openAmount:visibleAmount];

        if (_draggedParticleIndex >= 0 && index != _draggedParticleIndex && !particle->topAnchor) {
            CGFloat restDistance = LacePointLength(LacePointSubtract(particle->rest,
                                                                      _dragStartRestPosition));
            CGFloat influenceRadius = 155.0;
            if (restDistance < influenceRadius) {
                CGFloat influence = 1.0 - restDistance / influenceRadius;
                influence = influence * influence * 0.58;
                CGPoint dragOffset = LacePointSubtract(_dragTarget, _dragStartParticlePosition);
                goal = LacePointAdd(goal, LacePointScale(dragOffset, influence));
            }
        }

        if (index == _draggedParticleIndex) {
            CGPoint old = particle->position;
            particle->position = _dragTarget;
            particle->previous = old;
            continue;
        }

        if (particle->topAnchor) {
            CGPoint old = particle->position;
            particle->position = goal;
            particle->previous = old;
            continue;
        }

        CGPoint velocity = LacePointScale(LacePointSubtract(particle->position, particle->previous), 0.945);
        particle->previous = particle->position;

        CGPoint towardGoal = LacePointSubtract(goal, particle->position);
        CGFloat rowAmount = (CGFloat)particle->row / MAX(1.0, (CGFloat)(_rows - 1));
        CGFloat breeze = sin(_elapsed * 0.76 + particle->column * 0.31 + particle->row * 0.13)
            + 0.42 * sin(_elapsed * 1.17 - particle->column * 0.19 + particle->row * 0.27);
        CGFloat gravity = 54.0 * visibleAmount;
        CGPoint force = CGPointMake(towardGoal.x * goalSpring / MAX(deltaSquared, 0.00001)
                                    + breeze * (7.0 + 22.0 * rowAmount) * visibleAmount,
                                    towardGoal.y * goalSpring / MAX(deltaSquared, 0.00001)
                                    + gravity
                                    + cos(_elapsed * 0.9 + particle->column * 0.17) * 6.0 * rowAmount);
        particle->position = LacePointAdd(particle->position,
                                          LacePointAdd(velocity, LacePointScale(force, deltaSquared)));

        // The cursor transfers momentum into nearby threads while the
        // transparent window continues passing desktop clicks through.
        if (_pointerActive && visibleAmount > 0.20) {
            CGPoint fromPointer = LacePointSubtract(particle->position, _pointerPosition);
            CGFloat distance = LacePointLength(fromPointer);
            CGFloat radius = 96.0;
            if (distance < radius) {
                CGFloat falloff = 1.0 - distance / radius;
                falloff = falloff * falloff * (0.30 + 0.70 * rowAmount);
                CGPoint normal = distance > 0.5
                    ? LacePointScale(fromPointer, 1.0 / distance)
                    : CGPointMake(0.0, 1.0);
                CGPoint carriedMotion = LacePointScale(_pointerVelocity, 0.00062 * falloff);
                CGPoint softPush = LacePointScale(normal, 0.32 * falloff);
                particle->position = LacePointAdd(particle->position,
                                                  LacePointAdd(carriedMotion, softPush));
            }
        }
    }

    CGFloat verticalScale = 0.035 + 0.965 * LaceSmoothStep(visibleAmount);
    for (NSInteger iteration = 0; iteration < 4; iteration++) {
        for (NSInteger constraintIndex = 0; constraintIndex < _constraintCount; constraintIndex++) {
            LaceConstraint constraint = _constraints[constraintIndex];
            LaceParticle *a = &_particles[constraint.a];
            LaceParticle *b = &_particles[constraint.b];
            CGPoint delta = LacePointSubtract(b->position, a->position);
            CGFloat distance = MAX(0.001, LacePointLength(delta));
            CGPoint restDelta = LacePointSubtract(b->rest, a->rest);
            CGFloat desired = hypot(restDelta.x, restDelta.y * verticalScale);
            CGFloat kindStiffness = constraint.kind == LaceConstraintBend ? 0.40 :
                                    (constraint.kind == LaceConstraintShear ? 0.76 : 0.96);
            CGFloat correctionAmount = ((distance - desired) / distance) * kindStiffness;
            CGPoint correction = LacePointScale(delta, correctionAmount);
            BOOL aFixed = a->topAnchor || constraint.a == _draggedParticleIndex;
            BOOL bFixed = b->topAnchor || constraint.b == _draggedParticleIndex;
            if (!aFixed && !bFixed) {
                a->position = LacePointAdd(a->position, LacePointScale(correction, 0.5));
                b->position = LacePointSubtract(b->position, LacePointScale(correction, 0.5));
            } else if (aFixed && !bFixed) {
                b->position = LacePointSubtract(b->position, correction);
            } else if (!aFixed && bFixed) {
                a->position = LacePointAdd(a->position, correction);
            }
        }

        for (NSInteger index = 0; index < _particleCount; index++) {
            if (_particles[index].topAnchor) {
                _particles[index].position = [self goalForParticle:_particles[index]
                                                         openAmount:visibleAmount];
            }
        }
        if (_draggedParticleIndex >= 0) {
            _particles[_draggedParticleIndex].position = _dragTarget;
        }
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    CGContextRef context = NSGraphicsContext.currentContext.CGContext;
    if (!context) return;

    CGFloat visibleAmount = LaceClamp(_openAmount, 0.0, 1.0);
    CGFloat laceAlpha = LaceSmoothStep(LaceClamp((visibleAmount - 0.035) / 0.28, 0.0, 1.0));
    if (laceAlpha > 0.002 && !_renderingStaticPreview && !_usesMetalLace) {
        if (_usesTexturedLace) {
            [self drawTexturedLaceInContext:context alpha:laceAlpha];
        } else {
            [self drawLaceInContext:context alpha:laceAlpha];
        }
    }
    [self drawBarInContext:context];
}

- (void)drawImageTriangleInContext:(CGContextRef)context
                           source0:(CGPoint)source0
                           source1:(CGPoint)source1
                           source2:(CGPoint)source2
                      destination0:(CGPoint)destination0
                      destination1:(CGPoint)destination1
                      destination2:(CGPoint)destination2
                             alpha:(CGFloat)alpha
                       sourceBounds:(NSRect)sourceBounds {
    CGContextSaveGState(context);
    CGContextBeginPath(context);
    CGContextMoveToPoint(context, destination0.x, destination0.y);
    CGContextAddLineToPoint(context, destination1.x, destination1.y);
    CGContextAddLineToPoint(context, destination2.x, destination2.y);
    CGContextClosePath(context);
    CGContextClip(context);

    CGAffineTransform transform = LaceTriangleTransform(source0, source1, source2,
                                                         destination0, destination1, destination2);
    CGContextConcatCTM(context, transform);
    [self.laceImage drawInRect:sourceBounds
                      fromRect:NSZeroRect
                     operation:NSCompositingOperationSourceOver
                      fraction:alpha
                respectFlipped:YES
                         hints:@{NSImageHintInterpolation: @(NSImageInterpolationHigh)}];
    CGContextRestoreGState(context);
}

- (void)drawTexturedLaceInContext:(CGContextRef)context alpha:(CGFloat)alpha {
    if (!self.laceImage) return;
    CGFloat imageWidth = self.laceImage.size.width;
    CGFloat imageHeight = self.laceImage.size.height;
    if (imageWidth <= 0.0 || imageHeight <= 0.0) return;
    // The generated texture contains a small transparent export margin above
    // the first continuous thread. Skip it so the thread touches screen y=0.
    // Push the texture's straight reinforced seam behind the physical top
    // edge so only the hanging crochet remains visible on screen.
    CGFloat textureTopCrop = MIN(74.0, imageHeight * 0.12);
    CGFloat textureContentHeight = imageHeight - textureTopCrop;

    NSRect sourceBounds = NSMakeRect(0.0, 0.0, imageWidth, imageHeight);
    const NSInteger columnStep = 4;
    const NSInteger rowStep = 3;
    CGContextSaveGState(context);
    CGContextSetShouldAntialias(context, NO);
    CGContextSetInterpolationQuality(context, kCGInterpolationHigh);

    for (NSInteger row = 0; row < _rows - 1; row += rowStep) {
        NSInteger nextRow = MIN(row + rowStep, _rows - 1);
        for (NSInteger column = 0; column < _columns - 1; column += columnStep) {
            NSInteger nextColumn = MIN(column + columnStep, _columns - 1);
            NSInteger topLeftIndex = [self indexForColumn:column row:row];
            NSInteger topRightIndex = [self indexForColumn:nextColumn row:row];
            NSInteger bottomLeftIndex = [self indexForColumn:column row:nextRow];
            NSInteger bottomRightIndex = [self indexForColumn:nextColumn row:nextRow];
            if (topLeftIndex < 0 || topRightIndex < 0 || bottomLeftIndex < 0 || bottomRightIndex < 0) continue;

            CGFloat sourceLeft = (CGFloat)column / (_columns - 1) * imageWidth;
            CGFloat sourceRight = (CGFloat)nextColumn / (_columns - 1) * imageWidth;
            CGFloat sourceTop = textureTopCrop
                + (CGFloat)row / (_rows - 1) * textureContentHeight;
            CGFloat sourceBottom = textureTopCrop
                + (CGFloat)nextRow / (_rows - 1) * textureContentHeight;
            CGPoint sourceTopLeft = CGPointMake(sourceLeft, sourceTop);
            CGPoint sourceTopRight = CGPointMake(sourceRight, sourceTop);
            CGPoint sourceBottomLeft = CGPointMake(sourceLeft, sourceBottom);
            CGPoint sourceBottomRight = CGPointMake(sourceRight, sourceBottom);

            CGPoint destinationTopLeft = _particles[topLeftIndex].position;
            CGPoint destinationTopRight = _particles[topRightIndex].position;
            CGPoint destinationBottomLeft = _particles[bottomLeftIndex].position;
            CGPoint destinationBottomRight = _particles[bottomRightIndex].position;

            [self drawImageTriangleInContext:context
                                     source0:sourceTopLeft
                                     source1:sourceBottomLeft
                                     source2:sourceTopRight
                                destination0:destinationTopLeft
                                destination1:destinationBottomLeft
                                destination2:destinationTopRight
                                       alpha:alpha
                                 sourceBounds:sourceBounds];
            [self drawImageTriangleInContext:context
                                     source0:sourceTopRight
                                     source1:sourceBottomLeft
                                     source2:sourceBottomRight
                                destination0:destinationTopRight
                                destination1:destinationBottomLeft
                                destination2:destinationBottomRight
                                       alpha:alpha
                                 sourceBounds:sourceBounds];
        }
    }
    CGContextRestoreGState(context);
}

- (void)drawLaceInContext:(CGContextRef)context alpha:(CGFloat)alpha {
    CGContextSaveGState(context);
    CGContextSetLineCap(context, kCGLineCapRound);
    CGContextSetLineJoin(context, kCGLineJoinRound);

    // A soft contact shadow makes the threads sit above the wallpaper without
    // turning the transparent holes into an opaque image.
    CGContextSetShadowWithColor(context, CGSizeMake(0.0, 2.0), 3.0,
                                [NSColor colorWithWhite:0.0 alpha:0.33 * alpha].CGColor);

    CGContextBeginPath(context);
    for (NSInteger constraintIndex = 0; constraintIndex < _constraintCount; constraintIndex++) {
        LaceConstraint constraint = _constraints[constraintIndex];
        if (constraint.kind == LaceConstraintBend) continue;
        CGPoint a = _particles[constraint.a].position;
        CGPoint b = _particles[constraint.b].position;
        CGContextMoveToPoint(context, a.x, a.y);
        CGContextAddLineToPoint(context, b.x, b.y);
    }
    CGContextSetStrokeColorWithColor(context, [NSColor colorWithWhite:0.96 alpha:0.72 * alpha].CGColor);
    CGContextSetLineWidth(context, 0.78);
    CGContextStrokePath(context);

    // A second, warmer strand gives the net a thread-like highlight.
    CGContextSetShadowWithColor(context, CGSizeZero, 0.0, NULL);
    CGContextBeginPath(context);
    for (NSInteger constraintIndex = 0; constraintIndex < _constraintCount; constraintIndex++) {
        LaceConstraint constraint = _constraints[constraintIndex];
        if (constraint.kind != LaceConstraintStructural) continue;
        CGPoint a = _particles[constraint.a].position;
        CGPoint b = _particles[constraint.b].position;
        CGContextMoveToPoint(context, a.x, a.y);
        CGContextAddLineToPoint(context, b.x, b.y);
    }
    CGContextSetStrokeColorWithColor(context, [NSColor colorWithRed:1.0 green:0.985 blue:0.95 alpha:0.56 * alpha].CGColor);
    CGContextSetLineWidth(context, 0.48);
    CGContextStrokePath(context);

    [self drawFlowersInContext:context alpha:alpha];
    [self drawBorderInContext:context alpha:alpha];
    CGContextRestoreGState(context);
}

- (void)drawFlowersInContext:(CGContextRef)context alpha:(CGFloat)alpha {
    for (NSInteger row = 4; row < _rows; row += 5) {
        NSInteger offset = ((row / 5) % 2) ? 2 : 0;
        for (NSInteger column = 3 + offset; column < _columns - 2; column += 6) {
            NSInteger centerIndex = [self indexForColumn:column row:row];
            NSInteger leftIndex = [self indexForColumn:column - 1 row:row];
            NSInteger rightIndex = [self indexForColumn:column + 1 row:row];
            NSInteger upIndex = [self indexForColumn:column row:row - 1];
            NSInteger downIndex = [self indexForColumn:column row:row + 1];
            if (centerIndex < 0 || leftIndex < 0 || rightIndex < 0 || upIndex < 0 || downIndex < 0) continue;

            CGPoint center = _particles[centerIndex].position;
            CGPoint xAxis = LacePointScale(LacePointSubtract(_particles[rightIndex].position,
                                                              _particles[leftIndex].position),
                                            0.5 / MAX(_cellWidth, 1.0));
            CGPoint yAxis = LacePointScale(LacePointSubtract(_particles[downIndex].position,
                                                              _particles[upIndex].position),
                                            0.5 / MAX(_cellHeight, 1.0));
            CGAffineTransform transform = CGAffineTransformMake(xAxis.x, xAxis.y,
                                                                 yAxis.x, yAxis.y,
                                                                 center.x, center.y);

            CGMutablePathRef flower = CGPathCreateMutable();
            CGFloat innerRadius = 4.1;
            CGFloat outerRadius = MIN(_cellWidth, _cellHeight) * 1.18;
            NSInteger petals = 10;
            for (NSInteger petal = 0; petal < petals; petal++) {
                CGFloat angle = -M_PI_2 + (CGFloat)petal * (M_PI * 2.0 / petals);
                CGFloat halfWidth = M_PI / petals * 0.62;
                CGPoint start = CGPointMake(cos(angle - halfWidth) * innerRadius,
                                            sin(angle - halfWidth) * innerRadius);
                CGPoint end = CGPointMake(cos(angle + halfWidth) * innerRadius,
                                          sin(angle + halfWidth) * innerRadius);
                CGPoint control1 = CGPointMake(cos(angle - halfWidth * 0.42) * outerRadius,
                                               sin(angle - halfWidth * 0.42) * outerRadius);
                CGPoint control2 = CGPointMake(cos(angle + halfWidth * 0.42) * outerRadius,
                                               sin(angle + halfWidth * 0.42) * outerRadius);
                CGPathMoveToPoint(flower, &transform, start.x, start.y);
                CGPathAddCurveToPoint(flower, &transform,
                                      control1.x, control1.y,
                                      control2.x, control2.y,
                                      end.x, end.y);
                CGPathAddCurveToPoint(flower, &transform,
                                      cos(angle) * innerRadius * 1.6, sin(angle) * innerRadius * 1.6,
                                      cos(angle) * innerRadius * 1.3, sin(angle) * innerRadius * 1.3,
                                      start.x, start.y);
            }
            CGPathAddEllipseInRect(flower, &transform,
                                   CGRectMake(-innerRadius, -innerRadius,
                                              innerRadius * 2.0, innerRadius * 2.0));

            CGContextAddPath(context, flower);
            CGContextSetStrokeColorWithColor(context,
                                              [NSColor colorWithRed:1.0 green:0.99 blue:0.97 alpha:0.96 * alpha].CGColor);
            CGContextSetLineWidth(context, 1.25);
            CGContextStrokePath(context);
            CGPathRelease(flower);
        }
    }
}

- (void)drawBorderInContext:(CGContextRef)context alpha:(CGFloat)alpha {
    CGMutablePathRef border = CGPathCreateMutable();
    BOOL started = NO;
    for (NSInteger column = 0; column < _columns; column++) {
        NSInteger index = [self indexForColumn:column row:0];
        if (index < 0) continue;
        CGPoint point = _particles[index].position;
        if (!started) {
            CGPathMoveToPoint(border, NULL, point.x, point.y);
            started = YES;
        } else {
            CGPathAddLineToPoint(border, NULL, point.x, point.y);
        }
    }
    for (NSInteger column = _columns - 1; column >= 0; column--) {
        NSInteger bottomIndex = -1;
        for (NSInteger row = _rows - 1; row >= 0; row--) {
            bottomIndex = [self indexForColumn:column row:row];
            if (bottomIndex >= 0) break;
        }
        if (bottomIndex >= 0) {
            CGPoint point = _particles[bottomIndex].position;
            CGPathAddLineToPoint(border, NULL, point.x, point.y);
        }
    }
    CGPathCloseSubpath(border);
    CGContextAddPath(context, border);
    CGContextSetStrokeColorWithColor(context, [NSColor colorWithWhite:1.0 alpha:0.97 * alpha].CGColor);
    CGContextSetLineWidth(context, 1.65);
    CGContextStrokePath(context);
    CGPathRelease(border);

    // Tiny loops along the lower edge keep the silhouette from looking cut out.
    for (NSInteger column = 1; column < _columns - 1; column += 2) {
        NSInteger bottomIndex = -1;
        for (NSInteger row = _rows - 1; row >= 0; row--) {
            bottomIndex = [self indexForColumn:column row:row];
            if (bottomIndex >= 0) break;
        }
        if (bottomIndex < 0) continue;
        CGPoint point = _particles[bottomIndex].position;
        CGFloat radius = 2.1 + 1.1 * sin(column * 0.9) * sin(column * 0.9);
        CGContextStrokeEllipseInRect(context, CGRectMake(point.x - radius, point.y - radius * 0.25,
                                                          radius * 2.0, radius * 1.55));
    }
}

- (void)drawBarInContext:(CGContextRef)context {
    NSRect bar = [self barRect];
    CGFloat radius = 11.0;
    CGPathRef path = CGPathCreateWithRoundedRect(bar, radius, radius, NULL);
    CGContextSaveGState(context);
    CGContextSetShadowWithColor(context, CGSizeMake(0.0, 3.0), 8.0,
                                [NSColor colorWithWhite:0.0 alpha:0.42].CGColor);
    CGContextAddPath(context, path);
    CGContextSetFillColorWithColor(context, [NSColor colorWithWhite:0.025 alpha:0.985].CGColor);
    CGContextFillPath(context);
    CGContextSetShadowWithColor(context, CGSizeZero, 0.0, NULL);

    CGFloat indicatorAlpha = _hoveringBar ? 0.95 : 0.58;
    CGFloat chevronY = NSMidY(bar) + (_targetOpenAmount > 0.5 ? 1.5 : -1.0);
    CGContextBeginPath(context);
    if (_targetOpenAmount > 0.5) {
        CGContextMoveToPoint(context, NSMidX(bar) - 5.0, chevronY + 2.0);
        CGContextAddLineToPoint(context, NSMidX(bar), chevronY - 2.0);
        CGContextAddLineToPoint(context, NSMidX(bar) + 5.0, chevronY + 2.0);
    } else {
        CGContextMoveToPoint(context, NSMidX(bar) - 5.0, chevronY - 2.0);
        CGContextAddLineToPoint(context, NSMidX(bar), chevronY + 2.0);
        CGContextAddLineToPoint(context, NSMidX(bar) + 5.0, chevronY - 2.0);
    }
    CGContextSetStrokeColorWithColor(context,
                                      [NSColor colorWithRed:0.77 green:0.94 blue:1.0 alpha:indicatorAlpha].CGColor);
    CGContextSetLineWidth(context, 1.45);
    CGContextStrokePath(context);
    CGContextRestoreGState(context);
    CGPathRelease(path);
}

- (BOOL)writePreviewToPath:(NSString *)path error:(NSError **)error {
    [self setLaceOpen:YES animated:NO];
    for (NSInteger frame = 0; frame < 180; frame++) {
        [self advanceSimulation:(1.0 / 60.0)];
    }

    NSInteger scale = 2;
    NSInteger pixelWidth = (NSInteger)round(NSWidth(self.bounds) * scale);
    NSInteger pixelHeight = (NSInteger)round(NSHeight(self.bounds) * scale);
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:NULL
                      pixelsWide:pixelWidth
                      pixelsHigh:pixelHeight
                   bitsPerSample:8
                 samplesPerPixel:4
                        hasAlpha:YES
                        isPlanar:NO
                  colorSpaceName:NSDeviceRGBColorSpace
                    bitmapFormat:0
                     bytesPerRow:pixelWidth * 4
                    bitsPerPixel:32];
    bitmap.size = self.bounds.size;
    NSGraphicsContext *graphics = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
    if (!graphics) {
        if (error) {
            *error = [NSError errorWithDomain:@"LaceDropPreview"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Önizleme grafik bağlamı oluşturulamadı."}];
        }
        return NO;
    }
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:graphics];
    CGContextRef bitmapContext = graphics.CGContext;
    CGContextTranslateCTM(bitmapContext, 0.0, NSHeight(self.bounds));
    CGContextScaleCTM(bitmapContext, 1.0, -1.0);

    NSGradient *background = [[NSGradient alloc]
        initWithStartingColor:[NSColor colorWithRed:0.055 green:0.10 blue:0.22 alpha:1.0]
                  endingColor:[NSColor colorWithRed:0.15 green:0.33 blue:0.68 alpha:1.0]];
    [background drawInRect:self.bounds angle:-28.0];
    [[NSColor colorWithRed:0.35 green:0.25 blue:0.70 alpha:0.22] setFill];
    NSBezierPath *glow = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(NSWidth(self.bounds) * 0.50,
                                                                           NSHeight(self.bounds) * 0.34,
                                                                           470.0, 330.0)];
    [glow fill];
    if (self.laceImage) {
        [self drawTexturedLaceInContext:bitmapContext alpha:1.0];
    } else {
        [self drawLaceInContext:bitmapContext alpha:1.0];
    }
    [self drawBarInContext:bitmapContext];

    [graphics flushGraphics];
    [NSGraphicsContext restoreGraphicsState];
    NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    return [png writeToFile:path options:NSDataWritingAtomic error:error];
}

- (BOOL)writeScenePreviewToPath:(NSString *)path error:(NSError **)error {
    if (!_usesMetalLace || !self.metalView) {
        return [self writePreviewToPath:path error:error];
    }
    NSString *previewAmountText = NSProcessInfo.processInfo.environment[@"LACEDROP_PREVIEW_AMOUNT"];
    if (previewAmountText.length > 0) {
        _openAmount = LaceClamp(previewAmountText.doubleValue, 0.0, 1.0);
        _targetOpenAmount = _openAmount;
        _openVelocity = 0.0;
        [self resetParticlesToCurrentPose];
    } else {
        [self setLaceOpen:YES animated:NO];
    }
    for (NSInteger frame = 0; frame < 180; frame++) {
        [self advanceSimulation:(1.0 / 60.0)];
    }
    [self updateTexturedGeometry];
    return [self.metalView writeSnapshotToPath:path error:error];
}

@end
