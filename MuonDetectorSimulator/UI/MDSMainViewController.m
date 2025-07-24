#import "MDSMainViewController.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <math.h>

#import "MDSBatch.h"
#import "MDSCoincidence.h"
#import "MDSConfigurationViewController.h"
#import "MDSDetectorConfiguration.h"
#import "MDSDetectorSceneController.h"
#import "MDSHit.h"
#import "MDSHowItWorksWindowController.h"
#import "MDSLogEntry.h"
#import "MDSResultsExporter.h"
#import "MDSSimulationEngine.h"
#import "MDSSimulationEvent.h"
#import "MDSTimelineView.h"

static const NSUInteger MDSMaximumRetainedLogEntries = 3000;
static const NSTimeInterval MDSUIRefreshInterval = 1.0 / 30.0;

typedef NS_ENUM(NSInteger, MDSResultsExportFormat) {
    MDSResultsExportFormatJSON = 0,
    MDSResultsExportFormatCSV,
};

static NSColor *MDSDetectedTrackColor(void) {
    return [NSColor colorWithSRGBRed:0.05 green:0.55 blue:0.31 alpha:1.0];
}

static NSColor *MDSMissedTrackColor(void) {
    return [NSColor colorWithSRGBRed:0.72 green:0.38 blue:0.04 alpha:0.68];
}

static NSColor *MDSShowerTrackColor(void) {
    return [NSColor colorWithSRGBRed:0.44 green:0.28 blue:0.78 alpha:1.0];
}

static NSColor *MDSHitsTimelineColor(void) {
    return [NSColor colorWithSRGBRed:0.23 green:0.48 blue:0.78 alpha:1.0];
}

#pragma mark - Metric view

/// A compact results readout: an uppercase caption, a prominent value and one
/// secondary detail line. It deliberately uses native labels so VoiceOver reads
/// the title, value and detail independently.
@interface MDSMetricView : NSView

@property (nonatomic, strong) NSTextField *valueLabel;
@property (nonatomic, strong) NSTextField *detailLabel;

- (instancetype)initWithTitle:(NSString *)title;
- (void)setValueText:(NSString *)value detailText:(NSString *)detail;

@end

@implementation MDSMetricView

- (instancetype)initWithTitle:(NSString *)title {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        NSTextField *titleLabel = [NSTextField labelWithString:title.uppercaseString];
        titleLabel.font = [NSFont systemFontOfSize:9.0 weight:NSFontWeightSemibold];
        titleLabel.textColor = [NSColor secondaryLabelColor];
        titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        titleLabel.maximumNumberOfLines = 1;

        _valueLabel =
            [NSTextField labelWithString:@"0"];
        _valueLabel.font =
            [NSFont monospacedDigitSystemFontOfSize:19.0
                                             weight:NSFontWeightSemibold];
        _valueLabel.textColor = [NSColor labelColor];
        _valueLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _valueLabel.maximumNumberOfLines = 1;
        [_valueLabel setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                             forOrientation:NSLayoutConstraintOrientationHorizontal];

        _detailLabel = [NSTextField labelWithString:@""];
        _detailLabel.font = [NSFont systemFontOfSize:10.0];
        _detailLabel.textColor = [NSColor secondaryLabelColor];
        _detailLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _detailLabel.maximumNumberOfLines = 1;
        [_detailLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                              forOrientation:NSLayoutConstraintOrientationHorizontal];

        NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
        stack.orientation = NSUserInterfaceLayoutOrientationVertical;
        stack.alignment = NSLayoutAttributeLeading;
        stack.distribution = NSStackViewDistributionGravityAreas;
        stack.spacing = 1.0;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [stack addArrangedSubview:titleLabel];
        [stack addArrangedSubview:_valueLabel];
        [stack addArrangedSubview:_detailLabel];
        [self addSubview:stack];

        [NSLayoutConstraint activateConstraints:@[
            [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [stack.topAnchor constraintEqualToAnchor:self.topAnchor],
            [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
    }
    return self;
}

- (void)setValueText:(NSString *)value detailText:(NSString *)detail {
    self.valueLabel.stringValue = value;
    self.detailLabel.stringValue = detail;
    self.valueLabel.toolTip = value;
    self.detailLabel.toolTip = detail;
}

@end

#pragma mark - Main controller

@interface MDSMainViewController () <MDSConfigurationViewControllerDelegate,
                                      NSTableViewDataSource,
                                      NSTableViewDelegate>

@property (nonatomic, assign, readwrite) MDSPlaybackState playbackState;
@property (nonatomic, strong, readwrite) MDSConfigurationViewController *configurationViewController;
@property (nonatomic, strong) MDSSimulationEngine *engine;
@property (nonatomic, strong) MDSTimelineView *timelineView;
@property (nonatomic, strong) MDSDetectorSceneController *sceneController;
@property (nonatomic, strong) NSButton *shieldButton;
@property (nonatomic, strong) NSPopUpButton *trackFilterPopup;
@property (nonatomic, strong) NSButton *fadeTracksCheckbox;
@property (nonatomic, strong) NSButton *exportButton;
@property (nonatomic, assign) BOOL shieldWantedVisible;
@property (nonatomic, strong) MDSHowItWorksWindowController *howItWorksWindowController;

@property (nonatomic, strong) NSTimer *playbackTimer;
@property (nonatomic, assign) NSTimeInterval lastTickUptime;
@property (nonatomic, assign) double playbackSpeed;
@property (nonatomic, copy) MDSDetectorConfiguration *previewConfiguration;
@property (nonatomic, assign) BOOL previewConfigurationValid;
@property (nonatomic, copy, nullable) MDSDetectorConfiguration *renderedSceneConfiguration;

@property (nonatomic, strong) NSButton *startButton;
@property (nonatomic, strong) NSButton *pauseButton;
@property (nonatomic, strong) NSButton *resumeButton;
@property (nonatomic, strong) NSButton *stepButton;
@property (nonatomic, strong) NSButton *resetButton;
@property (nonatomic, strong) NSButton *labelsCheckbox;

@property (nonatomic, strong) NSView *statusDot;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSTextField *simulationTimeLabel;
@property (nonatomic, strong) NSTextField *requiredPatternLabel;
@property (nonatomic, strong) NSTextField *summaryNoteLabel;
@property (nonatomic, strong) MDSMetricView *coincidenceMetric;
@property (nonatomic, strong) MDSMetricView *rateMetric;
@property (nonatomic, strong) MDSMetricView *hitsMetric;

@property (nonatomic, strong) NSTableView *eventLogTableView;
@property (nonatomic, strong) NSScrollView *eventLogScrollView;
@property (nonatomic, strong) NSTableColumn *logDetailsColumn;
@property (nonatomic, strong) NSTextField *logCountLabel;
@property (nonatomic, strong) NSTextField *emptyLogLabel;
@property (nonatomic, strong) NSMutableArray<MDSLogEntry *> *logEntries;
@property (nonatomic, assign) BOOL logWasTruncated;

- (void)buildInterface;
- (NSView *)buildHeaderInMainArea:(NSView *)mainArea;
- (void)buildSceneAreaInMainArea:(NSView *)mainArea
                    headerBottom:(NSLayoutYAxisAnchor *)headerBottom;
- (void)buildResultsAreaInView:(NSView *)resultsArea;
- (NSButton *)transportButtonWithTitle:(NSString *)title
                                symbol:(NSString *)symbolName
                                action:(SEL)action
                               toolTip:(NSString *)toolTip;
- (NSButton *)smallButtonWithTitle:(NSString *)title action:(SEL)action;
- (NSTextField *)labelWithString:(NSString *)string
                            font:(NSFont *)font
                           color:(NSColor *)color;
- (NSView *)horizontalSeparator;
- (NSView *)verticalSeparator;
- (NSView *)trackLegendItemWithColor:(NSColor *)color title:(NSString *)title;
- (NSView *)timelineLegendItemWithColor:(NSColor *)color title:(NSString *)title;

- (void)syncFromConfigurationController;
- (void)renderSceneConfigurationIfNeeded:(MDSDetectorConfiguration *)configuration;
- (BOOL)sceneConfigurationMatches:(MDSDetectorConfiguration *)configuration;
- (void)updatePlaybackControls;
- (void)updateStatisticsAndTime;
- (void)updateRequiredPatternLabelWithConfiguration:(MDSDetectorConfiguration *)configuration;
- (void)updateLogCountLabel;
- (void)setStatusText:(NSString *)text color:(NSColor *)color;
- (void)adjustEventLogColumnWidths;

- (BOOL)prepareNewEngineWithConfiguration:(MDSDetectorConfiguration *)configuration
                                    error:(NSError **)error;
- (void)clearPresentationForNewRun;
- (void)startPlaybackTimer;
- (void)stopPlaybackTimer;
- (void)playbackTimerFired:(NSTimer *)timer;
- (void)consumeBatch:(MDSBatch *)batch;
- (void)appendLogEntries:(NSArray<MDSLogEntry *> *)entries;
- (void)finishSimulation;
- (void)presentConfigurationError:(NSError *)error;
- (NSString *)formattedCoincidenceWindow:(double)microseconds;
- (void)setInitialConfigurationSummary;

- (void)labelsCheckboxChanged:(NSButton *)sender;
- (void)trackFilterChanged:(NSPopUpButton *)sender;
- (void)fadeTracksCheckboxChanged:(NSButton *)sender;
- (void)toggleCrystalShield:(NSButton *)sender;
- (void)presentResultsSavePanelForFormat:(MDSResultsExportFormat)format;
- (BOOL)writeResultsData:(NSData *)data toURL:(NSURL *)url error:(NSError **)error;
- (void)presentExportError:(NSError *)error;
- (void)updateShieldButtonForVisible:(BOOL)visible;
- (void)labelCell:(NSTableCellView *)cell
      withString:(NSString *)string
            font:(NSFont *)font
           color:(NSColor *)color
         toolTip:(nullable NSString *)toolTip;

@end

@implementation MDSMainViewController

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        MDSDetectorConfiguration *defaultConfiguration =
            [MDSDetectorConfiguration defaultConfiguration];
        _configurationViewController =
            [[MDSConfigurationViewController alloc] initWithConfiguration:defaultConfiguration];
        _previewConfiguration = [defaultConfiguration copy];
        _previewConfigurationValid = YES;
        _playbackSpeed = 1.0;
        _logEntries = [NSMutableArray array];
        _playbackState = MDSPlaybackStateIdle;
        _shieldWantedVisible = YES;
        _sceneController = [[MDSDetectorSceneController alloc] init];
    }
    return self;
}

- (void)dealloc {
    [_playbackTimer invalidate];
}

- (void)loadView {
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1480, 900)];
    root.wantsLayer = YES;
    root.layer.backgroundColor = [NSColor whiteColor].CGColor;
    self.view = root;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self buildInterface];

    self.configurationViewController.delegate = self;
    [self syncFromConfigurationController];

    self.sceneController.labelsVisible = YES;
    self.sceneController.fadesTracks = YES;
    self.shieldWantedVisible = self.sceneController.isShieldVisible;
    [self updateShieldButtonForVisible:self.shieldWantedVisible];
    self.labelsCheckbox.state = NSControlStateValueOn;
    [self setStatusText:@"Idle" color:[NSColor tertiaryLabelColor]];
    [self updateStatisticsAndTime];
    [self updatePlaybackControls];
}

