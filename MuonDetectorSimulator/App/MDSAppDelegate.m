#import "MDSAppDelegate.h"

#import "MDSConfigurationViewController.h"
#import "MDSDetectorConfiguration.h"
#import "MDSMainViewController.h"
#import "MDSMainWindowController.h"

#if DEBUG
@interface MDSAppDelegate ()
@property (nonatomic, copy, nullable) NSString *debugSnapshotPath;
@property (nonatomic, copy, nullable) NSString *debugInspectorSnapshotPath;
@property (nonatomic, copy, nullable) NSString *debugHelpSnapshotPath;
@property (nonatomic, copy, nullable) NSString *debugAboutSnapshotPath;
@property (nonatomic, assign) BOOL debugAutoStart;
@property (nonatomic, assign) BOOL debugExitAfterSnapshot;
@property (nonatomic, strong, nullable) NSTimer *debugOpenTimer;
@property (nonatomic, strong, nullable) NSTimer *debugCaptureTimer;
- (void)runDebugHarnessIfRequested;
- (void)debugOpenTimerFired:(NSTimer *)timer;
- (void)debugCaptureTimerFired:(NSTimer *)timer;
@end
#endif

@implementation MDSAppDelegate

- (void)applicationWillFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    [self installMainMenu];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    _mainWindowController = [[MDSMainWindowController alloc] init];
    [self.mainWindowController showWindow:nil];
    [self.mainWindowController.window makeKeyAndOrderFront:nil];

    if (@available(macOS 14.0, *)) {
        [NSApp activate];
    } else {
        [NSApp activateIgnoringOtherApps:YES];
    }

#if DEBUG
    [self runDebugHarnessIfRequested];
#endif
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (BOOL)applicationShouldSaveApplicationState:(NSApplication *)sender {
    return NO;
}

- (BOOL)applicationShouldRestoreApplicationState:(NSApplication *)sender {
    return NO;
}

#pragma mark - Main menu

