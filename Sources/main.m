#import <AppKit/AppKit.h>
#import "LaceView.h"

static NSString * const LaceSelectedMotifDefaultsKey = @"LaceDropSelectedMotif";

@interface LacePanel : NSPanel
@end

@implementation LacePanel
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
@end


@interface AppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate>
@property (nonatomic, strong) LacePanel *panel;
@property (nonatomic, strong) LacePanel *blurPanel;
@property (nonatomic, strong) NSVisualEffectView *blurView;
@property (nonatomic, strong) LaceView *laceView;
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) NSMenuItem *toggleMenuItem;
@property (nonatomic, copy) NSArray<NSMenuItem *> *motifMenuItems;
@property (nonatomic) NSInteger screenIndex;
@property (nonatomic, strong) NSTimer *mousePassthroughTimer;
@end

@implementation AppDelegate

- (BOOL)runBlurSelfTest {
    self.screenIndex = 0;
    [self createOverlay];
    [self.laceView setLaceOpen:YES animated:NO];
    BOOL opened = self.blurPanel.isVisible && self.blurView.alphaValue > 0.99;
    [self updateDesktopBlurForProgress:0.5];
    BOOL halfway = self.blurPanel.isVisible && fabs(self.blurView.alphaValue - 0.5) < 0.01;
    [self.laceView setLaceOpen:NO animated:NO];
    BOOL closed = !self.blurPanel.isVisible && self.blurView.alphaValue < 0.001;
    [self.panel orderOut:nil];
    [self.blurPanel orderOut:nil];
    return opened && halfway && closed;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    self.screenIndex = 0;
    [self createOverlay];
    [self createStatusItem];
    __weak typeof(self) weakSelf = self;
    self.mousePassthroughTimer = [NSTimer scheduledTimerWithTimeInterval:(1.0 / 60.0)
                                                                 repeats:YES
                                                                   block:^(NSTimer *unusedTimer) {
        (void)unusedTimer;
        [weakSelf updateMousePassthrough];
    }];
    [[NSRunLoop mainRunLoop] addTimer:self.mousePassthroughTimer forMode:NSRunLoopCommonModes];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(screenConfigurationChanged:)
                                                 name:NSApplicationDidChangeScreenParametersNotification
                                               object:nil];
}

- (void)createOverlay {
    NSScreen *screen = NSScreen.screens.count > 0 ? NSScreen.screens[self.screenIndex] : NSScreen.mainScreen;
    [self createBlurOverlayForScreen:screen];
    CGFloat width = MIN(1120.0, NSWidth(screen.frame) * 0.78);
    CGFloat height = MIN(520.0, NSHeight(screen.frame) * 0.56);
    NSRect frame = NSMakeRect(NSMidX(screen.frame) - width * 0.5,
                              NSMaxY(screen.frame) - height,
                              width,
                              height);

    self.panel = [[LacePanel alloc] initWithContentRect:frame
                                              styleMask:(NSWindowStyleMaskBorderless |
                                                         NSWindowStyleMaskNonactivatingPanel)
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    self.panel.opaque = NO;
    self.panel.backgroundColor = NSColor.clearColor;
    self.panel.hasShadow = NO;
    self.panel.level = NSStatusWindowLevel + 1;
    self.panel.collectionBehavior = (NSWindowCollectionBehaviorCanJoinAllSpaces |
                                     NSWindowCollectionBehaviorFullScreenAuxiliary |
                                     NSWindowCollectionBehaviorStationary);
    self.panel.movable = NO;
    self.panel.hidesOnDeactivate = NO;
    self.panel.ignoresMouseEvents = YES;

    self.laceView = [[LaceView alloc] initWithFrame:NSMakeRect(0.0, 0.0, width, height)
                                    startAnimation:YES];
    __weak typeof(self) weakSelf = self;
    self.laceView.openStateDidChange = ^(BOOL isOpen) {
        weakSelf.toggleMenuItem.title = isOpen ? @"Danteli Kapat" : @"Danteli Aç";
    };
    self.laceView.openProgressDidChange = ^(CGFloat progress) {
        [weakSelf updateDesktopBlurForProgress:progress];
    };
    NSString *savedMotif = [[NSUserDefaults standardUserDefaults]
        stringForKey:LaceSelectedMotifDefaultsKey];
    if (![self.laceView setMotifNamed:savedMotif ?: LaceMotifFlower]) {
        [self.laceView setMotifNamed:LaceMotifFlower];
    }
    self.panel.contentView = self.laceView;
    [self.panel orderFrontRegardless];
}

- (void)createBlurOverlayForScreen:(NSScreen *)screen {
    self.blurPanel = [[LacePanel alloc] initWithContentRect:screen.frame
                                                  styleMask:(NSWindowStyleMaskBorderless |
                                                             NSWindowStyleMaskNonactivatingPanel)
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
    self.blurPanel.opaque = NO;
    self.blurPanel.backgroundColor = NSColor.clearColor;
    self.blurPanel.hasShadow = NO;
    self.blurPanel.level = NSStatusWindowLevel;
    self.blurPanel.collectionBehavior = (NSWindowCollectionBehaviorCanJoinAllSpaces |
                                         NSWindowCollectionBehaviorFullScreenAuxiliary |
                                         NSWindowCollectionBehaviorStationary |
                                         NSWindowCollectionBehaviorIgnoresCycle);
    self.blurPanel.movable = NO;
    self.blurPanel.hidesOnDeactivate = NO;
    self.blurPanel.ignoresMouseEvents = YES;
    self.blurPanel.animationBehavior = NSWindowAnimationBehaviorNone;

    self.blurView = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0.0, 0.0,
                                                                        NSWidth(screen.frame),
                                                                        NSHeight(screen.frame))];
    self.blurView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.blurView.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    self.blurView.material = NSVisualEffectMaterialUnderWindowBackground;
    self.blurView.state = NSVisualEffectStateActive;
    self.blurView.emphasized = NO;
    self.blurView.alphaValue = 0.0;
    self.blurPanel.contentView = self.blurView;
    [self.blurPanel orderOut:nil];
}