#pragma mark - Interface construction

- (void)buildInterface {
    NSView *root = self.view;

    NSView *mainArea = [[NSView alloc] initWithFrame:NSZeroRect];
    mainArea.translatesAutoresizingMaskIntoConstraints = NO;
    mainArea.wantsLayer = YES;
    mainArea.layer.backgroundColor = [NSColor whiteColor].CGColor;
    [root addSubview:mainArea];

    [self addChildViewController:self.configurationViewController];
    NSView *inspectorView = self.configurationViewController.view;
    inspectorView.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:inspectorView];

    NSView *divider = [self verticalSeparator];
    [root addSubview:divider];

    [NSLayoutConstraint activateConstraints:@[
        [mainArea.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [mainArea.topAnchor constraintEqualToAnchor:root.topAnchor],
        [mainArea.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [mainArea.trailingAnchor constraintEqualToAnchor:divider.leadingAnchor],

        [divider.widthAnchor constraintEqualToConstant:1.0],
        [divider.topAnchor constraintEqualToAnchor:root.topAnchor],
        [divider.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [divider.trailingAnchor constraintEqualToAnchor:inspectorView.leadingAnchor],

        [inspectorView.widthAnchor constraintEqualToConstant:360.0],
        [inspectorView.topAnchor constraintEqualToAnchor:root.topAnchor],
        [inspectorView.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [inspectorView.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
    ]];

    NSView *headerView = [self buildHeaderInMainArea:mainArea];
    [self addChildViewController:self.sceneController];
    [self buildSceneAreaInMainArea:mainArea
                      headerBottom:headerView.bottomAnchor];
}

- (NSView *)buildHeaderInMainArea:(NSView *)mainArea {
    NSView *header = [[NSView alloc] initWithFrame:NSZeroRect];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [mainArea addSubview:header];

    NSTextField *title = [self labelWithString:@"Muon Detector Simulator"
                                         font:[NSFont systemFontOfSize:19.0
                                                               weight:NSFontWeightSemibold]
                                        color:[NSColor labelColor]];
    title.lineBreakMode = NSLineBreakByTruncatingTail;

    self.statusDot = [[NSView alloc] initWithFrame:NSZeroRect];
    self.statusDot.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusDot.wantsLayer = YES;
    self.statusDot.layer.cornerRadius = 4.0;
    self.statusDot.layer.backgroundColor = [NSColor tertiaryLabelColor].CGColor;
    [self.statusDot setAccessibilityElement:NO];

    self.statusLabel = [self labelWithString:@"Idle"
                                       font:[NSFont systemFontOfSize:11.0
                                                             weight:NSFontWeightSemibold]
                                      color:[NSColor secondaryLabelColor]];
    self.statusLabel.accessibilityLabel = @"Simulation status";

    NSTextField *modeSeparator = [self labelWithString:@"·"
                                                 font:[NSFont systemFontOfSize:11.0]
                                                color:[NSColor tertiaryLabelColor]];
    NSTextField *disclaimer = [self labelWithString:@"Simulation only — no radiation is measured"
                                               font:[NSFont systemFontOfSize:11.0]
                                              color:[NSColor secondaryLabelColor]];
    disclaimer.lineBreakMode = NSLineBreakByTruncatingTail;
    [disclaimer setContentCompressionResistancePriority:NSLayoutPriorityDefaultHigh
                                         forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSStackView *statusStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    statusStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    statusStack.alignment = NSLayoutAttributeCenterY;
    statusStack.spacing = 5.0;
    statusStack.translatesAutoresizingMaskIntoConstraints = NO;
    [statusStack addArrangedSubview:self.statusDot];
    [statusStack addArrangedSubview:self.statusLabel];
    [statusStack addArrangedSubview:modeSeparator];
    [statusStack addArrangedSubview:disclaimer];

    NSStackView *titleStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    titleStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    titleStack.alignment = NSLayoutAttributeLeading;
    titleStack.spacing = 2.0;
    titleStack.translatesAutoresizingMaskIntoConstraints = NO;
    [titleStack addArrangedSubview:title];
    [titleStack addArrangedSubview:statusStack];

    self.startButton = [self transportButtonWithTitle:@"Start"
                                               symbol:@"play.fill"
                                               action:@selector(startSimulation:)
                                              toolTip:@"Start the simulation (⌘R)"];
    self.pauseButton = [self transportButtonWithTitle:@"Pause"
                                               symbol:@"pause.fill"
                                               action:@selector(pauseSimulation:)
                                              toolTip:@"Pause the simulation (⌘.)"];
    self.resumeButton = [self transportButtonWithTitle:@"Resume"
                                                symbol:@"play.circle.fill"
                                                action:@selector(resumeSimulation:)
                                               toolTip:@"Resume a paused simulation (⌘R)"];
    self.stepButton = [self transportButtonWithTitle:@"Step"
                                              symbol:@"forward.end.fill"
                                              action:@selector(stepSimulation:)
                                             toolTip:@"Advance one scheduled detector event (⌘T)"];
    self.resetButton = [self transportButtonWithTitle:@"Reset"
                                               symbol:@"arrow.counterclockwise"
                                               action:@selector(resetSimulation:)
                                              toolTip:@"Clear the run and unlock the configuration (⌘⇧R)"];

    NSStackView *transportStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    transportStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    transportStack.alignment = NSLayoutAttributeCenterY;
    transportStack.spacing = 6.0;
    transportStack.translatesAutoresizingMaskIntoConstraints = NO;
    [transportStack addArrangedSubview:self.startButton];
    [transportStack addArrangedSubview:self.pauseButton];
    [transportStack addArrangedSubview:self.resumeButton];
    [transportStack addArrangedSubview:self.stepButton];
    [transportStack addArrangedSubview:self.resetButton];

    [header addSubview:titleStack];
    [header addSubview:transportStack];

    [NSLayoutConstraint activateConstraints:@[
        [self.statusDot.widthAnchor constraintEqualToConstant:8.0],
        [self.statusDot.heightAnchor constraintEqualToConstant:8.0],

        [header.leadingAnchor constraintEqualToAnchor:mainArea.leadingAnchor constant:18.0],
        [header.trailingAnchor constraintEqualToAnchor:mainArea.trailingAnchor constant:-18.0],
        [header.topAnchor constraintEqualToAnchor:mainArea.topAnchor constant:15.0],

        [titleStack.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],
        [titleStack.topAnchor constraintEqualToAnchor:header.topAnchor],
        [titleStack.bottomAnchor constraintEqualToAnchor:header.bottomAnchor],
        [titleStack.trailingAnchor constraintLessThanOrEqualToAnchor:transportStack.leadingAnchor
                                                            constant:-14.0],

        [transportStack.trailingAnchor constraintEqualToAnchor:header.trailingAnchor],
        [transportStack.centerYAnchor constraintEqualToAnchor:titleStack.centerYAnchor],
    ]];

    NSLayoutConstraint *fillTitleSpace =
        [titleStack.trailingAnchor constraintEqualToAnchor:transportStack.leadingAnchor
                                                  constant:-14.0];
    fillTitleSpace.priority = NSLayoutPriorityDefaultHigh;
    fillTitleSpace.active = YES;

    return header;
}

- (void)buildSceneAreaInMainArea:(NSView *)mainArea
                    headerBottom:(NSLayoutYAxisAnchor *)headerBottom {
    NSView *sceneCard = [[NSView alloc] initWithFrame:NSZeroRect];
    sceneCard.translatesAutoresizingMaskIntoConstraints = NO;
    sceneCard.wantsLayer = YES;
    sceneCard.layer.backgroundColor =
        [NSColor colorWithSRGBRed:0.965 green:0.975 blue:0.985 alpha:1.0].CGColor;
    sceneCard.layer.cornerRadius = 8.0;
    sceneCard.layer.borderWidth = 1.0;
    sceneCard.layer.borderColor =
        [NSColor colorWithSRGBRed:0.855 green:0.875 blue:0.900 alpha:1.0].CGColor;
    sceneCard.layer.masksToBounds = YES;
    [mainArea addSubview:sceneCard];

    NSView *sceneHostView = self.sceneController.view;
    sceneHostView.translatesAutoresizingMaskIntoConstraints = NO;
    [sceneCard addSubview:sceneHostView];

    NSView *controlStrip = [[NSView alloc] initWithFrame:NSZeroRect];
    controlStrip.translatesAutoresizingMaskIntoConstraints = NO;
    controlStrip.wantsLayer = YES;
    controlStrip.layer.backgroundColor =
        [NSColor colorWithSRGBRed:0.988 green:0.992 blue:0.996 alpha:1.0].CGColor;
    [sceneCard addSubview:controlStrip];

    NSView *stripSeparator = [self horizontalSeparator];
    [controlStrip addSubview:stripSeparator];

    NSTextField *gestureHint =
        [self labelWithString:@"Drag to rotate · Scroll or pinch to zoom"
                         font:[NSFont systemFontOfSize:10.5]
                        color:[NSColor tertiaryLabelColor]];
    gestureHint.lineBreakMode = NSLineBreakByTruncatingTail;
    [gestureHint setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                         forOrientation:NSLayoutConstraintOrientationHorizontal];
    gestureHint.translatesAutoresizingMaskIntoConstraints = NO;
    [controlStrip addSubview:gestureHint];

    NSView *legend = [self trackLegend];
    legend.translatesAutoresizingMaskIntoConstraints = NO;
    [controlStrip addSubview:legend];

    NSTextField *trackFilterLabel =
        [self labelWithString:@"Particles"
                         font:[NSFont systemFontOfSize:10.0]
                        color:[NSColor secondaryLabelColor]];
    trackFilterLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [controlStrip addSubview:trackFilterLabel];

    self.trackFilterPopup =
        [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.trackFilterPopup.controlSize = NSControlSizeSmall;
    self.trackFilterPopup.font = [NSFont systemFontOfSize:10.5];
    [self.trackFilterPopup addItemsWithTitles:
        @[ @"All particles", @"Muon candidates", @"Shower particles" ]];
    self.trackFilterPopup.target = self;
    self.trackFilterPopup.action = @selector(trackFilterChanged:);
    self.trackFilterPopup.toolTip =
        @"Choose which simulated particle tracks are shown. The simulation, event log, and statistics are unaffected.";
    self.trackFilterPopup.accessibilityLabel = @"Particle track filter";
    self.trackFilterPopup.translatesAutoresizingMaskIntoConstraints = NO;
    [controlStrip addSubview:self.trackFilterPopup];

    self.fadeTracksCheckbox =
        [NSButton checkboxWithTitle:@"Fade tracks"
                              target:self
                              action:@selector(fadeTracksCheckboxChanged:)];
    self.fadeTracksCheckbox.controlSize = NSControlSizeSmall;
    self.fadeTracksCheckbox.font = [NSFont systemFontOfSize:11.0];
    self.fadeTracksCheckbox.state = NSControlStateValueOn;
    self.fadeTracksCheckbox.toolTip =
        @"Fade all recent particle tracks after a viewing hold. Shower tracks linger longer than single muon candidates. Presentation only.";
    self.fadeTracksCheckbox.accessibilityLabel =
        @"Fade particle tracks";
    self.fadeTracksCheckbox.translatesAutoresizingMaskIntoConstraints = NO;
    [controlStrip addSubview:self.fadeTracksCheckbox];

    self.labelsCheckbox = [NSButton checkboxWithTitle:@"Labels"
                                               target:self
                                               action:@selector(labelsCheckboxChanged:)];
    self.labelsCheckbox.controlSize = NSControlSizeSmall;
    self.labelsCheckbox.font = [NSFont systemFontOfSize:11.0];
    self.labelsCheckbox.state = NSControlStateValueOn;
    self.labelsCheckbox.toolTip = @"Show tube and particle-direction labels";
    self.labelsCheckbox.translatesAutoresizingMaskIntoConstraints = NO;
    [controlStrip addSubview:self.labelsCheckbox];

    NSButton *resetViewButton = [self smallButtonWithTitle:@"Reset View"
                                                   action:@selector(resetDetectorView:)];
    resetViewButton.toolTip = @"Restore the fitted isometric camera";
    [controlStrip addSubview:resetViewButton];

    self.shieldButton = [NSButton buttonWithTitle:@"Hide Shield"
                                           target:self
                                           action:@selector(toggleCrystalShield:)];
    self.shieldButton.bezelStyle = NSBezelStyleRounded;
    self.shieldButton.controlSize = NSControlSizeSmall;
    self.shieldButton.font = [NSFont systemFontOfSize:11.0];
    self.shieldButton.imagePosition = NSImageLeading;
    self.shieldButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.shieldButton.toolTip =
        @"Remove the transparent crystal display cover to inspect the tubes";
    self.shieldButton.accessibilityLabel = @"Hide crystal shield";
    [sceneCard addSubview:self.shieldButton];

    NSView *resultsArea = [[NSView alloc] initWithFrame:NSZeroRect];
    resultsArea.translatesAutoresizingMaskIntoConstraints = NO;
    resultsArea.wantsLayer = YES;
    resultsArea.layer.backgroundColor = [NSColor whiteColor].CGColor;
    [mainArea addSubview:resultsArea];

    [NSLayoutConstraint activateConstraints:@[
        [sceneCard.leadingAnchor constraintEqualToAnchor:mainArea.leadingAnchor constant:18.0],
        [sceneCard.trailingAnchor constraintEqualToAnchor:mainArea.trailingAnchor constant:-18.0],
        [sceneCard.topAnchor constraintEqualToAnchor:headerBottom constant:10.0],
        [sceneCard.bottomAnchor constraintEqualToAnchor:resultsArea.topAnchor constant:-13.0],
        [sceneCard.heightAnchor constraintGreaterThanOrEqualToConstant:220.0],

        [sceneHostView.leadingAnchor constraintEqualToAnchor:sceneCard.leadingAnchor],
        [sceneHostView.trailingAnchor constraintEqualToAnchor:sceneCard.trailingAnchor],
        [sceneHostView.topAnchor constraintEqualToAnchor:sceneCard.topAnchor],
        [sceneHostView.bottomAnchor constraintEqualToAnchor:controlStrip.topAnchor],

        [self.shieldButton.leadingAnchor constraintEqualToAnchor:sceneCard.leadingAnchor
                                                        constant:12.0],
        [self.shieldButton.topAnchor constraintEqualToAnchor:sceneCard.topAnchor
                                                    constant:12.0],

        [controlStrip.leadingAnchor constraintEqualToAnchor:sceneCard.leadingAnchor],
        [controlStrip.trailingAnchor constraintEqualToAnchor:sceneCard.trailingAnchor],
        [controlStrip.bottomAnchor constraintEqualToAnchor:sceneCard.bottomAnchor],
        [controlStrip.heightAnchor constraintEqualToConstant:35.0],
        [stripSeparator.leadingAnchor constraintEqualToAnchor:controlStrip.leadingAnchor],
        [stripSeparator.trailingAnchor constraintEqualToAnchor:controlStrip.trailingAnchor],
        [stripSeparator.topAnchor constraintEqualToAnchor:controlStrip.topAnchor],
        [stripSeparator.heightAnchor constraintEqualToConstant:1.0],
        [gestureHint.leadingAnchor constraintEqualToAnchor:controlStrip.leadingAnchor constant:12.0],
        [gestureHint.centerYAnchor constraintEqualToAnchor:controlStrip.centerYAnchor],
        [legend.leadingAnchor constraintEqualToAnchor:gestureHint.trailingAnchor constant:14.0],
        [legend.centerYAnchor constraintEqualToAnchor:controlStrip.centerYAnchor],
        [trackFilterLabel.leadingAnchor constraintEqualToAnchor:legend.trailingAnchor
                                                       constant:18.0],
        [trackFilterLabel.centerYAnchor constraintEqualToAnchor:controlStrip.centerYAnchor],
        [self.trackFilterPopup.leadingAnchor constraintEqualToAnchor:trackFilterLabel.trailingAnchor
                                                           constant:4.0],
        [self.trackFilterPopup.centerYAnchor constraintEqualToAnchor:controlStrip.centerYAnchor],
        [self.fadeTracksCheckbox.leadingAnchor constraintEqualToAnchor:self.trackFilterPopup.trailingAnchor
                                                               constant:12.0],
        [self.fadeTracksCheckbox.centerYAnchor constraintEqualToAnchor:controlStrip.centerYAnchor],
        [self.labelsCheckbox.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.fadeTracksCheckbox.trailingAnchor
                                                                      constant:12.0],
        [self.labelsCheckbox.trailingAnchor constraintEqualToAnchor:resetViewButton.leadingAnchor
                                                           constant:-10.0],
        [self.labelsCheckbox.centerYAnchor constraintEqualToAnchor:controlStrip.centerYAnchor],
        [resetViewButton.trailingAnchor constraintEqualToAnchor:controlStrip.trailingAnchor
                                                       constant:-10.0],
        [resetViewButton.centerYAnchor constraintEqualToAnchor:controlStrip.centerYAnchor],
        [resetViewButton.widthAnchor constraintGreaterThanOrEqualToConstant:80.0],
    ]];

    [self buildResultsAreaInView:resultsArea];
}

- (void)buildResultsAreaInView:(NSView *)resultsArea {
    NSView *mainArea = resultsArea.superview;
    NSTextField *resultsTitle = [self labelWithString:@"Results"
                                                 font:[NSFont systemFontOfSize:13.5
                                                                       weight:NSFontWeightSemibold]
                                                color:[NSColor labelColor]];
    resultsTitle.translatesAutoresizingMaskIntoConstraints = NO;
    [resultsArea addSubview:resultsTitle];

    self.exportButton = [NSButton buttonWithTitle:@"Export JSON…"
                                           target:self
                                           action:@selector(exportJSONResults:)];
    self.exportButton.bezelStyle = NSBezelStyleRounded;
    self.exportButton.controlSize = NSControlSizeSmall;
    self.exportButton.font = [NSFont systemFontOfSize:10.5];
    self.exportButton.imagePosition = NSImageLeading;
    self.exportButton.image = [[NSImage imageWithSystemSymbolName:@"square.and.arrow.up"
                                          accessibilityDescription:nil]
        imageWithSymbolConfiguration:
            [NSImageSymbolConfiguration configurationWithPointSize:10.0
                                                            weight:NSFontWeightRegular]];
    self.exportButton.toolTip =
        @"Export the current simulated configuration, summary, histogram, and event log as JSON";
    self.exportButton.accessibilityLabel = @"Export results as JSON";
    self.exportButton.enabled = NO;
    self.exportButton.translatesAutoresizingMaskIntoConstraints = NO;
    [resultsArea addSubview:self.exportButton];

    self.simulationTimeLabel = [self labelWithString:@"0.0 / 60.0 s simulated"
                                                font:[NSFont monospacedDigitSystemFontOfSize:10.5
                                                                                      weight:NSFontWeightRegular]
                                               color:[NSColor secondaryLabelColor]];
    self.simulationTimeLabel.alignment = NSTextAlignmentRight;
    self.simulationTimeLabel.accessibilityLabel = @"Simulated time";
    self.simulationTimeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [resultsArea addSubview:self.simulationTimeLabel];

    NSView *summaryColumn = [[NSView alloc] initWithFrame:NSZeroRect];
    summaryColumn.translatesAutoresizingMaskIntoConstraints = NO;
    [resultsArea addSubview:summaryColumn];

    NSView *columnDivider = [self verticalSeparator];
    [resultsArea addSubview:columnDivider];

    NSView *logColumn = [[NSView alloc] initWithFrame:NSZeroRect];
    logColumn.translatesAutoresizingMaskIntoConstraints = NO;
    [resultsArea addSubview:logColumn];

    self.coincidenceMetric = [[MDSMetricView alloc] initWithTitle:@"Coincidences"];
    self.rateMetric = [[MDSMetricView alloc] initWithTitle:@"Coincidence rate"];
    self.hitsMetric = [[MDSMetricView alloc] initWithTitle:@"Tube hits"];

    NSStackView *metricStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    metricStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    metricStack.alignment = NSLayoutAttributeTop;
    metricStack.distribution = NSStackViewDistributionFill;
    metricStack.spacing = 11.0;
    metricStack.translatesAutoresizingMaskIntoConstraints = NO;
    [summaryColumn addSubview:metricStack];
    [metricStack addArrangedSubview:self.coincidenceMetric];
    [metricStack addArrangedSubview:self.rateMetric];
    [metricStack addArrangedSubview:self.hitsMetric];

    self.requiredPatternLabel = [self labelWithString:@""
                                                 font:[NSFont systemFontOfSize:10.5]
                                                color:[NSColor secondaryLabelColor]];
    self.requiredPatternLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.requiredPatternLabel.accessibilityLabel = @"Required coincidence";
    self.requiredPatternLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [summaryColumn addSubview:self.requiredPatternLabel];

    NSTextField *timelineTitle =
        [self labelWithString:@"TIMELINE"
                         font:[NSFont systemFontOfSize:9.0 weight:NSFontWeightSemibold]
                        color:[NSColor secondaryLabelColor]];
    timelineTitle.translatesAutoresizingMaskIntoConstraints = NO;
    [summaryColumn addSubview:timelineTitle];

    NSStackView *timelineLegend = [[NSStackView alloc] initWithFrame:NSZeroRect];
    timelineLegend.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    timelineLegend.alignment = NSLayoutAttributeCenterY;
    timelineLegend.spacing = 9.0;
    timelineLegend.translatesAutoresizingMaskIntoConstraints = NO;
    [summaryColumn addSubview:timelineLegend];
    [timelineLegend addArrangedSubview:
        [self timelineLegendItemWithColor:MDSHitsTimelineColor() title:@"Hits"]];
    [timelineLegend addArrangedSubview:
        [self timelineLegendItemWithColor:MDSDetectedTrackColor() title:@"Coincidences"]];

    self.timelineView = [[MDSTimelineView alloc] initWithFrame:NSZeroRect];
    self.timelineView.translatesAutoresizingMaskIntoConstraints = NO;
    self.timelineView.hitCounts = @[];
    self.timelineView.coincidenceCounts = @[];
    self.timelineView.simulationDuration = self.previewConfiguration.simulationDuration;
    [summaryColumn addSubview:self.timelineView];

    self.summaryNoteLabel = [self labelWithString:@""
                                              font:[NSFont systemFontOfSize:9.5]
                                             color:[NSColor tertiaryLabelColor]];
    self.summaryNoteLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.summaryNoteLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [summaryColumn addSubview:self.summaryNoteLabel];

    NSTextField *logTitle = [self labelWithString:@"Event log"
                                             font:[NSFont systemFontOfSize:11.5
                                                                   weight:NSFontWeightSemibold]
                                            color:[NSColor labelColor]];
    logTitle.translatesAutoresizingMaskIntoConstraints = NO;
    [logColumn addSubview:logTitle];

    self.logCountLabel = [self labelWithString:@"No entries"
                                          font:[NSFont systemFontOfSize:9.5]
                                         color:[NSColor tertiaryLabelColor]];
    self.logCountLabel.alignment = NSTextAlignmentRight;
    self.logCountLabel.toolTip = @"The event log keeps the latest 3,000 rows. Counts and the histogram remain complete.";
    self.logCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [logColumn addSubview:self.logCountLabel];

    [self buildEventLogTableInView:logColumn belowView:logTitle];

    NSLayoutConstraint *resultsHeight =
        [resultsArea.heightAnchor constraintEqualToConstant:286.0];
    resultsHeight.priority = 999.0;

    [NSLayoutConstraint activateConstraints:@[
        [resultsArea.leadingAnchor constraintEqualToAnchor:mainArea.leadingAnchor constant:18.0],
        [resultsArea.trailingAnchor constraintEqualToAnchor:mainArea.trailingAnchor constant:-18.0],
        [resultsArea.bottomAnchor constraintEqualToAnchor:mainArea.bottomAnchor constant:-16.0],
        resultsHeight,

        [resultsTitle.leadingAnchor constraintEqualToAnchor:resultsArea.leadingAnchor],
        [resultsTitle.topAnchor constraintEqualToAnchor:resultsArea.topAnchor],
        [resultsTitle.trailingAnchor constraintLessThanOrEqualToAnchor:self.simulationTimeLabel.leadingAnchor
                                                              constant:-12.0],
        [self.exportButton.leadingAnchor constraintEqualToAnchor:resultsTitle.trailingAnchor
                                                         constant:10.0],
        [self.exportButton.centerYAnchor constraintEqualToAnchor:resultsTitle.centerYAnchor],
        [self.exportButton.trailingAnchor constraintLessThanOrEqualToAnchor:self.simulationTimeLabel.leadingAnchor
                                                                   constant:-12.0],
        [self.simulationTimeLabel.trailingAnchor constraintEqualToAnchor:resultsArea.trailingAnchor],
        [self.simulationTimeLabel.centerYAnchor constraintEqualToAnchor:resultsTitle.centerYAnchor],

        [summaryColumn.leadingAnchor constraintEqualToAnchor:resultsArea.leadingAnchor],
        [summaryColumn.topAnchor constraintEqualToAnchor:resultsTitle.bottomAnchor constant:10.0],
        [summaryColumn.widthAnchor constraintEqualToConstant:396.0],
        [summaryColumn.bottomAnchor constraintLessThanOrEqualToAnchor:resultsArea.bottomAnchor],

        [columnDivider.leadingAnchor constraintEqualToAnchor:summaryColumn.trailingAnchor constant:13.0],
        [columnDivider.widthAnchor constraintEqualToConstant:1.0],
        [columnDivider.topAnchor constraintEqualToAnchor:summaryColumn.topAnchor],
        [columnDivider.bottomAnchor constraintEqualToAnchor:resultsArea.bottomAnchor],

        [logColumn.leadingAnchor constraintEqualToAnchor:columnDivider.trailingAnchor constant:14.0],
        [logColumn.trailingAnchor constraintEqualToAnchor:resultsArea.trailingAnchor],
        [logColumn.topAnchor constraintEqualToAnchor:summaryColumn.topAnchor],
        [logColumn.bottomAnchor constraintEqualToAnchor:resultsArea.bottomAnchor],
        [logColumn.widthAnchor constraintGreaterThanOrEqualToConstant:260.0],

        [metricStack.leadingAnchor constraintEqualToAnchor:summaryColumn.leadingAnchor],
        [metricStack.trailingAnchor constraintEqualToAnchor:summaryColumn.trailingAnchor],
        [metricStack.topAnchor constraintEqualToAnchor:summaryColumn.topAnchor],
        [self.coincidenceMetric.widthAnchor constraintEqualToAnchor:self.rateMetric.widthAnchor],
        [self.rateMetric.widthAnchor constraintEqualToAnchor:self.hitsMetric.widthAnchor],
        [self.coincidenceMetric.heightAnchor constraintGreaterThanOrEqualToConstant:47.0],

        [self.requiredPatternLabel.leadingAnchor constraintEqualToAnchor:summaryColumn.leadingAnchor],
        [self.requiredPatternLabel.trailingAnchor constraintEqualToAnchor:summaryColumn.trailingAnchor],
        [self.requiredPatternLabel.topAnchor constraintEqualToAnchor:metricStack.bottomAnchor constant:7.0],

        [timelineTitle.leadingAnchor constraintEqualToAnchor:summaryColumn.leadingAnchor],
        [timelineTitle.topAnchor constraintEqualToAnchor:self.requiredPatternLabel.bottomAnchor constant:10.0],
        [timelineLegend.trailingAnchor constraintEqualToAnchor:summaryColumn.trailingAnchor],
        [timelineLegend.centerYAnchor constraintEqualToAnchor:timelineTitle.centerYAnchor],
        [timelineLegend.leadingAnchor constraintGreaterThanOrEqualToAnchor:timelineTitle.trailingAnchor constant:8.0],

        [self.timelineView.leadingAnchor constraintEqualToAnchor:summaryColumn.leadingAnchor],
        [self.timelineView.trailingAnchor constraintEqualToAnchor:summaryColumn.trailingAnchor],
        [self.timelineView.topAnchor constraintEqualToAnchor:timelineTitle.bottomAnchor constant:4.0],
        [self.timelineView.heightAnchor constraintEqualToConstant:48.0],

        [self.summaryNoteLabel.leadingAnchor constraintEqualToAnchor:summaryColumn.leadingAnchor],
        [self.summaryNoteLabel.trailingAnchor constraintEqualToAnchor:summaryColumn.trailingAnchor],
        [self.summaryNoteLabel.topAnchor constraintEqualToAnchor:self.timelineView.bottomAnchor constant:4.0],
        [self.summaryNoteLabel.bottomAnchor constraintLessThanOrEqualToAnchor:summaryColumn.bottomAnchor],

        [logTitle.leadingAnchor constraintEqualToAnchor:logColumn.leadingAnchor],
        [logTitle.topAnchor constraintEqualToAnchor:logColumn.topAnchor],
        [self.logCountLabel.trailingAnchor constraintEqualToAnchor:logColumn.trailingAnchor],
        [self.logCountLabel.centerYAnchor constraintEqualToAnchor:logTitle.centerYAnchor],
        [self.logCountLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:logTitle.trailingAnchor constant:8.0],
    ]];
}

- (void)buildEventLogTableInView:(NSView *)container belowView:(NSView *)headerView {
    self.eventLogTableView = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 500, 190)];
    self.eventLogTableView.dataSource = self;
    self.eventLogTableView.delegate = self;
    self.eventLogTableView.rowHeight = 20.0;
    self.eventLogTableView.intercellSpacing = NSMakeSize(6.0, 0.0);
    self.eventLogTableView.usesAlternatingRowBackgroundColors = YES;
    self.eventLogTableView.backgroundColor = [NSColor whiteColor];
    self.eventLogTableView.allowsColumnReordering = NO;
    self.eventLogTableView.allowsColumnResizing = NO;
    self.eventLogTableView.allowsMultipleSelection = NO;
    self.eventLogTableView.columnAutoresizingStyle = NSTableViewNoColumnAutoresizing;
    self.eventLogTableView.style = NSTableViewStylePlain;
    self.eventLogTableView.autoresizingMask = NSViewWidthSizable;
    self.eventLogTableView.accessibilityLabel = @"Event log";
    self.eventLogTableView.accessibilityRoleDescription = @"Table of simulated events";
    self.eventLogTableView.toolTip = @"Chronological list of simulated source events and accepted coincidences";

    NSTableColumn *timeColumn = [[NSTableColumn alloc] initWithIdentifier:@"time"];
    timeColumn.title = @"Time";
    timeColumn.width = 62.0;
    timeColumn.minWidth = 58.0;
    timeColumn.maxWidth = 82.0;
    timeColumn.resizingMask = 0;
    timeColumn.headerCell.accessibilityLabel = @"Simulated timestamp";
    [self.eventLogTableView addTableColumn:timeColumn];

    NSTableColumn *sourceColumn = [[NSTableColumn alloc] initWithIdentifier:@"source"];
    sourceColumn.title = @"Source";
    sourceColumn.width = 90.0;
    sourceColumn.minWidth = 78.0;
    sourceColumn.maxWidth = 140.0;
    sourceColumn.resizingMask = 0;
    sourceColumn.headerCell.accessibilityLabel = @"Event source";
    [self.eventLogTableView addTableColumn:sourceColumn];

    self.logDetailsColumn = [[NSTableColumn alloc] initWithIdentifier:@"details"];
    self.logDetailsColumn.title = @"Hits / tubes";
    self.logDetailsColumn.width = 170.0;
    self.logDetailsColumn.minWidth = 85.0;
    self.logDetailsColumn.resizingMask = NSTableColumnAutoresizingMask;
    self.logDetailsColumn.headerCell.accessibilityLabel = @"Hit timestamps and tubes";
    [self.eventLogTableView addTableColumn:self.logDetailsColumn];

    NSTableColumn *resultColumn = [[NSTableColumn alloc] initWithIdentifier:@"result"];
    resultColumn.title = @"Result";
    resultColumn.width = 88.0;
    resultColumn.minWidth = 74.0;
    resultColumn.maxWidth = 140.0;
    resultColumn.resizingMask = 0;
    resultColumn.headerCell.accessibilityLabel = @"Event result";
    [self.eventLogTableView addTableColumn:resultColumn];

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.hasVerticalScroller = YES;
    scrollView.autohidesScrollers = YES;
    scrollView.hasHorizontalScroller = NO;
    scrollView.horizontalScrollElasticity = NSScrollElasticityNone;
    scrollView.borderType = NSBezelBorder;
    scrollView.drawsBackground = YES;
    scrollView.backgroundColor = [NSColor whiteColor];
    scrollView.documentView = self.eventLogTableView;
    self.eventLogScrollView = scrollView;
    // The native floating header lets scrolled rows show through on current
    // macOS. Use a fixed header row outside the scroll view instead.
    self.eventLogTableView.headerView = nil;
    [container addSubview:scrollView];

    NSView *columnHeader = [[NSView alloc] initWithFrame:NSZeroRect];
    columnHeader.translatesAutoresizingMaskIntoConstraints = NO;
    columnHeader.wantsLayer = YES;
    columnHeader.layer.backgroundColor =
        [NSColor colorWithSRGBRed:0.972 green:0.976 blue:0.980 alpha:1.0].CGColor;
    [container addSubview:columnHeader];

    NSFont *headingFont = [NSFont systemFontOfSize:10.5 weight:NSFontWeightSemibold];
    NSColor *headingColor = [NSColor labelColor];
    NSTextField *timeHeading =
        [self labelWithString:@"Time" font:headingFont color:headingColor];
    NSTextField *sourceHeading =
        [self labelWithString:@"Source" font:headingFont color:headingColor];
    NSTextField *detailsHeading =
        [self labelWithString:@"Hits / tubes" font:headingFont color:headingColor];
    NSTextField *resultHeading =
        [self labelWithString:@"Result" font:headingFont color:headingColor];
    for (NSTextField *heading in @[timeHeading, sourceHeading, detailsHeading, resultHeading]) {
        heading.lineBreakMode = NSLineBreakByTruncatingTail;
        heading.translatesAutoresizingMaskIntoConstraints = NO;
        [columnHeader addSubview:heading];
    }

    NSView *headerRule = [[NSView alloc] initWithFrame:NSZeroRect];
    headerRule.translatesAutoresizingMaskIntoConstraints = NO;
    headerRule.wantsLayer = YES;
    headerRule.layer.backgroundColor = [NSColor separatorColor].CGColor;
    [columnHeader addSubview:headerRule];

    self.emptyLogLabel = [self labelWithString:
        @"No simulated events yet.\nStart or step the simulation to record pulses."
                                            font:[NSFont systemFontOfSize:11.0]
                                           color:[NSColor tertiaryLabelColor]];
    self.emptyLogLabel.alignment = NSTextAlignmentCenter;
    self.emptyLogLabel.maximumNumberOfLines = 2;
    self.emptyLogLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.emptyLogLabel];

    [NSLayoutConstraint activateConstraints:@[
        [columnHeader.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [columnHeader.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [columnHeader.topAnchor constraintEqualToAnchor:headerView.bottomAnchor constant:5.0],
        [columnHeader.heightAnchor constraintEqualToConstant:27.0],

        [timeHeading.leadingAnchor constraintEqualToAnchor:columnHeader.leadingAnchor constant:9.0],
        [timeHeading.widthAnchor constraintEqualToConstant:62.0],
        [timeHeading.centerYAnchor constraintEqualToAnchor:columnHeader.centerYAnchor],

        [sourceHeading.leadingAnchor constraintEqualToAnchor:timeHeading.trailingAnchor constant:6.0],
        [sourceHeading.widthAnchor constraintEqualToConstant:90.0],
        [sourceHeading.centerYAnchor constraintEqualToAnchor:columnHeader.centerYAnchor],

        [detailsHeading.leadingAnchor constraintEqualToAnchor:sourceHeading.trailingAnchor constant:6.0],
        [detailsHeading.centerYAnchor constraintEqualToAnchor:columnHeader.centerYAnchor],

        [resultHeading.trailingAnchor constraintEqualToAnchor:columnHeader.trailingAnchor constant:-9.0],
        [resultHeading.widthAnchor constraintEqualToConstant:88.0],
        [resultHeading.centerYAnchor constraintEqualToAnchor:columnHeader.centerYAnchor],

        [detailsHeading.trailingAnchor constraintLessThanOrEqualToAnchor:resultHeading.leadingAnchor
                                                               constant:-6.0],

        [headerRule.leadingAnchor constraintEqualToAnchor:columnHeader.leadingAnchor],
        [headerRule.trailingAnchor constraintEqualToAnchor:columnHeader.trailingAnchor],
        [headerRule.bottomAnchor constraintEqualToAnchor:columnHeader.bottomAnchor],
        [headerRule.heightAnchor constraintEqualToConstant:1.0],

        [scrollView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [scrollView.topAnchor constraintEqualToAnchor:columnHeader.bottomAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],

        [self.emptyLogLabel.centerXAnchor constraintEqualToAnchor:scrollView.centerXAnchor],
        [self.emptyLogLabel.centerYAnchor constraintEqualToAnchor:scrollView.centerYAnchor constant:7.0],
        [self.emptyLogLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:scrollView.leadingAnchor
                                                                      constant:16.0],
        [self.emptyLogLabel.trailingAnchor constraintLessThanOrEqualToAnchor:scrollView.trailingAnchor
                                                                     constant:-16.0],
    ]];

    columnHeader.accessibilityElement = YES;
    columnHeader.accessibilityRole = NSAccessibilityGroupRole;
    columnHeader.accessibilityLabel =
        @"Event log columns: simulated time, source, hit timestamps and tubes, result.";
}

- (NSView *)trackLegend {
    NSStackView *legend = [[NSStackView alloc] initWithFrame:NSZeroRect];
    legend.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    legend.alignment = NSLayoutAttributeCenterY;
    legend.spacing = 10.0;
    [legend addArrangedSubview:
        [self trackLegendItemWithColor:MDSDetectedTrackColor() title:@"Detected"]];
    [legend addArrangedSubview:
        [self trackLegendItemWithColor:MDSMissedTrackColor() title:@"Not accepted"]];
    [legend addArrangedSubview:
        [self trackLegendItemWithColor:MDSShowerTrackColor() title:@"Shower"]];
    legend.accessibilityElement = YES;
    legend.accessibilityRole = NSAccessibilityGroupRole;
    legend.accessibilityLabel =
        @"Track legend: green detected, amber not accepted, violet shower.";
    return legend;
}

- (NSView *)trackLegendItemWithColor:(NSColor *)color title:(NSString *)title {
    NSView *swatch = [[NSView alloc] initWithFrame:NSZeroRect];
    swatch.translatesAutoresizingMaskIntoConstraints = NO;
    swatch.wantsLayer = YES;
    swatch.layer.backgroundColor = color.CGColor;
    swatch.layer.cornerRadius = 1.5;

    NSTextField *label = [self labelWithString:title
                                         font:[NSFont systemFontOfSize:10.0]
                                        color:[NSColor secondaryLabelColor]];
    label.lineBreakMode = NSLineBreakByTruncatingTail;

    NSStackView *item = [[NSStackView alloc] initWithFrame:NSZeroRect];
    item.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    item.alignment = NSLayoutAttributeCenterY;
    item.spacing = 4.0;
    [item addArrangedSubview:swatch];
    [item addArrangedSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [swatch.widthAnchor constraintEqualToConstant:13.0],
        [swatch.heightAnchor constraintEqualToConstant:3.0],
    ]];
    return item;
}

- (NSView *)timelineLegendItemWithColor:(NSColor *)color title:(NSString *)title {
    NSView *swatch = [[NSView alloc] initWithFrame:NSZeroRect];
    swatch.translatesAutoresizingMaskIntoConstraints = NO;
    swatch.wantsLayer = YES;
    swatch.layer.backgroundColor = color.CGColor;
    swatch.layer.cornerRadius = 3.0;

    NSTextField *label = [self labelWithString:title
                                         font:[NSFont systemFontOfSize:9.0]
                                        color:[NSColor tertiaryLabelColor]];

    NSStackView *item = [[NSStackView alloc] initWithFrame:NSZeroRect];
    item.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    item.alignment = NSLayoutAttributeCenterY;
    item.spacing = 4.0;
    [item addArrangedSubview:swatch];
    [item addArrangedSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [swatch.widthAnchor constraintEqualToConstant:6.0],
        [swatch.heightAnchor constraintEqualToConstant:6.0],
    ]];
    return item;
}

#pragma mark - Small UI factories

- (NSButton *)transportButtonWithTitle:(NSString *)title
                                symbol:(NSString *)symbolName
                                action:(SEL)action
                               toolTip:(NSString *)toolTip {
    NSButton *button = [NSButton buttonWithTitle:title target:self action:action];
    button.bezelStyle = NSBezelStyleRounded;
    button.controlSize = NSControlSizeSmall;
    button.font = [NSFont systemFontOfSize:11.0];
    button.toolTip = toolTip;
    button.imagePosition = NSImageLeading;
    button.imageScaling = NSImageScaleProportionallyDown;
    NSImage *image = [NSImage imageWithSystemSymbolName:symbolName
                              accessibilityDescription:nil];
    image = [image imageWithSymbolConfiguration:
        [NSImageSymbolConfiguration configurationWithPointSize:10.0
                                                        weight:NSFontWeightMedium]];
    button.image = image;
    return button;
}

- (NSButton *)smallButtonWithTitle:(NSString *)title action:(SEL)action {
    NSButton *button = [NSButton buttonWithTitle:title target:self action:action];
    button.bezelStyle = NSBezelStyleRounded;
    button.controlSize = NSControlSizeSmall;
    button.font = [NSFont systemFontOfSize:10.5];
    button.imagePosition = NSImageLeading;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    NSImage *image = [NSImage imageWithSystemSymbolName:@"viewfinder"
                              accessibilityDescription:nil];
    button.image = [image imageWithSymbolConfiguration:
        [NSImageSymbolConfiguration configurationWithPointSize:9.5
                                                        weight:NSFontWeightRegular]];
    return button;
}

- (NSTextField *)labelWithString:(NSString *)string
                            font:(NSFont *)font
                           color:(NSColor *)color {
    NSTextField *label = [NSTextField labelWithString:string];
    label.font = font;
    label.textColor = color;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

- (NSView *)horizontalSeparator {
    NSView *separator = [[NSView alloc] initWithFrame:NSZeroRect];
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    separator.wantsLayer = YES;
    separator.layer.backgroundColor =
        [NSColor colorWithSRGBRed:0.855 green:0.875 blue:0.900 alpha:1.0].CGColor;
    return separator;
}

- (NSView *)verticalSeparator {
    NSView *separator = [[NSView alloc] initWithFrame:NSZeroRect];
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    separator.wantsLayer = YES;
    separator.layer.backgroundColor =
        [NSColor colorWithSRGBRed:0.855 green:0.875 blue:0.900 alpha:1.0].CGColor;
    return separator;
}

#pragma mark - Configuration and playback

- (void)syncFromConfigurationController {
    MDSConfigurationViewController *controller = self.configurationViewController;
    NSError *error = nil;
    const BOOL valid = [controller.configuration validate:&error];
    self.previewConfigurationValid = valid;
    if (valid) {
        self.previewConfiguration = [controller.configuration copy];
    }
    self.playbackSpeed = controller.playbackSpeed;
    self.configurationViewController.delegate = self;

    if (valid) {
        [self renderSceneConfigurationIfNeeded:controller.configuration];
    }
    [self updateRequiredPatternLabelWithConfiguration:controller.configuration];
    [self.timelineView setSimulationDuration:self.previewConfiguration.simulationDuration];
    [controller setControlsEnabled:YES];
}

- (void)configurationViewController:(MDSConfigurationViewController *)controller
            didChangeConfiguration:(MDSDetectorConfiguration *)configuration
                    validationError:(NSError *)validationError
                      playbackSpeed:(double)playbackSpeed {
    self.playbackSpeed = playbackSpeed;
    const BOOL valid = validationError == nil;
    self.previewConfigurationValid = valid;
    if (valid) {
        self.previewConfiguration = [configuration copy];
        if (self.playbackState == MDSPlaybackStateIdle) {
            [self renderSceneConfigurationIfNeeded:configuration];
        }
    }

    [self updateRequiredPatternLabelWithConfiguration:configuration];
    if (self.playbackState == MDSPlaybackStateIdle) {
        [self.timelineView setSimulationDuration:self.previewConfiguration.simulationDuration];
    }
    [self updateStatisticsAndTime];
    [self updatePlaybackControls];
}

- (void)configurationViewControllerDidRequestHelp:
    (MDSConfigurationViewController *)controller {
    [self showHowItWorks:nil];
}

- (void)renderSceneConfigurationIfNeeded:(MDSDetectorConfiguration *)configuration {
    if ([self sceneConfigurationMatches:configuration]) {
        return;
    }
    [self.sceneController applyConfiguration:configuration];
    self.renderedSceneConfiguration = [configuration copy];
    [self.sceneController setLabelsVisible:self.labelsCheckbox.state == NSControlStateValueOn];
}

- (BOOL)sceneConfigurationMatches:(MDSDetectorConfiguration *)configuration {
    MDSDetectorConfiguration *rendered = self.renderedSceneConfiguration;
    if (rendered == nil) {
        return NO;
    }
    return fabs(rendered.tubeSpacing - configuration.tubeSpacing) < 1.0e-9 &&
        fabs(rendered.alignmentOffset - configuration.alignmentOffset) < 1.0e-9 &&
        fabs(rendered.activeLength - configuration.activeLength) < 1.0e-9 &&
        fabs(rendered.activeDiameter - configuration.activeDiameter) < 1.0e-9 &&
        rendered.requiredTubeMask == configuration.requiredTubeMask &&
        rendered.isShowerModeEnabled == configuration.isShowerModeEnabled &&
        rendered.arrivalDirectionMode == configuration.arrivalDirectionMode &&
        fabs(rendered.primaryAngleFromVertical -
             configuration.primaryAngleFromVertical) < 1.0e-9 &&
        fabs(rendered.primaryAzimuth - configuration.primaryAzimuth) < 1.0e-9 &&
        fabs(rendered.showerAngularSpread -
             configuration.showerAngularSpread) < 1.0e-9;
}

#pragma mark - Transport actions

- (void)startSimulation:(id)sender {
    if (self.playbackState != MDSPlaybackStateIdle) {
        return;
    }

    MDSDetectorConfiguration *configuration =
        [self.configurationViewController.configuration copy];
    NSError *error = nil;
    if (![self prepareNewEngineWithConfiguration:configuration error:&error]) {
        [self presentConfigurationError:error];
        return;
    }

    self.playbackState = MDSPlaybackStateRunning;
    [self updatePlaybackControls];
    [self updateStatisticsAndTime];
    [self startPlaybackTimer];
}

- (void)pauseSimulation:(id)sender {
    if (self.playbackState != MDSPlaybackStateRunning) {
        return;
    }
    [self stopPlaybackTimer];
    self.playbackState = MDSPlaybackStatePaused;
    [self updatePlaybackControls];
    [self updateStatisticsAndTime];
}

- (void)resumeSimulation:(id)sender {
    if (self.playbackState != MDSPlaybackStatePaused || self.engine == nil) {
        return;
    }
    self.playbackState = MDSPlaybackStateRunning;
    [self updatePlaybackControls];
    [self startPlaybackTimer];
}

- (void)stepSimulation:(id)sender {
    if (self.playbackState == MDSPlaybackStateIdle) {
        MDSDetectorConfiguration *configuration =
            [self.configurationViewController.configuration copy];
        NSError *error = nil;
        if (![self prepareNewEngineWithConfiguration:configuration error:&error]) {
            [self presentConfigurationError:error];
            return;
        }
        self.playbackState = MDSPlaybackStatePaused;
    } else if (self.playbackState != MDSPlaybackStatePaused) {
        return;
    }

    MDSBatch *batch = [self.engine stepNextEvent];
    [self consumeBatch:batch];
    if (self.engine.isFinished) {
        [self finishSimulation];
    } else {
        [self updatePlaybackControls];
        [self updateStatisticsAndTime];
    }
}

- (void)resetSimulation:(id)sender {
    [self stopPlaybackTimer];
    self.engine = nil;
    self.playbackState = MDSPlaybackStateIdle;
    [self.sceneController clearTracks];

    [self.logEntries removeAllObjects];
    self.logWasTruncated = NO;
    [self.eventLogTableView reloadData];
    [self adjustEventLogColumnWidths];
    [self updateLogCountLabel];
    self.emptyLogLabel.hidden = NO;

    self.timelineView.hitCounts = @[];
    self.timelineView.coincidenceCounts = @[];
    self.timelineView.currentTime = 0.0;
    [self.timelineView setSimulationDuration:self.previewConfiguration.simulationDuration];

    [self.configurationViewController setControlsEnabled:YES];
    [self updatePlaybackControls];
    [self updateStatisticsAndTime];
}

- (BOOL)prepareNewEngineWithConfiguration:(MDSDetectorConfiguration *)configuration
                                    error:(NSError **)error {
    NSError *validationError = nil;
    if (![configuration validate:&validationError]) {
        if (error) {
            *error = validationError;
        }
        return NO;
    }

    MDSSimulationEngine *engine =
        [[MDSSimulationEngine alloc] initWithConfiguration:configuration
                                                     error:&validationError];
    if (engine == nil) {
        if (error) {
            *error = validationError;
        }
        return NO;
    }

    [self stopPlaybackTimer];
    self.engine = engine;
    self.previewConfiguration = [configuration copy];
    [self renderSceneConfigurationIfNeeded:configuration];
    [self clearPresentationForNewRun];
    [self.configurationViewController setControlsEnabled:NO];
    [self.timelineView setSimulationDuration:configuration.simulationDuration];
    self.timelineView.currentTime = 0.0;
    self.lastTickUptime = [NSProcessInfo processInfo].systemUptime;
    return YES;
}

- (void)clearPresentationForNewRun {
    [self.sceneController clearTracks];
    [self.logEntries removeAllObjects];
    self.logWasTruncated = NO;
    [self.eventLogTableView reloadData];
    [self updateLogCountLabel];
    self.emptyLogLabel.hidden = NO;

    self.timelineView.hitCounts = @[];
    self.timelineView.coincidenceCounts = @[];
    self.timelineView.currentTime = 0.0;
    self.simulationTimeLabel.stringValue =
        [NSString stringWithFormat:@"0.0 / %.1f s simulated",
         self.previewConfiguration.simulationDuration];
}

- (void)startPlaybackTimer {
    [self stopPlaybackTimer];
    self.lastTickUptime = [NSProcessInfo processInfo].systemUptime;
    NSTimer *timer = [NSTimer timerWithTimeInterval:MDSUIRefreshInterval
                                             target:self
                                           selector:@selector(playbackTimerFired:)
                                           userInfo:nil
                                            repeats:YES];
    timer.tolerance = 0.004;
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    self.playbackTimer = timer;
}

- (void)stopPlaybackTimer {
    [self.playbackTimer invalidate];
    self.playbackTimer = nil;
}

- (void)playbackTimerFired:(NSTimer *)timer {
    if (self.playbackState != MDSPlaybackStateRunning || self.engine == nil) {
        return;
    }

    const NSTimeInterval now = [NSProcessInfo processInfo].systemUptime;
    NSTimeInterval wallDelta = now - self.lastTickUptime;
    self.lastTickUptime = now;
    wallDelta = MIN(MAX(wallDelta, 0.0), 0.25);

    const double speed = MAX(0.01, self.playbackSpeed);
    const NSTimeInterval target = self.engine.currentTime + wallDelta * speed;
    MDSBatch *batch = [self.engine advanceToTime:target];
    [self consumeBatch:batch];

    if (self.engine.isFinished) {
        [self finishSimulation];
    } else {
        [self updateStatisticsAndTime];
    }
}

- (void)finishSimulation {
    [self stopPlaybackTimer];
    self.playbackState = MDSPlaybackStateFinished;
    [self updatePlaybackControls];
    [self updateStatisticsAndTime];
}

- (void)consumeBatch:(MDSBatch *)batch {
    if (batch.isEmpty) {
        return;
    }

    NSMutableSet<NSNumber *> *acceptedEventIDs = [NSMutableSet set];
    for (MDSCoincidence *coincidence in batch.coincidences) {
        [acceptedEventIDs addObjectsFromArray:coincidence.sourceEventIDs];
    }

    [self.sceneController presentEvents:batch.events
                       acceptedEventIDs:acceptedEventIDs];
    [self.sceneController markEventIDsAccepted:acceptedEventIDs];

    NSMutableArray<MDSHit *> *hits = [NSMutableArray array];
    for (MDSSimulationEvent *event in batch.events) {
        [hits addObjectsFromArray:event.hits];
    }
    [self.sceneController flashHits:hits];

    NSMutableArray<MDSLogEntry *> *newEntries = [NSMutableArray array];
    for (MDSSimulationEvent *event in batch.events) {
        [newEntries addObject:[MDSLogEntry entryForEvent:event]];
    }
    for (MDSCoincidence *coincidence in batch.coincidences) {
        [newEntries addObject:[MDSLogEntry entryForCoincidence:coincidence]];
    }

    [newEntries sortUsingComparator:^NSComparisonResult(MDSLogEntry *first,
                                                         MDSLogEntry *second) {
        if (first.timestamp < second.timestamp) {
            return NSOrderedAscending;
        }
        if (first.timestamp > second.timestamp) {
            return NSOrderedDescending;
        }
        if (first.style == second.style) {
            return NSOrderedSame;
        }
        return first.style == MDSLogEntryStyleCoincidence
            ? NSOrderedDescending : NSOrderedAscending;
    }];
    [self appendLogEntries:newEntries];
}

- (void)appendLogEntries:(NSArray<MDSLogEntry *> *)entries {
    if (entries.count == 0) {
        return;
    }

    const BOOL wasAtBottom = [self eventLogIsScrolledToBottom];
    [self.logEntries addObjectsFromArray:entries];
    if (self.logEntries.count > MDSMaximumRetainedLogEntries) {
        const NSUInteger removeCount =
            self.logEntries.count - MDSMaximumRetainedLogEntries;
        [self.logEntries removeObjectsInRange:NSMakeRange(0, removeCount)];
        self.logWasTruncated = YES;
    }

    [self.eventLogTableView reloadData];
    [self adjustEventLogColumnWidths];
    [self updateLogCountLabel];
    self.emptyLogLabel.hidden = self.logEntries.count > 0;
    if (wasAtBottom) {
        [self.eventLogTableView scrollRowToVisible:
            (NSInteger)self.logEntries.count - 1];
    }
}

- (BOOL)eventLogIsScrolledToBottom {
    if (self.logEntries.count == 0) {
        return YES;
    }
    NSRect visibleRect = self.eventLogScrollView.contentView.bounds;
    NSRect documentRect = self.eventLogTableView.bounds;
    return NSMaxY(visibleRect) >= NSMaxY(documentRect) - 28.0;
}

#pragma mark - State presentation

- (void)updatePlaybackControls {
    self.exportButton.enabled = self.canExportResults;
    const BOOL idle = self.playbackState == MDSPlaybackStateIdle;
    const BOOL running = self.playbackState == MDSPlaybackStateRunning;
    const BOOL paused = self.playbackState == MDSPlaybackStatePaused;
    const BOOL finished = self.playbackState == MDSPlaybackStateFinished;

    self.startButton.enabled = idle && self.previewConfigurationValid;
    self.pauseButton.enabled = running;
    self.resumeButton.enabled = paused;
    self.stepButton.enabled = (idle && self.previewConfigurationValid) || paused;
    self.resetButton.enabled = running || paused || finished;

    [self.configurationViewController setControlsEnabled:idle];

    switch (self.playbackState) {
        case MDSPlaybackStateIdle:
            [self setStatusText:@"Idle" color:[NSColor tertiaryLabelColor]];
            break;
        case MDSPlaybackStateRunning:
            [self setStatusText:@"Running" color:[NSColor systemGreenColor]];
            break;
        case MDSPlaybackStatePaused:
            [self setStatusText:@"Paused" color:[NSColor systemOrangeColor]];
            break;
        case MDSPlaybackStateFinished:
            [self setStatusText:@"Complete" color:[NSColor systemBlueColor]];
            break;
    }
}

- (void)setStatusText:(NSString *)text color:(NSColor *)color {
    self.statusLabel.stringValue = text;
    self.statusLabel.textColor = color;
    self.statusDot.layer.backgroundColor = color.CGColor;
    self.statusLabel.accessibilityValue = text;
}

- (void)updateStatisticsAndTime {
    MDSDetectorConfiguration *displayConfiguration =
        self.engine.configuration ?: self.previewConfiguration;
    const double currentTime = self.engine.currentTime;
    const double duration = displayConfiguration.simulationDuration;

    self.simulationTimeLabel.stringValue =
        [NSString stringWithFormat:@"%.1f / %.1f s simulated", currentTime, duration];
    self.simulationTimeLabel.toolTip = @"Elapsed simulated time / configured duration";

    const NSUInteger coincidences =
        self.engine.acceptedCoincidenceCount;
    const NSUInteger twoFold = self.engine.twoFoldCoincidenceCount;
    const NSUInteger threeFold = self.engine.threeFoldCoincidenceCount;
    const NSUInteger accidental = self.engine.accidentalCoincidenceCount;
    const double rate = self.engine.acceptedCoincidenceRatePerMinute;

    NSArray<NSNumber *> *tubeHits = self.engine.hitCountsPerTube;
    const NSUInteger tube1 = tubeHits.count > 0 ? tubeHits[0].unsignedIntegerValue : 0;
    const NSUInteger tube2 = tubeHits.count > 1 ? tubeHits[1].unsignedIntegerValue : 0;
    const NSUInteger tube3 = tubeHits.count > 2 ? tubeHits[2].unsignedIntegerValue : 0;
    const NSUInteger totalHits = self.engine.totalHitCount;
    const NSUInteger candidates = self.engine.cosmicCandidateCount;
    const NSUInteger background = self.engine.backgroundEventCount;
    const NSUInteger particles = self.engine.totalParticleCount;

    self.coincidenceMetric.valueLabel.stringValue =
        [NSString stringWithFormat:@"%lu", (unsigned long)coincidences];
    self.coincidenceMetric.valueLabel.toolTip =
        [NSString stringWithFormat:@"%lu accepted coincidences", (unsigned long)coincidences];
    self.coincidenceMetric.detailLabel.stringValue =
        [NSString stringWithFormat:@"2-fold %lu · 3-fold %lu",
         (unsigned long)twoFold, (unsigned long)threeFold];
    self.coincidenceMetric.detailLabel.toolTip =
        [NSString stringWithFormat:@"%lu accidental · %lu total accepted",
         (unsigned long)accidental, (unsigned long)coincidences];

    self.rateMetric.valueLabel.stringValue =
        [NSString stringWithFormat:@"%.1f /min", rate];
    self.rateMetric.valueLabel.toolTip =
        @"Accepted coincidences per elapsed simulated minute";
    self.rateMetric.detailLabel.stringValue = @"accepted / simulated min";
    self.rateMetric.detailLabel.toolTip = @"This is a model output, not a calibrated measurement.";

    self.hitsMetric.valueLabel.stringValue =
        [NSString stringWithFormat:@"%lu", (unsigned long)totalHits];
    self.hitsMetric.valueLabel.toolTip =
        [NSString stringWithFormat:@"%lu total tube pulses", (unsigned long)totalHits];
    self.hitsMetric.detailLabel.stringValue =
        [NSString stringWithFormat:@"T1 %lu · T2 %lu · T3 %lu",
         (unsigned long)tube1, (unsigned long)tube2, (unsigned long)tube3];
    self.hitsMetric.detailLabel.toolTip =
        [NSString stringWithFormat:@"Tube 1: %lu · Tube 2: %lu · Tube 3: %lu",
         (unsigned long)tube1, (unsigned long)tube2, (unsigned long)tube3];

    [self updateRequiredPatternLabelWithConfiguration:displayConfiguration];

    NSString *candidateNoun = candidates == 1 ? @"candidate" : @"candidates";
    NSString *backgroundNoun = background == 1 ? @"pulse" : @"pulses";
    self.summaryNoteLabel.stringValue =
        [NSString stringWithFormat:@"%lu accidental · %lu %@ · %lu background %@",
         (unsigned long)accidental, (unsigned long)candidates, candidateNoun,
         (unsigned long)background, backgroundNoun];
    self.summaryNoteLabel.toolTip =
        [NSString stringWithFormat:
            @"%lu candidate events · %lu shower events · %lu particles · %lu background pulses",
            (unsigned long)candidates,
            (unsigned long)self.engine.showerEventCount,
            (unsigned long)particles,
            (unsigned long)background];

    self.timelineView.hitCounts = self.engine.histogramHitCounts;
    self.timelineView.coincidenceCounts = self.engine.histogramCoincidenceCounts;
    self.timelineView.simulationDuration = duration;
    self.timelineView.currentTime = currentTime;
    [self.timelineView updateAccessibilitySummary];

    [self updateLogCountLabel];
}

- (void)updateRequiredPatternLabelWithConfiguration:
    (MDSDetectorConfiguration *)configuration {
    if (configuration == nil) {
        self.requiredPatternLabel.stringValue = @"";
        return;
    }
    NSString *window = [self formattedCoincidenceWindow:
        configuration.coincidenceWindowMicroseconds];
    NSString *text = [NSString stringWithFormat:@"Required: %@ · window %@ µs",
                      [configuration coincidenceDescription], window];
    self.requiredPatternLabel.stringValue = text;
    self.requiredPatternLabel.toolTip =
        @"A coincidence is accepted only when an unconsumed pulse is present in every required tube.";
}

- (NSString *)formattedCoincidenceWindow:(double)microseconds {
    if (microseconds < 10.0) {
        return [NSString stringWithFormat:@"%.2f", microseconds];
    }
    if (microseconds < 100.0) {
        return [NSString stringWithFormat:@"%.1f", microseconds];
    }
    return [NSString stringWithFormat:@"%.0f", microseconds];
}

- (void)updateLogCountLabel {
    if (self.logEntries.count == 0) {
        self.logCountLabel.stringValue = @"No entries";
    } else if (self.logEntries.count >= MDSMaximumRetainedLogEntries) {
        self.logCountLabel.stringValue =
            [NSString stringWithFormat:@"Latest %lu entries",
             (unsigned long)MDSMaximumRetainedLogEntries];
    } else {
        self.logCountLabel.stringValue =
            [NSString stringWithFormat:@"%lu entr%@",
             (unsigned long)self.logEntries.count,
             self.logEntries.count == 1 ? @"y" : @"ies"];
    }
}

- (void)presentConfigurationError:(NSError *)error {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"The simulation could not start";
    NSMutableString *informative = [NSMutableString string];
    if (error.localizedDescription.length > 0) {
        [informative appendString:error.localizedDescription];
    } else {
        [informative appendString:@"The configuration is not valid."];
    }
    if (error.localizedRecoverySuggestion.length > 0) {
        [informative appendFormat:@"\n\n%@", error.localizedRecoverySuggestion];
    }
    alert.informativeText = informative;
    alert.alertStyle = NSAlertStyleWarning;
    [alert addButtonWithTitle:@"OK"];
    if (self.view.window != nil) {
        [alert beginSheetModalForWindow:self.view.window completionHandler:nil];
    } else {
        [alert runModal];
    }
}

#pragma mark - Event log table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)self.logEntries.count;
}

- (NSView *)tableView:(NSTableView *)tableView
    viewForTableColumn:(NSTableColumn *)tableColumn
                   row:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.logEntries.count) {
        return nil;
    }

    MDSLogEntry *entry = self.logEntries[(NSUInteger)row];
    NSString *identifier = tableColumn.identifier;
    NSTableCellView *cell =
        [tableView makeViewWithIdentifier:identifier owner:self];
    if (cell == nil) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 100, 20)];
        cell.identifier = identifier;
        NSTextField *label = [NSTextField labelWithString:@""];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        label.lineBreakMode = NSLineBreakByTruncatingTail;
        label.maximumNumberOfLines = 1;
        [cell addSubview:label];
        cell.textField = label;
        [NSLayoutConstraint activateConstraints:@[
            [label.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:2.0],
            [label.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-2.0],
            [label.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        ]];
    }

    NSTextField *label = cell.textField;
    if ([identifier isEqualToString:@"time"]) {
        [self labelCell:cell
             withString:entry.timeText
                   font:[NSFont monospacedDigitSystemFontOfSize:10.0
                                                        weight:NSFontWeightRegular]
                  color:[NSColor tertiaryLabelColor]
                toolTip:entry.timeText];
    } else if ([identifier isEqualToString:@"source"]) {
        NSColor *color = [NSColor labelColor];
        NSFont *font = [NSFont systemFontOfSize:10.5];
        if (entry.style == MDSLogEntryStyleBackground) {
            color = [NSColor secondaryLabelColor];
        } else if (entry.style == MDSLogEntryStyleCoincidence) {
            color = MDSDetectedTrackColor();
            font = [NSFont systemFontOfSize:10.5 weight:NSFontWeightSemibold];
        }
        [self labelCell:cell
             withString:entry.sourceText
                   font:font
                  color:color
                toolTip:entry.sourceText];
    } else if ([identifier isEqualToString:@"details"]) {
        [self labelCell:cell
             withString:entry.detailsText
                   font:[NSFont systemFontOfSize:10.5]
                  color:entry.style == MDSLogEntryStyleBackground
                      ? [NSColor secondaryLabelColor] : [NSColor labelColor]
                toolTip:entry.detailsText];
    } else {
        NSColor *color = entry.style == MDSLogEntryStyleCoincidence
            ? MDSDetectedTrackColor() : [NSColor secondaryLabelColor];
        NSFont *font = entry.style == MDSLogEntryStyleCoincidence
            ? [NSFont systemFontOfSize:10.5 weight:NSFontWeightSemibold]
            : [NSFont systemFontOfSize:10.5];
        [self labelCell:cell
             withString:entry.resultText
                   font:font
                  color:color
                toolTip:entry.resultText];
    }
    label.accessibilityLabel = [NSString stringWithFormat:@"%@, %@, %@, %@",
        entry.timeText, entry.sourceText, entry.detailsText, entry.resultText];
    return cell;
}

