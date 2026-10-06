#import <MetalKit/MetalKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface LaceMetalView : MTKView

@property (nonatomic, readonly, getter=isRendererReady) BOOL rendererReady;

- (instancetype)initWithFrame:(NSRect)frame
                    textureURL:(NSURL *)textureURL
                       columns:(NSInteger)columns
                          rows:(NSInteger)rows;
- (void)updateParticlePositions:(const CGPoint *)positions
                          count:(NSInteger)count
                        opacity:(CGFloat)opacity;
- (BOOL)setTextureURL:(NSURL *)textureURL error:(NSError **)error;
- (BOOL)writeSnapshotToPath:(NSString *)path error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
