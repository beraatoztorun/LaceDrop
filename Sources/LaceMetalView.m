#import "LaceMetalView.h"
#import <QuartzCore/QuartzCore.h>
#import <simd/simd.h>

typedef struct {
    vector_float2 position;
    vector_float2 textureCoordinate;
    float deformationLight;
    float padding;
} LaceMetalVertex;

typedef struct {
    vector_float2 viewportSize;
    float opacity;
    float padding;
} LaceMetalUniforms;

@interface LaceMetalView () <MTKViewDelegate>
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) id<MTLRenderPipelineState> pipelineState;
@property (nonatomic, strong) id<MTLBuffer> vertexBuffer;
@property (nonatomic, strong) id<MTLBuffer> indexBuffer;
@property (nonatomic, strong) id<MTLTexture> laceTexture;
@property (nonatomic, strong) id<MTLSamplerState> samplerState;
@end

@implementation LaceMetalView {
    NSInteger _columns;
    NSInteger _rows;
    NSInteger _vertexCount;
    NSUInteger _indexCount;
    CGFloat _opacity;
    BOOL _rendererReady;
}

- (BOOL)setTextureURL:(NSURL *)textureURL error:(NSError **)error {
    if (!self.device || !textureURL) {
        if (error) {
            *error = [NSError errorWithDomain:@"LaceDropMetal"
                                         code:4
                                     userInfo:@{NSLocalizedDescriptionKey: @"Dantel dokusu bulunamadı."}];
        }
        return NO;
    }

    MTKTextureLoader *textureLoader = [[MTKTextureLoader alloc] initWithDevice:self.device];
    id<MTLTexture> texture = [textureLoader newTextureWithContentsOfURL:textureURL
                                                                options:@{
        MTKTextureLoaderOptionSRGB: @NO,
        MTKTextureLoaderOptionOrigin: MTKTextureLoaderOriginTopLeft,
    }
                                                                  error:error];
    if (!texture) return NO;

    self.laceTexture = texture;
    if (self.vertexBuffer) {
        LaceMetalVertex *vertices = self.vertexBuffer.contents;
        float topCrop = MIN(0.12f, 74.0f / MAX(1.0f, (float)texture.height));
        for (NSInteger row = 0; row < _rows; row++) {
            for (NSInteger column = 0; column < _columns; column++) {
                NSInteger index = row * _columns + column;
                float u = (float)column / (float)(_columns - 1);
                float rowAmount = (float)row / (float)(_rows - 1);
                vertices[index].textureCoordinate =
                    (vector_float2){u, topCrop + rowAmount * (1.0f - topCrop)};
            }
        }
    }
    [self setNeedsDisplay:YES];
    return YES;
}

- (instancetype)initWithFrame:(NSRect)frame
                    textureURL:(NSURL *)textureURL
                       columns:(NSInteger)columns
                          rows:(NSInteger)rows {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    self = [super initWithFrame:frame device:device];
    if (!self) return nil;

    _columns = MAX(2, columns);
    _rows = MAX(2, rows);
    _vertexCount = _columns * _rows;
    _opacity = 0.0;

    self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    self.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);
    self.framebufferOnly = YES;
    self.paused = YES;
    self.enableSetNeedsDisplay = YES;
    self.preferredFramesPerSecond = 60;
    self.delegate = self;
    self.wantsLayer = YES;
    self.layer.opaque = NO;
    self.layer.backgroundColor = NSColor.clearColor.CGColor;

    if (!device || ![self buildRendererWithTextureURL:textureURL]) {
        return self;
    }
    _rendererReady = YES;
    return self;
}

- (BOOL)isOpaque {
    return NO;
}

- (nullable NSView *)hitTest:(NSPoint)point {
    (void)point;
    return nil;
}

- (BOOL)isRendererReady {
    return _rendererReady;
}