- (void)labelCell:(NSTableCellView *)cell
       withString:(NSString *)string
             font:(NSFont *)font
            color:(NSColor *)color
          toolTip:(NSString *)toolTip {
    NSTextField *label = cell.textField;
    label.stringValue = string;
    label.font = font;
    label.textColor = color;
    label.toolTip = toolTip;
}

- (void)viewDidLayout {
    [super viewDidLayout];
    [self adjustEventLogColumnWidths];
}

- (void)adjustEventLogColumnWidths {
    if (self.eventLogTableView == nil || self.logDetailsColumn == nil) {
        return;
    }
    const CGFloat clipWidth = self.eventLogScrollView.contentView.bounds.size.width;
    const CGFloat tableWidth = MIN(self.eventLogTableView.bounds.size.width,
                                  clipWidth > 0.0 ? clipWidth : CGFLOAT_MAX);
    if (tableWidth < 200.0) {
        return;
    }

    const CGFloat spacing =
        self.eventLogTableView.intercellSpacing.width *
        (CGFloat)(self.eventLogTableView.tableColumns.count - 1);
    CGFloat fixedWidth = 0.0;
    for (NSTableColumn *column in self.eventLogTableView.tableColumns) {
        if (column != self.logDetailsColumn) {
            fixedWidth += column.width;
        }
    }
    CGFloat detailsWidth = floor(tableWidth - fixedWidth - spacing - 2.0);
    detailsWidth = MAX(100.0, detailsWidth);
    if (fabs(self.logDetailsColumn.width - detailsWidth) > 0.5) {
        self.logDetailsColumn.width = detailsWidth;
    }
}