- (void)updateDesktopBlurForProgress:(CGFloat)progress {
    if (!self.blurPanel || !self.blurView) return;
    progress = MAX(0.0, MIN(1.0, progress));
    CGFloat eased = progress * progress * (3.0 - 2.0 * progress);
    if (eased > 0.001 && !self.blurPanel.isVisible) {
        [self.blurPanel orderFrontRegardless];
        [self.panel orderFrontRegardless];
    }
    self.blurView.alphaValue = eased;
    if (eased <= 0.001 && self.blurPanel.isVisible) {
        [self.blurPanel orderOut:nil];
    }
}

- (void)updateMousePassthrough {
    if (!self.panel || !self.laceView) return;
    NSRect barInWindow = [self.laceView interactionRectInWindow];
    NSRect barOnScreen = [self.panel convertRectToScreen:barInWindow];
    BOOL hovering = NSPointInRect(NSEvent.mouseLocation, barOnScreen);
    NSPoint windowPoint = [self.panel convertPointFromScreen:NSEvent.mouseLocation];
    BOOL shouldCapture = [self.laceView shouldCaptureMouseAtWindowPoint:windowPoint];
    self.panel.ignoresMouseEvents = !shouldCapture;
    [self.laceView setBarHoveredFromPolling:hovering];
}

- (void)createStatusItem {
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    self.statusItem.button.title = @"⌁";
    self.statusItem.button.toolTip = @"LaceDrop";

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"LaceDrop"];
    menu.delegate = self;
    self.toggleMenuItem = [[NSMenuItem alloc] initWithTitle:(self.laceView.isOpen ? @"Danteli Kapat" : @"Danteli Aç")
                                                    action:@selector(toggleLace:)
                                             keyEquivalent:@""];
    self.toggleMenuItem.target = self;
    [menu addItem:self.toggleMenuItem];

    NSMenuItem *motifParent = [[NSMenuItem alloc] initWithTitle:@"Motif Seç"
                                                        action:nil
                                                 keyEquivalent:@""];
    NSMenu *motifMenu = [[NSMenu alloc] initWithTitle:@"Motif Seç"];
    NSArray<NSArray<NSString *> *> *motifs = @[
        @[@"Klasik Çiçek", LaceMotifFlower],
        @[@"Osmanlı Lalesi", LaceMotifTulip],
        @[@"Sarmaşık ve Yaprak", LaceMotifVine],
        @[@"Geometrik Baklava", LaceMotifGeometric],
    ];
    NSMutableArray<NSMenuItem *> *motifItems = [NSMutableArray array];
    for (NSArray<NSString *> *motif in motifs) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:motif[0]
                                                     action:@selector(selectMotif:)
                                              keyEquivalent:@""];
        item.target = self;
        item.representedObject = motif[1];
        [motifMenu addItem:item];
        [motifItems addObject:item];
    }
    self.motifMenuItems = motifItems;
    motifParent.submenu = motifMenu;
    [menu addItem:motifParent];
    [self updateMotifMenuChecks];

    NSMenuItem *nextScreen = [[NSMenuItem alloc] initWithTitle:@"Sonraki Ekrana Taşı"
                                                       action:@selector(moveToNextScreen:)
                                                keyEquivalent:@""];
    nextScreen.target = self;
    [menu addItem:nextScreen];
    [menu addItem:NSMenuItem.separatorItem];

    NSMenuItem *about = [[NSMenuItem alloc] initWithTitle:@"LaceDrop Hakkında"
                                                   action:@selector(showAbout:)
                                            keyEquivalent:@""];
    about.target = self;
    [menu addItem:about];

    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"LaceDrop’tan Çık"
                                                  action:@selector(terminate:)
                                           keyEquivalent:@"q"];
    quit.target = NSApp;
    [menu addItem:quit];
    self.statusItem.menu = menu;
}

- (void)toggleLace:(id)sender {
    [self.laceView toggleLace];
}

- (void)selectMotif:(NSMenuItem *)sender {
    NSString *motifName = sender.representedObject;
    if (![motifName isKindOfClass:NSString.class]) return;
    if ([self.laceView setMotifNamed:motifName]) {
        [[NSUserDefaults standardUserDefaults] setObject:motifName
                                                 forKey:LaceSelectedMotifDefaultsKey];
        [self updateMotifMenuChecks];
    }
}