- (BOOL)buildRendererWithTextureURL:(NSURL *)textureURL {
    static NSString *const shaderSource =
        @"#include <metal_stdlib>\n"
         "using namespace metal;\n"
         "struct VertexIn { float2 position; float2 uv; float deformationLight; float padding; };\n"
         "struct Uniforms { float2 viewport; float opacity; float padding; };\n"
         "struct VertexOut { float4 position [[position]]; float2 uv; float deformationLight; };\n"
         "vertex VertexOut lace_vertex(const device VertexIn *vertices [[buffer(0)]],\n"
         "                            constant Uniforms &uniforms [[buffer(1)]],\n"
         "                            uint vertexID [[vertex_id]]) {\n"
         "    VertexOut out;\n"
         "    float2 point = vertices[vertexID].position;\n"
         "    float2 clip = float2((point.x / uniforms.viewport.x) * 2.0 - 1.0,\n"
         "                         1.0 - (point.y / uniforms.viewport.y) * 2.0);\n"
         "    out.position = float4(clip, 0.0, 1.0);\n"
         "    out.uv = vertices[vertexID].uv;\n"
         "    out.deformationLight = vertices[vertexID].deformationLight;\n"
         "    return out;\n"
         "}\n"
         "fragment float4 lace_fragment(VertexOut in [[stage_in]],\n"
         "                              texture2d<float> texture [[texture(0)]],\n"
         "                              sampler textureSampler [[sampler(0)]],\n"
         "                              constant Uniforms &uniforms [[buffer(1)]]) {\n"
         "    float2 textureSize = float2(float(texture.get_width()), float(texture.get_height()));\n"
         "    float2 texel = 1.0 / max(textureSize, float2(1.0));\n"
         "    float4 color = texture.sample(textureSampler, in.uv);\n"
         "\n"
         "    // Reconstruct a tiny rounded-thread normal from the alpha edge.\n"
         "    float alphaLeft = texture.sample(textureSampler, in.uv - float2(texel.x, 0.0)).a;\n"
         "    float alphaRight = texture.sample(textureSampler, in.uv + float2(texel.x, 0.0)).a;\n"
         "    float alphaUp = texture.sample(textureSampler, in.uv - float2(0.0, texel.y)).a;\n"
         "    float alphaDown = texture.sample(textureSampler, in.uv + float2(0.0, texel.y)).a;\n"
         "    float3 threadNormal = normalize(float3((alphaLeft - alphaRight) * 2.8,\n"
         "                                         (alphaUp - alphaDown) * 2.8, 1.0));\n"
         "    float reliefLight = 0.90 + 0.16 * saturate(dot(threadNormal,\n"
         "        normalize(float3(-0.45, -0.72, 0.82))));\n"
         "\n"
         "    // Keep the fibers naturally ivory and suppress tiny color artifacts.\n"
         "    float luminance = dot(color.rgb, float3(0.299, 0.587, 0.114));\n"
         "    float3 warmFiber = float3(luminance * 1.025, luminance * 0.995, luminance * 0.935);\n"
         "    float3 fiberColor = mix(color.rgb, warmFiber, 0.48) * reliefLight\n"
         "        * clamp(in.deformationLight, 0.82, 1.16);\n"
         "    float laceAlpha = color.a * uniforms.opacity;\n"
         "\n"
         "    // A soft two-pixel contact shadow makes the mesh sit above the desktop.\n"
         "    float2 shadowCenter = in.uv - float2(1.8 * texel.x, 3.8 * texel.y);\n"
         "    float shadow = 0.0;\n"
         "    shadow += texture.sample(textureSampler, shadowCenter).a * 0.20;\n"
         "    shadow += texture.sample(textureSampler, shadowCenter + float2( 2.2 * texel.x, 0.0)).a * 0.12;\n"
         "    shadow += texture.sample(textureSampler, shadowCenter + float2(-2.2 * texel.x, 0.0)).a * 0.12;\n"
         "    shadow += texture.sample(textureSampler, shadowCenter + float2(0.0,  2.2 * texel.y)).a * 0.12;\n"
         "    shadow += texture.sample(textureSampler, shadowCenter + float2(0.0, -2.2 * texel.y)).a * 0.12;\n"
         "    shadow += texture.sample(textureSampler, shadowCenter + float2( 1.7 * texel.x,  1.7 * texel.y)).a * 0.08;\n"
         "    shadow += texture.sample(textureSampler, shadowCenter + float2(-1.7 * texel.x,  1.7 * texel.y)).a * 0.08;\n"
         "    shadow += texture.sample(textureSampler, shadowCenter + float2( 1.7 * texel.x, -1.7 * texel.y)).a * 0.08;\n"
         "    shadow += texture.sample(textureSampler, shadowCenter + float2(-1.7 * texel.x, -1.7 * texel.y)).a * 0.08;\n"
         "    float shadowAlpha = shadow * 0.30 * uniforms.opacity * (1.0 - laceAlpha);\n"
         "    float outputAlpha = laceAlpha + shadowAlpha * (1.0 - laceAlpha);\n"
         "    float3 shadowColor = float3(0.035, 0.028, 0.022);\n"
         "    float3 premultiplied = fiberColor * laceAlpha\n"
         "        + shadowColor * shadowAlpha * (1.0 - laceAlpha);\n"
         "    float3 outputColor = outputAlpha > 0.0001 ? premultiplied / outputAlpha : float3(0.0);\n"
         "    return float4(outputColor, outputAlpha);\n"
         "}\n";

    NSError *error = nil;
    id<MTLLibrary> library = [self.device newLibraryWithSource:shaderSource options:nil error:&error];
    if (!library) {
        NSLog(@"LaceDrop Metal shader error: %@", error.localizedDescription);
        return NO;
    }

    MTLRenderPipelineDescriptor *descriptor = [[MTLRenderPipelineDescriptor alloc] init];
    descriptor.vertexFunction = [library newFunctionWithName:@"lace_vertex"];
    descriptor.fragmentFunction = [library newFunctionWithName:@"lace_fragment"];
    descriptor.colorAttachments[0].pixelFormat = self.colorPixelFormat;
    descriptor.colorAttachments[0].blendingEnabled = YES;
    descriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    descriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    descriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    descriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
    descriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    descriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

    self.pipelineState = [self.device newRenderPipelineStateWithDescriptor:descriptor error:&error];
    if (!self.pipelineState) {
        NSLog(@"LaceDrop Metal pipeline error: %@", error.localizedDescription);
        return NO;
    }

    if (![self setTextureURL:textureURL error:&error]) {
        NSLog(@"LaceDrop texture error: %@", error.localizedDescription);
        return NO;
    }

    self.commandQueue = [self.device newCommandQueue];
    self.vertexBuffer = [self.device newBufferWithLength:sizeof(LaceMetalVertex) * _vertexCount
                                                 options:MTLResourceStorageModeShared];

    _indexCount = (NSUInteger)(_columns - 1) * (NSUInteger)(_rows - 1) * 6;
    self.indexBuffer = [self.device newBufferWithLength:sizeof(uint16_t) * _indexCount
                                                options:MTLResourceStorageModeShared];
    uint16_t *indices = self.indexBuffer.contents;
    NSUInteger cursor = 0;
    for (NSInteger row = 0; row < _rows - 1; row++) {
        for (NSInteger column = 0; column < _columns - 1; column++) {
            uint16_t topLeft = (uint16_t)(row * _columns + column);
            uint16_t topRight = (uint16_t)(topLeft + 1);
            uint16_t bottomLeft = (uint16_t)(topLeft + _columns);
            uint16_t bottomRight = (uint16_t)(bottomLeft + 1);
            indices[cursor++] = topLeft;
            indices[cursor++] = bottomLeft;
            indices[cursor++] = topRight;
            indices[cursor++] = topRight;
            indices[cursor++] = bottomLeft;
            indices[cursor++] = bottomRight;
        }
    }

    LaceMetalVertex *vertices = self.vertexBuffer.contents;
    float topCrop = MIN(0.12f, 74.0f / MAX(1.0f, (float)self.laceTexture.height));
    for (NSInteger row = 0; row < _rows; row++) {
        for (NSInteger column = 0; column < _columns; column++) {
            NSInteger index = row * _columns + column;
            float u = (float)column / (float)(_columns - 1);
            float rowAmount = (float)row / (float)(_rows - 1);
            float v = topCrop + rowAmount * (1.0f - topCrop);
            vertices[index].position = (vector_float2){0.0f, 0.0f};
            vertices[index].textureCoordinate = (vector_float2){u, v};
            vertices[index].deformationLight = 1.0f;
            vertices[index].padding = 0.0f;
        }
    }

    MTLSamplerDescriptor *samplerDescriptor = [[MTLSamplerDescriptor alloc] init];
    samplerDescriptor.minFilter = MTLSamplerMinMagFilterLinear;
    samplerDescriptor.magFilter = MTLSamplerMinMagFilterLinear;
    samplerDescriptor.mipFilter = MTLSamplerMipFilterNotMipmapped;
    samplerDescriptor.sAddressMode = MTLSamplerAddressModeClampToEdge;
    samplerDescriptor.tAddressMode = MTLSamplerAddressModeClampToEdge;
    self.samplerState = [self.device newSamplerStateWithDescriptor:samplerDescriptor];
    return self.commandQueue && self.vertexBuffer && self.indexBuffer && self.samplerState;
}