#pragma mark - Actions

- (void)resetDetectorView:(id)sender {
    [self.sceneController resetCamera];
}

- (void)labelsCheckboxChanged:(NSButton *)sender {
    const BOOL visible = sender.state == NSControlStateValueOn;
    self.sceneController.labelsVisible = visible;
}

- (void)trackFilterChanged:(NSPopUpButton *)sender {
    switch (sender.indexOfSelectedItem) {
        case 1:
            self.sceneController.trackDisplayFilter = MDSTrackDisplayFilterMuons;
            break;
        case 2:
            self.sceneController.trackDisplayFilter = MDSTrackDisplayFilterShowers;
            break;
        default:
            self.sceneController.trackDisplayFilter = MDSTrackDisplayFilterAll;
            break;
    }
}

- (void)fadeTracksCheckboxChanged:(NSButton *)sender {
    [self setTracksFading:sender.state == NSControlStateValueOn];
}

- (void)toggleCrystalShield:(NSButton *)sender {
    self.shieldWantedVisible = !self.shieldWantedVisible;
    const BOOL visible = self.shieldWantedVisible;
    // NSButton is still tracking the click when it sends this action. Defer the
    // scene-graph and button-cell changes until tracking has finished so a
    // click cannot re-enter SceneKit or mutate the button image mid-highlight.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)(0.05 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        self.sceneController.shieldVisible = visible;
        [self updateShieldButtonForVisible:visible];
    });
}

