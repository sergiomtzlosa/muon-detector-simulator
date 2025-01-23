#import "MDSMainWindowController.h"

#import "MDSMainViewController.h"

@implementation MDSMainWindowController

- (instancetype)init {
    static const CGFloat preferredWidth = 1480.0;
    static const CGFloat preferredHeight = 900.0;
    static const CGFloat minimumWidth = 1200.0;
    static const CGFloat minimumHeight = 760.0;

    NSScreen *screen = [NSScreen mainScreen];
    const NSSize visibleSize = screen.visibleFrame.size;
    const CGFloat contentWidth =
        MAX(minimumWidth, MIN(preferredWidth, visibleSize.width - 64.0));
    const CGFloat contentHeight =
        MAX(minimumHeight, MIN(preferredHeight, visibleSize.height - 64.0));

    MDSMainViewController *mainViewController = [[MDSMainViewController alloc] init];
    mainViewController.view.frame =
        NSMakeRect(0, 0, contentWidth, contentHeight);
    NSWindow *window =
        [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0,
                                                         contentWidth,
                                                         contentHeight)
                                    styleMask:(NSWindowStyleMaskTitled |
                                               NSWindowStyleMaskClosable |
                                               NSWindowStyleMaskMiniaturizable |
                                               NSWindowStyleMaskResizable)
                                      backing:NSBackingStoreBuffered
                                        defer:NO];
    window.title = @"Muon Detector Simulator";
    window.subtitle = @"Simulation only — no radiation is measured";
    window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    window.backgroundColor = [NSColor whiteColor];
    window.contentMinSize = NSMakeSize(minimumWidth, minimumHeight);

    // Host the interface in a container pinned to the window's content layout
    // guide. Without that explicit relationship, AppKit can shrink a new window
    // to the fitting width of the Auto Layout tree during its first visible
    // layout pass. The main view remains constrained inside this container and
    // resizes with the window.
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0,
                                                                  contentWidth,
                                                                  contentHeight)];
    container.wantsLayer = YES;
    container.layer.backgroundColor = [NSColor whiteColor].CGColor;
    mainViewController.view.frame = container.bounds;
    mainViewController.view.autoresizingMask =
        NSViewWidthSizable | NSViewHeightSizable;
    [container addSubview:mainViewController.view];
    window.contentView = container;
    [window setContentSize:NSMakeSize(contentWidth, contentHeight)];

    NSLayoutGuide *contentGuide = (NSLayoutGuide *)window.contentLayoutGuide;
    container.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [container.leadingAnchor constraintEqualToAnchor:contentGuide.leadingAnchor],
        [container.trailingAnchor constraintEqualToAnchor:contentGuide.trailingAnchor],
        [container.topAnchor constraintEqualToAnchor:contentGuide.topAnchor],
        [container.bottomAnchor constraintEqualToAnchor:contentGuide.bottomAnchor],
    ]];
    window.releasedWhenClosed = NO;
    window.tabbingMode = NSWindowTabbingModeDisallowed;

    self = [super initWithWindow:window];
    if (self) {
        _mainViewController = mainViewController;
        [window center];
    }
    return self;
}

@end