- (void)updateParticlePositions:(const CGPoint *)positions
                          count:(NSInteger)count
                        opacity:(CGFloat)opacity {
    if (!_rendererReady || !positions || count != _vertexCount) return;
    LaceMetalVertex *vertices = self.vertexBuffer.contents;
    for (NSInteger index = 0; index < count; index++) {
        vertices[index].position = (vector_float2){(float)positions[index].x,
                                                   (float)positions[index].y};
    }
    for (NSInteger row = 0; row < _rows; row++) {
        for (NSInteger column = 0; column < _columns; column++) {
            NSInteger index = row * _columns + column;
            NSInteger leftIndex = row * _columns + MAX(0, column - 1);
            NSInteger rightIndex = row * _columns + MIN(_columns - 1, column + 1);
            NSInteger upIndex = MAX(0, row - 1) * _columns + column;
            NSInteger downIndex = MIN(_rows - 1, row + 1) * _columns + column;
            CGPoint left = positions[leftIndex];
            CGPoint right = positions[rightIndex];
            CGPoint up = positions[upIndex];
            CGPoint down = positions[downIndex];
            CGFloat horizontalSpan = MAX(12.0, fabs(right.x - left.x));
            CGFloat verticalSpan = MAX(12.0, fabs(down.y - up.y));
            CGFloat horizontalSlope = (right.y - left.y) / horizontalSpan;
            CGFloat verticalShear = (down.x - up.x) / verticalSpan;
            CGFloat light = 1.0 - horizontalSlope * 0.15 + verticalShear * 0.07;
            vertices[index].deformationLight = (float)MAX(0.82, MIN(1.16, light));
        }
    }
    _opacity = opacity;
    [self setNeedsDisplay:YES];
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    (void)view;
    (void)size;
}