- (void)updateShieldButtonForVisible:(BOOL)visible {
    self.shieldButton.title = visible ? @"Hide Shield" : @"Show Shield";
    NSString *symbolName = visible ? @"eye.slash" : @"eye";
    NSImage *symbol =
        [NSImage imageWithSystemSymbolName:symbolName
                  accessibilityDescription:nil];
    self.shieldButton.image = [symbol imageWithSymbolConfiguration:
        [NSImageSymbolConfiguration configurationWithPointSize:10.0
                                                        weight:NSFontWeightRegular]];
    self.shieldButton.toolTip = visible
        ? @"Remove the transparent crystal display cover to inspect the tubes"
        : @"Place the crystal shield back around the tubes";
    self.shieldButton.accessibilityLabel =
        visible ? @"Hide crystal shield" : @"Show crystal shield";
}

- (void)toggleLabels:(id)sender {
    [self setSceneLabelsVisible:![self areSceneLabelsVisible]];
}

- (BOOL)canExportResults {
    return self.engine != nil;
}

- (void)exportJSONResults:(id)sender {
    [self presentResultsSavePanelForFormat:MDSResultsExportFormatJSON];
}

- (void)exportCSVResults:(id)sender {
    [self presentResultsSavePanelForFormat:MDSResultsExportFormatCSV];
}