- (void)updateMotifMenuChecks {
    for (NSMenuItem *item in self.motifMenuItems) {
        item.state = [item.representedObject isEqualToString:self.laceView.motifName]
            ? NSControlStateValueOn : NSControlStateValueOff;
    }
}

- (void)moveToNextScreen:(id)sender {
    NSArray<NSScreen *> *screens = NSScreen.screens;
    if (screens.count == 0) return;
    self.screenIndex = (self.screenIndex + 1) % screens.count;
    NSScreen *screen = screens[self.screenIndex];
    CGFloat width = MIN(1120.0, NSWidth(screen.frame) * 0.78);
    CGFloat height = MIN(520.0, NSHeight(screen.frame) * 0.56);
    NSRect frame = NSMakeRect(NSMidX(screen.frame) - width * 0.5,
                              NSMaxY(screen.frame) - height,
                              width,
                              height);
    [self.blurPanel setFrame:screen.frame display:YES];
    [self.panel setFrame:frame display:YES animate:YES];
    self.laceView.frame = NSMakeRect(0.0, 0.0, width, height);
}

- (void)screenConfigurationChanged:(NSNotification *)notification {
    if (self.screenIndex >= (NSInteger)NSScreen.screens.count) self.screenIndex = 0;
    [self moveToCurrentScreenWithoutCycling];
}

- (void)moveToCurrentScreenWithoutCycling {
    NSArray<NSScreen *> *screens = NSScreen.screens;
    if (screens.count == 0) return;
    NSScreen *screen = screens[self.screenIndex];
    CGFloat width = MIN(1120.0, NSWidth(screen.frame) * 0.78);
    CGFloat height = MIN(520.0, NSHeight(screen.frame) * 0.56);
    [self.blurPanel setFrame:screen.frame display:YES];
    [self.panel setFrame:NSMakeRect(NSMidX(screen.frame) - width * 0.5,
                                    NSMaxY(screen.frame) - height,
                                    width,
                                    height)
                   display:YES];
    self.laceView.frame = NSMakeRect(0.0, 0.0, width, height);
}

- (void)showAbout:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"LaceDrop";
    alert.informativeText = @"Masaüstünüzün üst kenarından sarkan, gerçek zamanlı kumaş fiziği ve açılma oranına duyarlı arka plan bulanıklığıyla hareket eden dijital dantel.";
    [alert addButtonWithTitle:@"Tamam"];
    [alert runModal];
}

@end


int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc == 2 && strcmp(argv[1], "--test-blur") == 0) {
            [NSApplication sharedApplication];
            AppDelegate *delegate = [[AppDelegate alloc] init];
            BOOL success = [delegate runBlurSelfTest];
            printf("desktop blur progression: %s\n", success ? "passed" : "failed");
            return success ? 0 : 1;
        }
        if (argc == 2 && strcmp(argv[1], "--test-motifs") == 0) {
            [NSApplication sharedApplication];
            LaceView *view = [[LaceView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 1120.0, 520.0)
                                                startAnimation:NO];
            NSArray<NSString *> *motifs = @[
                LaceMotifFlower, LaceMotifTulip, LaceMotifVine, LaceMotifGeometric
            ];
            BOOL success = YES;
            for (NSString *motif in motifs) {
                success = [view setMotifNamed:motif] &&
                          [view.motifName isEqualToString:motif] && success;
            }
            printf("motif switching: %s\n", success ? "passed" : "failed");
            return success ? 0 : 1;
        }
        if (argc == 4 && strcmp(argv[1], "--render-motif-preview") == 0) {
            [NSApplication sharedApplication];
            LaceView *view = [[LaceView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 1120.0, 520.0)
                                                startAnimation:NO];
            NSError *error = nil;
            BOOL selected = [view setMotifNamed:[NSString stringWithUTF8String:argv[2]]];
            BOOL success = selected &&
                [view writeScenePreviewToPath:[NSString stringWithUTF8String:argv[3]] error:&error];
            if (!success) {
                const char *message = error ? error.localizedDescription.UTF8String : "Bilinmeyen motif.";
                fprintf(stderr, "%s\n", message);
                return 1;
            }
            return 0;
        }
        if (argc == 3 && (strcmp(argv[1], "--render-preview") == 0 ||
                          strcmp(argv[1], "--render-scene-preview") == 0)) {
            [NSApplication sharedApplication];
            LaceView *view = [[LaceView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 1120.0, 520.0)
                                                startAnimation:NO];
            NSError *error = nil;
            BOOL scenePreview = strcmp(argv[1], "--render-scene-preview") == 0;
            BOOL success = scenePreview
                ? [view writeScenePreviewToPath:[NSString stringWithUTF8String:argv[2]] error:&error]
                : [view writePreviewToPath:[NSString stringWithUTF8String:argv[2]] error:&error];
            if (!success) {
                fprintf(stderr, "%s\n", error.localizedDescription.UTF8String);
                return 1;
            }
            return 0;
        }

        NSApplication *application = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