- (void)installMainMenu {
    NSString *applicationName = [[NSProcessInfo processInfo] processName];
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"Main Menu"];

    NSMenu *applicationMenu = [[NSMenu alloc] initWithTitle:applicationName];
    NSMenuItem *aboutItem =
        [[NSMenuItem alloc] initWithTitle:
            [NSString stringWithFormat:@"About %@", applicationName]
                                   action:@selector(showAboutPanel:)
                            keyEquivalent:@""];
    aboutItem.target = self;
    [applicationMenu addItem:aboutItem];
    [applicationMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *servicesItem =
        [[NSMenuItem alloc] initWithTitle:@"Services" action:nil keyEquivalent:@""];
    NSMenu *servicesMenu = [[NSMenu alloc] initWithTitle:@"Services"];
    NSApp.servicesMenu = servicesMenu;
    servicesItem.submenu = servicesMenu;
    [applicationMenu addItem:servicesItem];
    [applicationMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *hideItem =
        [[NSMenuItem alloc] initWithTitle:
            [NSString stringWithFormat:@"Hide %@", applicationName]
                                   action:@selector(hide:)
                            keyEquivalent:@"h"];
    hideItem.target = NSApp;
    [applicationMenu addItem:hideItem];

    NSMenuItem *hideOthersItem =
        [[NSMenuItem alloc] initWithTitle:@"Hide Others"
                                   action:@selector(hideOtherApplications:)
                            keyEquivalent:@"h"];
    hideOthersItem.keyEquivalentModifierMask =
        NSEventModifierFlagCommand | NSEventModifierFlagOption;
    hideOthersItem.target = NSApp;
    [applicationMenu addItem:hideOthersItem];

    NSMenuItem *showAllItem =
        [[NSMenuItem alloc] initWithTitle:@"Show All"
                                   action:@selector(unhideAllApplications:)
                            keyEquivalent:@""];
    showAllItem.target = NSApp;
    [applicationMenu addItem:showAllItem];
    [applicationMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *quitItem =
        [[NSMenuItem alloc] initWithTitle:
            [NSString stringWithFormat:@"Quit %@", applicationName]
                                   action:@selector(terminate:)
                            keyEquivalent:@"q"];
    quitItem.target = NSApp;
    [applicationMenu addItem:quitItem];

    NSMenuItem *applicationMenuItem =
        [[NSMenuItem alloc] initWithTitle:applicationName
                                   action:nil
                            keyEquivalent:@""];
    applicationMenuItem.submenu = applicationMenu;
    [mainMenu addItem:applicationMenuItem];

    [mainMenu addItem:[self fileMenuItem]];
    [mainMenu addItem:[self simulationMenuItem]];
    [mainMenu addItem:[self viewMenuItem]];
    [mainMenu addItem:[self windowMenuItem]];
    [mainMenu addItem:[self helpMenuItem]];

    NSApp.mainMenu = mainMenu;
}

- (NSMenuItem *)fileMenuItem {
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    NSMenuItem *closeItem =
        [[NSMenuItem alloc] initWithTitle:@"Close Window"
                                   action:@selector(performClose:)
                            keyEquivalent:@"w"];
    closeItem.target = nil;
    [fileMenu addItem:closeItem];
    [fileMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *exportJSONItem =
        [[NSMenuItem alloc] initWithTitle:@"Export Results as JSON…"
                                   action:@selector(exportJSONResults:)
                            keyEquivalent:@"e"];
    exportJSONItem.target = self;
    [fileMenu addItem:exportJSONItem];

    NSMenuItem *exportCSVItem =
        [[NSMenuItem alloc] initWithTitle:@"Export Results as CSV…"
                                   action:@selector(exportCSVResults:)
                            keyEquivalent:@"e"];
    exportCSVItem.keyEquivalentModifierMask =
        NSEventModifierFlagCommand | NSEventModifierFlagShift;
    exportCSVItem.target = self;
    [fileMenu addItem:exportCSVItem];

    NSMenuItem *fileItem =
        [[NSMenuItem alloc] initWithTitle:@"File" action:nil keyEquivalent:@""];
    fileItem.submenu = fileMenu;
    return fileItem;
}

- (NSMenuItem *)simulationMenuItem {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Simulation"];

    NSMenuItem *startItem =
        [[NSMenuItem alloc] initWithTitle:@"Start Simulation"
                                   action:@selector(startSimulation:)
                            keyEquivalent:@"r"];
    startItem.target = self;
    [menu addItem:startItem];

    NSMenuItem *pauseItem =
        [[NSMenuItem alloc] initWithTitle:@"Pause Simulation"
                                   action:@selector(pauseSimulation:)
                            keyEquivalent:@"."];
    pauseItem.target = self;
    [menu addItem:pauseItem];

    NSMenuItem *resumeItem =
        [[NSMenuItem alloc] initWithTitle:@"Resume Simulation"
                                   action:@selector(resumeSimulation:)
                            keyEquivalent:@"r"];
    resumeItem.target = self;
    [menu addItem:resumeItem];

    NSMenuItem *stepItem =
        [[NSMenuItem alloc] initWithTitle:@"Step One Event"
                                   action:@selector(stepSimulation:)
                            keyEquivalent:@"t"];
    stepItem.target = self;
    [menu addItem:stepItem];
    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *resetItem =
        [[NSMenuItem alloc] initWithTitle:@"Reset Simulation"
                                   action:@selector(resetSimulation:)
                            keyEquivalent:@"r"];
    resetItem.keyEquivalentModifierMask =
        NSEventModifierFlagCommand | NSEventModifierFlagShift;
    resetItem.target = self;
    [menu addItem:resetItem];

    NSMenuItem *simulationItem =
        [[NSMenuItem alloc] initWithTitle:@"Simulation" action:nil keyEquivalent:@""];
    simulationItem.submenu = menu;
    return simulationItem;
}

- (NSMenuItem *)viewMenuItem {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"View"];

    NSMenuItem *labelsItem =
        [[NSMenuItem alloc] initWithTitle:@"Show Detector Labels"
                                   action:@selector(toggleLabels:)
                            keyEquivalent:@"l"];
    labelsItem.keyEquivalentModifierMask =
        NSEventModifierFlagCommand | NSEventModifierFlagShift;
    labelsItem.target = self;
    [menu addItem:labelsItem];

    NSMenuItem *fadeItem =
        [[NSMenuItem alloc] initWithTitle:@"Fade Tracks"
                                   action:@selector(toggleFadeTracks:)
                            keyEquivalent:@"f"];
    fadeItem.keyEquivalentModifierMask =
        NSEventModifierFlagCommand | NSEventModifierFlagShift;
    fadeItem.target = self;
    [menu addItem:fadeItem];

    NSMenuItem *resetCameraItem =
        [[NSMenuItem alloc] initWithTitle:@"Reset Detector View"
                                   action:@selector(resetDetectorView:)
                            keyEquivalent:@"0"];
    resetCameraItem.target = self;
    [menu addItem:resetCameraItem];

    NSMenuItem *viewItem =
        [[NSMenuItem alloc] initWithTitle:@"View" action:nil keyEquivalent:@""];
    viewItem.submenu = menu;
    return viewItem;
}

- (NSMenuItem *)windowMenuItem {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Window"];

    NSMenuItem *minimizeItem =
        [[NSMenuItem alloc] initWithTitle:@"Minimize"
                                   action:@selector(performMiniaturize:)
                            keyEquivalent:@"m"];
    minimizeItem.target = nil;
    [menu addItem:minimizeItem];

    NSMenuItem *zoomItem =
        [[NSMenuItem alloc] initWithTitle:@"Zoom"
                                   action:@selector(performZoom:)
                            keyEquivalent:@""];
    zoomItem.target = nil;
    [menu addItem:zoomItem];
    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *bringAllItem =
        [[NSMenuItem alloc] initWithTitle:@"Bring All to Front"
                                   action:@selector(arrangeInFront:)
                            keyEquivalent:@""];
    bringAllItem.target = NSApp;
    [menu addItem:bringAllItem];

    NSApp.windowsMenu = menu;
    NSMenuItem *windowItem =
        [[NSMenuItem alloc] initWithTitle:@"Window" action:nil keyEquivalent:@""];
    windowItem.submenu = menu;
    return windowItem;
}

- (NSMenuItem *)helpMenuItem {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Help"];

    NSMenuItem *howItWorksItem =
        [[NSMenuItem alloc] initWithTitle:@"How It Works"
                                   action:@selector(showHowItWorks:)
                            keyEquivalent:@"?"];
    howItWorksItem.target = self;
    [menu addItem:howItWorksItem];

    NSApp.helpMenu = menu;
    NSMenuItem *helpItem =
        [[NSMenuItem alloc] initWithTitle:@"Help" action:nil keyEquivalent:@""];
    helpItem.submenu = menu;
    return helpItem;
}

#pragma mark - Menu actions

- (MDSMainViewController *)mainViewController {
    return self.mainWindowController.mainViewController;
}

- (void)startSimulation:(id)sender {
    [self.mainViewController startSimulation:sender];
}

- (void)pauseSimulation:(id)sender {
    [self.mainViewController pauseSimulation:sender];
}

- (void)resumeSimulation:(id)sender {
    [self.mainViewController resumeSimulation:sender];
}

- (void)stepSimulation:(id)sender {
    [self.mainViewController stepSimulation:sender];
}

- (void)resetSimulation:(id)sender {
    [self.mainViewController resetSimulation:sender];
}

- (void)toggleLabels:(id)sender {
    [self.mainViewController toggleLabels:sender];
}

- (void)resetDetectorView:(id)sender {
    [self.mainViewController resetDetectorView:sender];
}

- (void)showHowItWorks:(id)sender {
    [self.mainViewController showHowItWorks:sender];
}

- (void)exportJSONResults:(id)sender {
    [self.mainViewController exportJSONResults:sender];
}

- (void)exportCSVResults:(id)sender {
    [self.mainViewController exportCSVResults:sender];
}

- (void)toggleFadeTracks:(id)sender {
    [self.mainViewController
        setTracksFading:![self.mainViewController areTracksFading]];
}

- (void)showAboutPanel:(id)sender {
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *version =
        [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"1.0";
    NSString *build = [bundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"1";

    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.alignment = NSTextAlignmentCenter;
    paragraph.lineSpacing = 2.0;
    NSAttributedString *credits = [[NSAttributedString alloc] initWithString:
        @"An educational simulation of a three-tube cosmic-ray muon telescope.\n\n"
        @"This application does not measure radiation, identify particles, or "
        @"communicate with detector hardware. Every displayed rate and event is a "
        @"modeled assumption, not a calibrated measurement."
        attributes:@{
            NSFontAttributeName: [NSFont systemFontOfSize:11.0],
            NSForegroundColorAttributeName: [NSColor secondaryLabelColor],
            NSParagraphStyleAttributeName: paragraph,
        }];

    NSDictionary *options = @{
        NSAboutPanelOptionApplicationName: @"Muon Detector Simulator",
        NSAboutPanelOptionApplicationVersion: version,
        NSAboutPanelOptionVersion: build,
        NSAboutPanelOptionCredits: credits,
    };
    [NSApp orderFrontStandardAboutPanelWithOptions:options];
}

#pragma mark - Validation

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    SEL action = menuItem.action;
    MDSMainViewController *controller = self.mainViewController;

    if (action == @selector(startSimulation:)) {
        return controller.canStartSimulation;
    }
    if (action == @selector(pauseSimulation:)) {
        return controller.canPauseSimulation;
    }
    if (action == @selector(resumeSimulation:)) {
        return controller.canResumeSimulation;
    }
    if (action == @selector(stepSimulation:)) {
        return controller.canStepSimulation;
    }
    if (action == @selector(resetSimulation:)) {
        return controller.canResetSimulation;
    }
    if (action == @selector(toggleLabels:)) {
        const BOOL visible = controller.areSceneLabelsVisible;
        menuItem.state = visible ? NSControlStateValueOn : NSControlStateValueOff;
        return controller != nil;
    }
    if (action == @selector(toggleFadeTracks:)) {
        const BOOL fading = controller.areTracksFading;
        menuItem.state = fading ? NSControlStateValueOn : NSControlStateValueOff;
        return controller != nil;
    }
    if (action == @selector(resetDetectorView:)) {
        return controller != nil;
    }
    if (action == @selector(exportJSONResults:) ||
        action == @selector(exportCSVResults:)) {
        return controller.canExportResults;
    }
    if (action == @selector(showHowItWorks:)) {
        return YES;
    }
    if (action == @selector(showAboutPanel:)) {
        return YES;
    }
    return YES;
}

#if DEBUG
#pragma mark - Local snapshot harness

static NSString *MDSDebugArgumentValue(NSArray<NSString *> *arguments,
                                       NSString *prefix) {
    for (NSString *argument in arguments) {
        if ([argument hasPrefix:prefix] && argument.length > prefix.length) {
            return [argument substringFromIndex:prefix.length];
        }
    }
    return nil;
}

static BOOL MDSDebugWritePNG(NSImage *image, NSString *path) {
    if (image == nil || path.length == 0) {
        return NO;
    }
    NSData *tiff = image.TIFFRepresentation;
    NSBitmapImageRep *bitmap = tiff != nil
        ? [NSBitmapImageRep imageRepWithData:tiff] : nil;
    NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG
                                       properties:@{}];
    if (png == nil) {
        return NO;
    }
    NSString *parentDirectory = [path stringByDeletingLastPathComponent];
    if (parentDirectory.length > 0) {
        [[NSFileManager defaultManager] createDirectoryAtPath:parentDirectory
                                 withIntermediateDirectories:YES
                                                  attributes:nil
                                                       error:NULL];
    }
    return [png writeToFile:path atomically:YES];
}

static NSImage *MDSDebugCaptureWindowContent(NSWindow *window) {
    NSView *view = window.contentView;
    if (view == nil || NSIsEmptyRect(view.bounds)) {
        return nil;
    }
    [view layoutSubtreeIfNeeded];
    [window displayIfNeeded];
    NSBitmapImageRep *bitmap =
        [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    if (bitmap == nil) {
        return nil;
    }
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
    NSImage *image = [[NSImage alloc] initWithSize:view.bounds.size];
    [image addRepresentation:bitmap];
    return image;
}

- (void)runDebugHarnessIfRequested {
    NSArray<NSString *> *arguments = [NSProcessInfo processInfo].arguments;
    self.debugSnapshotPath =
        MDSDebugArgumentValue(arguments, @"--debug-snapshot=");
    self.debugInspectorSnapshotPath =
        MDSDebugArgumentValue(arguments, @"--debug-inspector-snapshot=");
    self.debugHelpSnapshotPath =
        MDSDebugArgumentValue(arguments, @"--debug-help-snapshot=");
    self.debugAboutSnapshotPath =
        MDSDebugArgumentValue(arguments, @"--debug-about-snapshot=");
    self.debugAutoStart = [arguments containsObject:@"--debug-autostart"];
    self.debugExitAfterSnapshot = [arguments containsObject:@"--debug-exit"];
    const BOOL debugFadeOff = [arguments containsObject:@"--debug-fade-off"];
    const BOOL debugShower = [arguments containsObject:@"--debug-shower"];
    const BOOL debugRandom = [arguments containsObject:@"--debug-random"];
    NSString *debugFilter = MDSDebugArgumentValue(arguments, @"--debug-filter=");

    const BOOL hasCapture = self.debugSnapshotPath != nil ||
        self.debugInspectorSnapshotPath != nil ||
        self.debugHelpSnapshotPath != nil ||
        self.debugAboutSnapshotPath != nil;
    if (!hasCapture && !self.debugAutoStart && !self.debugExitAfterSnapshot &&
        !debugFadeOff && !debugShower && !debugRandom && debugFilter.length == 0) {
        return;
    }
    if (debugFadeOff) {
        [self.mainViewController setTracksFading:NO];
    }
    if (debugShower || debugRandom) {
        MDSDetectorConfiguration *configuration =
            [self.mainViewController.configurationViewController.configuration copy];
        if (debugShower) {
            configuration.showerModeEnabled = YES;
        }
        if (debugRandom) {
            configuration.arrivalDirectionMode =
                MDSArrivalDirectionModeRandomRealistic;
        }
        [self.mainViewController.configurationViewController
            setConfiguration:configuration];
    }
    if (debugFilter.length > 0) {
        NSPopUpButton *popup =
            [self.mainViewController valueForKey:@"trackFilterPopup"];
        NSInteger index = 0;
        if ([debugFilter isEqualToString:@"muons"]) {
            index = 1;
        } else if ([debugFilter isEqualToString:@"showers"]) {
            index = 2;
        }
        [popup selectItemAtIndex:index];
        [popup sendAction:popup.action to:popup.target];
    }

    NSTimeInterval delay = 6.0;
    NSString *delayValue = MDSDebugArgumentValue(arguments, @"--debug-delay=");
    if (delayValue != nil) {
        delay = MAX(1.2, delayValue.doubleValue);
    }
    fprintf(stderr, "[MDS debug] harness active: %s\n",
            arguments.description.UTF8String);
    fflush(stderr);

    self.debugOpenTimer =
        [NSTimer scheduledTimerWithTimeInterval:0.6
                                         target:self
                                       selector:@selector(debugOpenTimerFired:)
                                       userInfo:nil
                                        repeats:NO];
    self.debugCaptureTimer =
        [NSTimer scheduledTimerWithTimeInterval:delay
                                         target:self
                                       selector:@selector(debugCaptureTimerFired:)
                                       userInfo:nil
                                        repeats:NO];
    [[NSRunLoop mainRunLoop] addTimer:self.debugOpenTimer
                              forMode:NSRunLoopCommonModes];
    [[NSRunLoop mainRunLoop] addTimer:self.debugCaptureTimer
                              forMode:NSRunLoopCommonModes];
}

- (void)debugOpenTimerFired:(NSTimer *)timer {
    fprintf(stderr, "[MDS debug] open timer fired\n");
    fflush(stderr);
    if (self.debugHelpSnapshotPath != nil) {
        [self.mainViewController showHowItWorks:nil];
    }
    if (self.debugAboutSnapshotPath != nil) {
        [self showAboutPanel:nil];
    }
    if (self.debugAutoStart) {
        [self.mainViewController startSimulation:nil];
    }
}

- (void)debugCaptureTimerFired:(NSTimer *)timer {
    fprintf(stderr, "[MDS debug] capture timer fired\n");
    fflush(stderr);
    [self.mainWindowController.window displayIfNeeded];
    if (self.debugSnapshotPath != nil) {
        NSImage *image = [self.mainViewController debugSnapshotImage];
        BOOL wrote = MDSDebugWritePNG(image, self.debugSnapshotPath);
        fprintf(stderr, "debug snapshot %s: %s\n",
                wrote ? "wrote" : "failed",
                self.debugSnapshotPath.UTF8String);
    }
    if (self.debugInspectorSnapshotPath != nil) {
        NSImage *image = [self.mainViewController debugInspectorSnapshotImage];
        BOOL wrote = MDSDebugWritePNG(image, self.debugInspectorSnapshotPath);
        fprintf(stderr, "debug inspector snapshot %s: %s\n",
                wrote ? "wrote" : "failed",
                self.debugInspectorSnapshotPath.UTF8String);
    }
    if (self.debugHelpSnapshotPath != nil) {
        NSWindow *helpWindow = nil;
        for (NSWindow *window in NSApp.windows) {
            if ([window.title isEqualToString:@"How It Works"]) {
                helpWindow = window;
                break;
            }
        }
        NSImage *image = MDSDebugCaptureWindowContent(helpWindow);
        BOOL wrote = MDSDebugWritePNG(image, self.debugHelpSnapshotPath);
        fprintf(stderr, "debug help snapshot %s: %s\n",
                wrote ? "wrote" : "failed",
                self.debugHelpSnapshotPath.UTF8String);
    }
    if (self.debugAboutSnapshotPath != nil) {
        NSWindow *aboutWindow = nil;
        for (NSWindow *window in NSApp.windows) {
            if ([NSStringFromClass(window.class) containsString:@"About"] ||
                [window.title containsString:@"About"]) {
                aboutWindow = window;
                break;
            }
            if (aboutWindow == nil && window.isVisible &&
                window != self.mainWindowController.window) {
                aboutWindow = window;
            }
        }
        NSImage *image = MDSDebugCaptureWindowContent(aboutWindow);
        BOOL wrote = MDSDebugWritePNG(image, self.debugAboutSnapshotPath);
        fprintf(stderr, "debug about snapshot %s: %s\n",
                wrote ? "wrote" : "failed",
                self.debugAboutSnapshotPath.UTF8String);
    }
    fflush(stderr);

    if (self.debugExitAfterSnapshot) {
        [NSApp terminate:nil];
    }
}
#endif

@end
​​​​​​​​