- (void)presentResultsSavePanelForFormat:(MDSResultsExportFormat)format {
    if (![self canExportResults]) {
        NSBeep();
        return;
    }

    NSData *data = nil;
    NSError *preparationError = nil;
    if (format == MDSResultsExportFormatJSON) {
        data = [MDSResultsExporter
            JSONDataForEngine:self.engine
                   logEntries:self.logEntries
              logWasTruncated:self.logWasTruncated
                        error:&preparationError];
    } else {
        NSString *csv = [MDSResultsExporter
            CSVReportForEngine:self.engine
                    logEntries:self.logEntries
               logWasTruncated:self.logWasTruncated];
        data = [csv dataUsingEncoding:NSUTF8StringEncoding];
        if (data == nil) {
            preparationError = [NSError errorWithDomain:@"MDSResultsExportErrorDomain"
                                                   code:1
                                               userInfo:@{
                NSLocalizedDescriptionKey:
                    @"The results report could not be encoded as UTF-8."
            }];
        }
    }
    if (data == nil) {
        [self presentExportError:preparationError ?: [NSError
            errorWithDomain:@"MDSResultsExportErrorDomain"
                       code:2
                   userInfo:@{
            NSLocalizedDescriptionKey: @"The results report could not be created."
        }]];
        return;
    }

    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.prompt = @"Export";
    panel.nameFieldStringValue = format == MDSResultsExportFormatJSON
        ? [MDSResultsExporter suggestedJSONFileNameForDate:[NSDate date]]
        : [MDSResultsExporter suggestedFileNameForDate:[NSDate date]];
    if (format == MDSResultsExportFormatJSON) {
        panel.title = @"Export Simulated Results as JSON";
        panel.message =
            @"Save the current modeled configuration, counts, histogram, and retained event log as JSON.";
        UTType *jsonType = [UTType typeWithFilenameExtension:@"json"];
        if (jsonType != nil) {
            panel.allowedContentTypes = @[ jsonType ];
        }
    } else {
        panel.title = @"Export Simulated Results as CSV";
        panel.message =
            @"Save the current modeled counts, histogram, and retained event log as CSV.";
        UTType *csvType = [UTType typeWithFilenameExtension:@"csv"];
        if (csvType != nil) {
            panel.allowedContentTypes = @[ csvType ];
        }
    }

    void (^writeReport)(NSURL *) = ^(NSURL *url) {
        NSError *error = nil;
        if (![self writeResultsData:data toURL:url error:&error]) {
            [self presentExportError:error];
        }
    };

    if (self.view.window != nil) {
        [panel beginSheetModalForWindow:self.view.window
                     completionHandler:^(NSModalResponse response) {
            if (response == NSModalResponseOK && panel.URL != nil) {
                writeReport(panel.URL);
            }
        }];
    } else if ([panel runModal] == NSModalResponseOK && panel.URL != nil) {
        writeReport(panel.URL);
    }
}