- (void)drawInMTKView:(MTKView *)view {
    if (!_rendererReady || !view.currentDrawable || !view.currentRenderPassDescriptor) return;
    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    id<MTLRenderCommandEncoder> encoder =
        [commandBuffer renderCommandEncoderWithDescriptor:view.currentRenderPassDescriptor];
    if (!encoder) return;

    [encoder setRenderPipelineState:self.pipelineState];
    [encoder setCullMode:MTLCullModeNone];
    [encoder setVertexBuffer:self.vertexBuffer offset:0 atIndex:0];
    LaceMetalUniforms uniforms = {
        .viewportSize = {(float)MAX(1.0, NSWidth(self.bounds)),
                         (float)MAX(1.0, NSHeight(self.bounds))},
        .opacity = (float)_opacity,
        .padding = 0.0f,
    };
    [encoder setVertexBytes:&uniforms length:sizeof(uniforms) atIndex:1];
    [encoder setFragmentBytes:&uniforms length:sizeof(uniforms) atIndex:1];
    [encoder setFragmentTexture:self.laceTexture atIndex:0];
    [encoder setFragmentSamplerState:self.samplerState atIndex:0];
    if (_opacity > 0.001) {
        [encoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                            indexCount:_indexCount
                             indexType:MTLIndexTypeUInt16
                           indexBuffer:self.indexBuffer
                     indexBufferOffset:0];
    }
    [encoder endEncoding];
    [commandBuffer presentDrawable:view.currentDrawable];
    [commandBuffer commit];
}