- (BOOL)writeResultsData:(NSData *)data
                   toURL:(NSURL *)url
                   error:(NSError **)error {
    if (data == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"MDSResultsExportErrorDomain"
                                         code:2
                                     userInfo:@{
                NSLocalizedDescriptionKey:
                    @"The results report could not be created."
            }];
        }
        return NO;
    }
    return [data writeToURL:url options:NSDataWritingAtomic error:error];
}

- (void)presentExportError:(NSError *)error {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Could not export results";
    alert.informativeText = error.localizedDescription ?:
        @"The results file could not be written.";
    alert.alertStyle = NSAlertStyleWarning;
    [alert addButtonWithTitle:@"OK"];
    if (self.view.window != nil) {
        [alert beginSheetModalForWindow:self.view.window completionHandler:nil];
    } else {
        [alert runModal];
    }
}

- (void)showHowItWorks:(id)sender {
    if (self.howItWorksWindowController == nil) {
        self.howItWorksWindowController =
            [[MDSHowItWorksWindowController alloc] init];
    }
    [self.howItWorksWindowController showWindow:self];
    [self.howItWorksWindowController.window makeKeyAndOrderFront:self];
    [self.howItWorksWindowController.window center];
}

#pragma mark - Public state

- (BOOL)canStartSimulation {
    return self.playbackState == MDSPlaybackStateIdle && self.previewConfigurationValid;
}

- (BOOL)canPauseSimulation {
    return self.playbackState == MDSPlaybackStateRunning;
}

- (BOOL)canResumeSimulation {
    return self.playbackState == MDSPlaybackStatePaused;
}

- (BOOL)canStepSimulation {
    return (self.playbackState == MDSPlaybackStateIdle && self.previewConfigurationValid) ||
        self.playbackState == MDSPlaybackStatePaused;
}

- (BOOL)canResetSimulation {
    return self.playbackState != MDSPlaybackStateIdle;
}

- (BOOL)areSceneLabelsVisible {
    return self.sceneController.areLabelsVisible;
}

- (void)setSceneLabelsVisible:(BOOL)visible {
    self.labelsCheckbox.state = visible ? NSControlStateValueOn : NSControlStateValueOff;
    self.sceneController.labelsVisible = visible;
}

- (BOOL)areTracksFading {
    return self.sceneController.fadesTracks;
}

- (void)setTracksFading:(BOOL)fading {
    self.fadeTracksCheckbox.state =
        fading ? NSControlStateValueOn : NSControlStateValueOff;
    self.sceneController.fadesTracks = fading;
}

- (void)setInitialConfigurationSummary {
    [self updateStatisticsAndTime];
}

#if DEBUG
static NSScrollView *MDSFindVerticalScrollView(NSView *view) {
    if ([view isKindOfClass:[NSScrollView class]]) {
        NSScrollView *scrollView = (NSScrollView *)view;
        if (scrollView.hasVerticalScroller && scrollView.documentView != nil) {
            return scrollView;
        }
    }
    for (NSView *subview in view.subviews) {
        NSScrollView *found = MDSFindVerticalScrollView(subview);
        if (found != nil) {
            return found;
        }
    }
    return nil;
}

static NSImage *MDSCaptureViewImage(NSView *view) {
    if (view == nil || NSIsEmptyRect(view.bounds)) {
        return nil;
    }
    [view layoutSubtreeIfNeeded];
    [view displayIfNeeded];
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

- (NSImage *)debugSnapshotImage {
    [self.view.window.contentView layoutSubtreeIfNeeded];
    [self.view.window displayIfNeeded];
    NSImage *image = MDSCaptureViewImage(self.view);
    if (image == nil) {
        return nil;
    }

    NSImage *sceneImage = [self.sceneController debugSnapshotImage];
    if (sceneImage != nil) {
        NSRect sceneRect =
            [self.sceneController.view convertRect:self.sceneController.view.bounds
                                            toView:self.view];
        [image lockFocus];
        [sceneImage drawInRect:sceneRect
                      fromRect:NSZeroRect
                     operation:NSCompositingOperationSourceOver
                      fraction:1.0
                respectFlipped:NO
                         hints:nil];
        [image unlockFocus];
    }

    if (self.shieldButton != nil) {
        NSImage *buttonImage = MDSCaptureViewImage(self.shieldButton);
        NSRect buttonRect =
            [self.shieldButton convertRect:self.shieldButton.bounds toView:self.view];
        if (buttonImage != nil && !NSIsEmptyRect(buttonRect)) {
            [image lockFocus];
            [buttonImage drawInRect:buttonRect
                           fromRect:NSZeroRect
                          operation:NSCompositingOperationSourceOver
                           fraction:1.0
                     respectFlipped:NO
                              hints:nil];
            [image unlockFocus];
        }
    }
    return image;
}

- (NSImage *)debugInspectorSnapshotImage {
    [self.view.window.contentView layoutSubtreeIfNeeded];
    NSScrollView *scrollView =
        MDSFindVerticalScrollView(self.configurationViewController.view);
    NSView *documentView = scrollView.documentView ?: self.configurationViewController.view;
    [documentView layoutSubtreeIfNeeded];
    return MDSCaptureViewImage(documentView);
}
#endif

@end