- (BOOL)writeSnapshotToPath:(NSString *)path error:(NSError **)error {
    if (!_rendererReady) {
        if (error) {
            *error = [NSError errorWithDomain:@"LaceDropMetal"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Metal renderer hazır değil."}];
        }
        return NO;
    }

    NSUInteger width = (NSUInteger)MAX(1.0, round(NSWidth(self.bounds)));
    NSUInteger height = (NSUInteger)MAX(1.0, round(NSHeight(self.bounds)));
    MTLTextureDescriptor *textureDescriptor =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:self.colorPixelFormat
                                                           width:width
                                                          height:height
                                                       mipmapped:NO];
    textureDescriptor.storageMode = MTLStorageModeShared;
    textureDescriptor.usage = MTLTextureUsageRenderTarget;
    id<MTLTexture> target = [self.device newTextureWithDescriptor:textureDescriptor];
    if (!target) {
        if (error) {
            *error = [NSError errorWithDomain:@"LaceDropMetal"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Metal test dokusu oluşturulamadı."}];
        }
        return NO;
    }

    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = target;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);

    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:pass];
    [encoder setRenderPipelineState:self.pipelineState];
    [encoder setCullMode:MTLCullModeNone];
    [encoder setVertexBuffer:self.vertexBuffer offset:0 atIndex:0];
    LaceMetalUniforms uniforms = {
        .viewportSize = {(float)width, (float)height},
        .opacity = (float)_opacity,
        .padding = 0.0f,
    };
    [encoder setVertexBytes:&uniforms length:sizeof(uniforms) atIndex:1];
    [encoder setFragmentBytes:&uniforms length:sizeof(uniforms) atIndex:1];
    [encoder setFragmentTexture:self.laceTexture atIndex:0];
    [encoder setFragmentSamplerState:self.samplerState atIndex:0];
    [encoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                        indexCount:_indexCount
                         indexType:MTLIndexTypeUInt16
                       indexBuffer:self.indexBuffer
                 indexBufferOffset:0];
    [encoder endEncoding];
    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];
    if (commandBuffer.status == MTLCommandBufferStatusError) {
        if (error) *error = commandBuffer.error;
        return NO;
    }

    NSUInteger bytesPerRow = width * 4;
    NSMutableData *pixelData = [NSMutableData dataWithLength:bytesPerRow * height];
    [target getBytes:pixelData.mutableBytes
         bytesPerRow:bytesPerRow
          fromRegion:MTLRegionMake2D(0, 0, width, height)
         mipmapLevel:0];
    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)pixelData);
    CGBitmapInfo bitmapInfo = kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst;
    CGImageRef image = CGImageCreate(width, height, 8, 32, bytesPerRow, colorSpace,
                                     bitmapInfo, provider, NULL, YES,
                                     kCGRenderingIntentDefault);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(colorSpace);
    if (!image) return NO;
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithCGImage:image];
    CGImageRelease(image);
    NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    return [png writeToFile:path options:NSDataWritingAtomic error:error];
}

@end
