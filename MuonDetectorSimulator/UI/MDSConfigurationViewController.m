#import "MDSConfigurationViewController.h"

#import <stdlib.h>
#import <math.h>

#import "MDSDetectorConfiguration.h"

typedef NS_ENUM(NSInteger, MDSConfigControlTag) {
    MDSConfigTagTubeSpacing = 101,
    MDSConfigTagAlignment = 102,
    MDSConfigTagActiveLength = 103,
    MDSConfigTagActiveDiameter = 104,
    MDSConfigTagEfficiency1 = 110,
    MDSConfigTagEfficiency2 = 111,
    MDSConfigTagEfficiency3 = 112,
    MDSConfigTagBackgroundRate = 120,
    MDSConfigTagEventRate = 121,
    MDSConfigTagCoincidenceWindow = 122,
    MDSConfigTagPrimaryAngle = 131,
    MDSConfigTagPrimaryAzimuth = 132,
    MDSConfigTagShowerSpread = 133,
    MDSConfigTagMultiplicity = 134,
    MDSConfigTagRequiredTube1 = 201,
    MDSConfigTagRequiredTube2 = 202,
    MDSConfigTagRequiredTube3 = 203,
};

/// NSScrollView anchors an unflipped document view at its bottom-left corner.
/// The inspector content is authored top-to-bottom, so use a flipped canvas to
/// ensure the assumptions banner is what appears when the view first opens.
@interface MDSFlippedView : NSView
@end

@implementation MDSFlippedView
- (BOOL)isFlipped {
    return YES;
}
@end

@interface MDSConfigurationViewController () <NSTextFieldDelegate>

@property (nonatomic, copy, readwrite) MDSDetectorConfiguration *configuration;
@property (nonatomic, assign, readwrite) double playbackSpeed;
@property (nonatomic, assign, readwrite, getter=isConfigurationValid) BOOL configurationValid;
@property (nonatomic, assign, readwrite, getter=areControlsEnabled) BOOL controlsEnabled;

@property (nonatomic, strong) NSStackView *headerStack;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSView *documentView;
@property (nonatomic, strong) NSStackView *contentStack;
@property (nonatomic, strong) NSTextField *validationLabel;
@property (nonatomic, strong) NSTextField *coincidenceSummaryLabel;
@property (nonatomic, strong) NSTextField *crossSectionLabel;

@property (nonatomic, strong) NSTextField *durationField;
@property (nonatomic, strong) NSStepper *durationStepper;
@property (nonatomic, strong) NSTextField *seedField;
@property (nonatomic, strong) NSPopUpButton *playbackPopup;
@property (nonatomic, strong) NSPopUpButton *arrivalDirectionPopup;
@property (nonatomic, strong) NSSwitch *showerSwitch;

@property (nonatomic, strong) NSMutableArray<NSControl *> *allControls;
@property (nonatomic, strong) NSMutableArray<NSControl *> *showerDependentControls;
@property (nonatomic, strong) NSMutableArray<NSControl *> *showerAxisControls;
@property (nonatomic, strong) NSMutableArray<NSButton *> *requiredTubeButtons;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSSlider *> *slidersByTag;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSTextField *> *valueLabelsByTag;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSString *> *formatsByTag;
@property (nonatomic, strong) NSButton *restoreDefaultsButton;
@property (nonatomic, strong) NSArray<NSNumber *> *playbackSpeedValues;
@property (nonatomic, assign) BOOL suppressNotifications;

- (NSError *)currentValidationError;
- (void)buildHeaderInView:(NSView *)root;
- (void)buildScrollViewInView:(NSView *)root;
- (void)buildFooterInView:(NSView *)root;
- (void)buildInspectorContent;
- (void)syncControlsFromConfiguration;
- (NSStackView *)verticalStackWithSpacing:(CGFloat)spacing;
- (NSStackView *)horizontalStackWithSpacing:(CGFloat)spacing;
- (NSTextField *)labelWithText:(NSString *)text
                           font:(NSFont *)font
                          color:(NSColor *)color;
- (NSTextField *)titleLabelWithText:(NSString *)text;
- (NSTextField *)valueLabelWithText:(NSString *)text;
- (NSTextField *)explanationLabelWithText:(NSString *)text;
- (NSStackView *)settingStackWithTitle:(NSView *)titleView
                              controls:(NSArray<NSView *> *)controls
                           explanation:(nullable NSTextField *)explanation;
- (void)addFullWidthView:(NSView *)view;
- (void)addFullWidthView:(NSView *)view withTopSpacing:(CGFloat)topSpacing;
- (void)addFullWidthView:(NSView *)view toStack:(NSStackView *)stack;
- (void)setSlider:(NSInteger)tag toValue:(double)value;
- (void)updateValueLabels;
- (void)updateValueLabelForTag:(NSInteger)tag;
- (void)updateCoincidenceSummary;
- (void)updateCrossSectionLabel;
- (NSString *)formattedCoincidenceWindow:(double)microseconds;
- (void)selectPlaybackSpeed;
- (double)coincidenceWindowFromSlider:(NSSlider *)slider;
- (void)commitDurationField;
- (void)commitSeedField;
- (void)updateShowerDependentControls;
- (void)validateAndNotify;
- (void)notifyDelegate;
- (void)addAssumptionsBanner;
- (void)addSectionHeader:(NSString *)title;
- (void)addDurationRow;
- (void)addSeedRow;
- (void)addPlaybackSpeedRow;
- (void)addArrivalDirectionRow;

- (NSSlider *)addSliderSettingWithTitle:(NSString *)title
                            explanation:(NSString *)explanation
                                    min:(double)minimum
                                    max:(double)maximum
                                  value:(double)value
                                    tag:(NSInteger)tag
                                 format:(NSString *)format
                                 action:(SEL)action;
- (void)addCoincidenceWindowRow;
- (void)addRequiredTubesRow;
- (void)addShowerSwitchRow;

@end

@implementation MDSConfigurationViewController

- (instancetype)initWithConfiguration:(MDSDetectorConfiguration *)configuration {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _configuration = [configuration copy];
        _playbackSpeed = 1.0;
        _controlsEnabled = YES;
        _configurationValid = YES;
        _allControls = [NSMutableArray array];
        _showerDependentControls = [NSMutableArray array];
        _showerAxisControls = [NSMutableArray array];
        _requiredTubeButtons = [NSMutableArray array];
        _slidersByTag = [NSMutableDictionary dictionary];
        _valueLabelsByTag = [NSMutableDictionary dictionary];
        _formatsByTag = [NSMutableDictionary dictionary];
        _playbackSpeedValues = @[ @1.0, @2.0, @5.0, @10.0 ];
    }
    return self;
}

- (void)loadView {
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 360, 780)];
    root.wantsLayer = YES;
    root.layer.backgroundColor =
        [NSColor colorWithSRGBRed:0.958 green:0.966 blue:0.975 alpha:1.0].CGColor;
    self.view = root;

    [self buildHeaderInView:root];
    [self buildScrollViewInView:root];
    [self buildFooterInView:root];
    [self buildInspectorContent];
    [self syncControlsFromConfiguration];
    [self validateAndNotify];
}

#pragma mark - Interface construction

- (void)buildHeaderInView:(NSView *)root {
    NSTextField *title = [self labelWithText:@"Simulation Setup"
                                        font:[NSFont systemFontOfSize:17
                                                              weight:NSFontWeightSemibold]
                                       color:[NSColor labelColor]];
    NSTextField *subtitle =
        [self labelWithText:@"Adjustable assumptions · simulation only"
                       font:[NSFont systemFontOfSize:11]
                      color:[NSColor secondaryLabelColor]];

    NSStackView *headerStack = [self verticalStackWithSpacing:3];
    [headerStack addArrangedSubview:title];
    [headerStack addArrangedSubview:subtitle];
    headerStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.headerStack = headerStack;
    [root addSubview:headerStack];
    [NSLayoutConstraint activateConstraints:@[
        [headerStack.topAnchor constraintEqualToAnchor:root.topAnchor constant:16.0],
        [headerStack.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:18.0],
        [headerStack.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-18.0],
    ]];
}

- (void)buildScrollViewInView:(NSView *)root {
    NSStackView *headerStack = self.headerStack;
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.drawsBackground = NO;
    scrollView.borderType = NSNoBorder;
    scrollView.hasVerticalScroller = YES;
    scrollView.hasHorizontalScroller = NO;
    scrollView.autohidesScrollers = YES;
    scrollView.horizontalScrollElasticity = NSScrollElasticityNone;
    self.scrollView = scrollView;
    [root addSubview:scrollView];

    NSView *documentView = [[MDSFlippedView alloc] initWithFrame:NSMakeRect(0, 0, 360, 900)];
    documentView.translatesAutoresizingMaskIntoConstraints = NO;
    self.documentView = documentView;
    scrollView.documentView = documentView;

    NSStackView *contentStack = [self verticalStackWithSpacing:12];
    contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentStack = contentStack;
    [documentView addSubview:contentStack];

    [NSLayoutConstraint activateConstraints:@[
        [scrollView.topAnchor constraintEqualToAnchor:headerStack.bottomAnchor constant:8.0],
        [scrollView.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [documentView.widthAnchor constraintEqualToAnchor:scrollView.contentView.widthAnchor],
        [contentStack.topAnchor constraintEqualToAnchor:documentView.topAnchor constant:4.0],
        [contentStack.leadingAnchor constraintEqualToAnchor:documentView.leadingAnchor constant:18.0],
        [contentStack.trailingAnchor constraintEqualToAnchor:documentView.trailingAnchor constant:-18.0],
        [contentStack.bottomAnchor constraintEqualToAnchor:documentView.bottomAnchor constant:-18.0],
    ]];
}

- (void)buildFooterInView:(NSView *)root {
    NSBox *separator = [[NSBox alloc] initWithFrame:NSZeroRect];
    separator.boxType = NSBoxSeparator;
    separator.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *validation = [self labelWithText:@""
                                            font:[NSFont systemFontOfSize:11]
                                           color:[NSColor systemRedColor]];
    validation.maximumNumberOfLines = 0;
    validation.lineBreakMode = NSLineBreakByWordWrapping;
    validation.preferredMaxLayoutWidth = 324.0;
    validation.hidden = YES;
    self.validationLabel = validation;

    NSButton *restore = [NSButton buttonWithTitle:@"Restore Defaults"
                                           target:self
                                           action:@selector(restoreDefaults:)];
    restore.bezelStyle = NSBezelStyleRounded;
    restore.controlSize = NSControlSizeSmall;
    restore.accessibilityLabel = @"Restore default simulation settings";
    self.restoreDefaultsButton = restore;

    NSButton *help = [NSButton buttonWithTitle:@"How It Works"
                                        target:self
                                        action:@selector(helpButtonPressed:)];
    help.bezelStyle = NSBezelStyleRounded;
    help.controlSize = NSControlSizeSmall;
    help.enabled = YES;
    help.accessibilityLabel = @"Open How It Works";
    help.toolTip = @"Learn how the simulation models cosmic rays, tube hits and coincidence.";

    NSView *buttonRow = [[NSView alloc] initWithFrame:NSZeroRect];
    buttonRow.translatesAutoresizingMaskIntoConstraints = NO;
    restore.translatesAutoresizingMaskIntoConstraints = NO;
    help.translatesAutoresizingMaskIntoConstraints = NO;
    [buttonRow addSubview:restore];
    [buttonRow addSubview:help];
    [NSLayoutConstraint activateConstraints:@[
        [restore.leadingAnchor constraintEqualToAnchor:buttonRow.leadingAnchor],
        [restore.centerYAnchor constraintEqualToAnchor:buttonRow.centerYAnchor],
        [help.trailingAnchor constraintEqualToAnchor:buttonRow.trailingAnchor],
        [help.centerYAnchor constraintEqualToAnchor:buttonRow.centerYAnchor],
        [buttonRow.heightAnchor constraintEqualToConstant:26.0],
    ]];

    NSStackView *footerStack = [self verticalStackWithSpacing:7];
    [footerStack addArrangedSubview:validation];
    [footerStack addArrangedSubview:buttonRow];
    footerStack.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:separator];
    [root addSubview:footerStack];

    [NSLayoutConstraint activateConstraints:@[
        [separator.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [separator.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [separator.bottomAnchor constraintEqualToAnchor:footerStack.topAnchor constant:-8.0],
        [footerStack.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:18.0],
        [footerStack.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-18.0],
        [footerStack.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-12.0],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:separator.topAnchor constant:-8.0],
    ]];
}

- (void)buildInspectorContent {
    [self addAssumptionsBanner];

    [self addSectionHeader:@"SIMULATION"];

    [self addDurationRow];
    [self addSeedRow];
    [self addPlaybackSpeedRow];
    [self addArrivalDirectionRow];

    [self addSectionHeader:@"DETECTOR GEOMETRY"];

    [self addSliderSettingWithTitle:@"Tube spacing"
                       explanation:@"Centre-to-centre distance between adjacent active volumes."
                                min:2.0
                                max:20.0
                              value:self.configuration.tubeSpacing
                                tag:MDSConfigTagTubeSpacing
                             format:@"%.1f cm"
                             action:@selector(geometrySliderChanged:)];
    [self addSliderSettingWithTitle:@"Alignment skew"
                       explanation:@"Opposing sideways offset of the top and bottom tubes; zero keeps all three coaxial."
                                min:0.0
                                max:5.0
                              value:self.configuration.alignmentOffset
                                tag:MDSConfigTagAlignment
                             format:@"%.1f cm"
                             action:@selector(geometrySliderChanged:)];
    [self addSliderSettingWithTitle:@"Active length"
                       explanation:@"Length of each gas-filled active volume used for ray intersections."
                                min:2.0
                                max:30.0
                              value:self.configuration.activeLength
                                tag:MDSConfigTagActiveLength
                             format:@"%.1f cm"
                             action:@selector(geometrySliderChanged:)];
    [self addSliderSettingWithTitle:@"Active diameter"
                       explanation:@"Diameter of each cylindrical active volume."
                                min:0.5
                                max:5.0
                              value:self.configuration.activeDiameter
                                tag:MDSConfigTagActiveDiameter
                             format:@"%.1f cm"
                             action:@selector(geometrySliderChanged:)];

    self.crossSectionLabel = [self explanationLabelWithText:@""];
    [self addFullWidthView:self.crossSectionLabel];

    [self addSectionHeader:@"DETECTION & TIMING"];

    for (NSInteger index = 0; index < 3; index++) {
        const NSInteger tag = MDSConfigTagEfficiency1 + index;
        [self addSliderSettingWithTitle:
                [NSString stringWithFormat:@"Tube %ld efficiency", (long)index + 1]
                           explanation:
                [NSString stringWithFormat:
                    @"Probability that a particle crossing Tube %ld produces a detectable pulse.",
                    (long)index + 1]
                                    min:0.0
                                    max:100.0
                                  value:[self.configuration.tubeEfficiencies[index] doubleValue] * 100.0
                                    tag:tag
                                 format:@"%.0f%%"
                                 action:@selector(efficiencySliderChanged:)];
    }

    [self addSliderSettingWithTitle:@"Background rate"
                       explanation:@"Independent Poisson noise pulses per second in each tube. Applied as an observed rate."
                                min:0.0
                                max:20.0
                              value:self.configuration.backgroundRatePerTube
                                tag:MDSConfigTagBackgroundRate
                             format:@"%.1f /s"
                             action:@selector(detectionSliderChanged:)];
    [self addSliderSettingWithTitle:@"Cosmic event rate"
                       explanation:@"Simplified arrival rate for candidate cosmic tracks aimed through the selected tube volumes, not a calibrated flux."
                                min:0.0
                                max:300.0
                              value:self.configuration.cosmicEventRatePerMinute
                                tag:MDSConfigTagEventRate
                             format:@"%.0f /min"
                             action:@selector(detectionSliderChanged:)];

    [self addCoincidenceWindowRow];
    [self addRequiredTubesRow];

    [self addSectionHeader:@"SHOWER MODEL"];
    [self addShowerSwitchRow];

    NSSlider *angleSlider = [self addSliderSettingWithTitle:@"Primary angle"
                       explanation:@"Configured shower axis measured from the downward vertical. Used with the Vertical arrival model; random mode samples this per event."
                                                min:0.0
                                                max:80.0
                                              value:self.configuration.primaryAngleFromVertical
                                                tag:MDSConfigTagPrimaryAngle
                                             format:@"%.0f°"
                                             action:@selector(showerSliderChanged:)];
    [self.showerDependentControls addObject:angleSlider];
    [self.showerAxisControls addObject:angleSlider];

    NSSlider *azimuthSlider = [self addSliderSettingWithTitle:@"Primary azimuth"
                       explanation:@"Configured compass angle of the shower axis. Used with the Vertical arrival model; random mode samples the azimuth per event."
                                                 min:0.0
                                                 max:360.0
                                               value:self.configuration.primaryAzimuth
                                                 tag:MDSConfigTagPrimaryAzimuth
                                              format:@"%.0f°"
                                              action:@selector(showerSliderChanged:)];
    [self.showerDependentControls addObject:azimuthSlider];
    [self.showerAxisControls addObject:azimuthSlider];

    NSSlider *multiplicitySlider = [self addSliderSettingWithTitle:@"Multiplicity"
                       explanation:@"Number of simulated particles in each shower, including the primary."
                                                 min:1.0
                                                 max:20.0
                                               value:self.configuration.showerMultiplicity
                                                 tag:MDSConfigTagMultiplicity
                                              format:@"%.0f"
                                              action:@selector(showerSliderChanged:)];
    multiplicitySlider.numberOfTickMarks = 0;
    [self.showerDependentControls addObject:multiplicitySlider];

    NSSlider *spreadSlider = [self addSliderSettingWithTitle:@"Angular spread"
                       explanation:@"Half-angle of the cone around the primary direction. Directions are sampled uniformly in solid angle."
                                                 min:0.0
                                                 max:60.0
                                               value:self.configuration.showerAngularSpread
                                                 tag:MDSConfigTagShowerSpread
                                              format:@"±%.0f°"
                                              action:@selector(showerSliderChanged:)];
    [self.showerDependentControls addObject:spreadSlider];

    NSTextField *fixedModelNote =
        [self explanationLabelWithText:
            @"Fixed model choices: Poisson event arrivals, 0.025 µs Gaussian timing "
            @"jitter, and no tube dead time. See How It Works for details."];
    [self addFullWidthView:fixedModelNote];

    [self addSectionHeader:@"COINCIDENCE NOTE"];
    NSTextField *coincidenceNote =
        [self explanationLabelWithText:
            @"Coincidence rejects unrelated background pulses, but it does not identify "
            @"a particle with certainty. Other particles and accidental overlaps can "
            @"also satisfy the timing condition."];
    [self addFullWidthView:coincidenceNote];

    [self updateShowerDependentControls];
}

- (void)addAssumptionsBanner {
    NSView *banner = [[NSView alloc] initWithFrame:NSZeroRect];
    banner.translatesAutoresizingMaskIntoConstraints = NO;
    banner.wantsLayer = YES;
    banner.layer.backgroundColor =
        [NSColor colorWithSRGBRed:0.918 green:0.941 blue:0.969 alpha:1.0].CGColor;
    banner.layer.cornerRadius = 6.0;
    banner.layer.borderWidth = 1.0;
    banner.layer.borderColor =
        [NSColor colorWithSRGBRed:0.820 green:0.859 blue:0.902 alpha:1.0].CGColor;

    NSImageView *icon = [[NSImageView alloc] initWithFrame:NSZeroRect];
    icon.image = [NSImage imageWithSystemSymbolName:@"info.circle.fill"
                          accessibilityDescription:nil];
    icon.contentTintColor = [NSColor systemBlueColor];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [banner addSubview:icon];

    NSTextField *title = [self labelWithText:@"Editable assumptions"
                                        font:[NSFont systemFontOfSize:11
                                                              weight:NSFontWeightSemibold]
                                       color:[NSColor labelColor]];
    NSTextField *body = [self labelWithText:
        @"None of these values is a measurement. They shape an educational model; "
        @"fixed implementation choices are listed at the bottom of this panel and in "
        @"How It Works."
                                            font:[NSFont systemFontOfSize:11]
                                           color:[NSColor secondaryLabelColor]];
    body.maximumNumberOfLines = 0;
    body.lineBreakMode = NSLineBreakByWordWrapping;
    body.preferredMaxLayoutWidth = 268.0;

    NSStackView *textStack = [self verticalStackWithSpacing:2];
    [textStack addArrangedSubview:title];
    [textStack addArrangedSubview:body];
    textStack.translatesAutoresizingMaskIntoConstraints = NO;
    [banner addSubview:textStack];

    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor constraintEqualToAnchor:banner.leadingAnchor constant:10.0],
        [icon.topAnchor constraintEqualToAnchor:banner.topAnchor constant:11.0],
        [icon.widthAnchor constraintEqualToConstant:16.0],
        [icon.heightAnchor constraintEqualToConstant:16.0],
        [textStack.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:8.0],
        [textStack.trailingAnchor constraintEqualToAnchor:banner.trailingAnchor constant:-10.0],
        [textStack.topAnchor constraintEqualToAnchor:banner.topAnchor constant:9.0],
        [textStack.bottomAnchor constraintEqualToAnchor:banner.bottomAnchor constant:-10.0],
    ]];
    [self addFullWidthView:banner];
}

- (void)addSectionHeader:(NSString *)title {
    NSTextField *label = [self labelWithText:title
                                        font:[NSFont systemFontOfSize:10.5
                                                              weight:NSFontWeightSemibold]
                                       color:[NSColor secondaryLabelColor]];
    label.maximumNumberOfLines = 1;
    [self addFullWidthView:label withTopSpacing:4.0];
}

- (void)addDurationRow {
    NSTextField *title = [self titleLabelWithText:@"Simulation duration"];
    NSView *controlRow = [[NSView alloc] initWithFrame:NSZeroRect];
    controlRow.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *field = [[NSTextField alloc] initWithFrame:NSZeroRect];
    field.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular];
    field.alignment = NSTextAlignmentRight;
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.accessibilityLabel = @"Simulation duration in seconds";
    field.target = self;
    field.action = @selector(durationFieldCommitted:);
    field.delegate = self;
    field.toolTip = @"Enter 1 to 3600 simulated seconds.";
    self.durationField = field;
    [self.allControls addObject:field];

    NSStepper *stepper = [[NSStepper alloc] initWithFrame:NSZeroRect];
    stepper.minValue = 1.0;
    stepper.maxValue = 3600.0;
    stepper.increment = 5.0;
    stepper.valueWraps = NO;
    stepper.translatesAutoresizingMaskIntoConstraints = NO;
    stepper.target = self;
    stepper.action = @selector(durationStepperChanged:);
    stepper.accessibilityLabel = @"Simulation duration stepper";
    self.durationStepper = stepper;
    [self.allControls addObject:stepper];

    NSTextField *unit = [self labelWithText:@"seconds"
                                       font:[NSFont systemFontOfSize:11]
                                      color:[NSColor secondaryLabelColor]];
    [controlRow addSubview:field];
    [controlRow addSubview:stepper];
    [controlRow addSubview:unit];
    unit.translatesAutoresizingMaskIntoConstraints = NO;

    [NSLayoutConstraint activateConstraints:@[
        [field.leadingAnchor constraintEqualToAnchor:controlRow.leadingAnchor],
        [field.topAnchor constraintEqualToAnchor:controlRow.topAnchor],
        [field.bottomAnchor constraintEqualToAnchor:controlRow.bottomAnchor],
        [field.widthAnchor constraintEqualToConstant:84.0],
        [stepper.leadingAnchor constraintEqualToAnchor:field.trailingAnchor constant:5.0],
        [stepper.centerYAnchor constraintEqualToAnchor:controlRow.centerYAnchor],
        [unit.leadingAnchor constraintEqualToAnchor:stepper.trailingAnchor constant:7.0],
        [unit.centerYAnchor constraintEqualToAnchor:controlRow.centerYAnchor],
    ]];

    NSTextField *explanation =
        [self explanationLabelWithText:
            @"Simulated observation window, not wall-clock time. Playback speed can make "
            @"this window pass more quickly."];
    NSStackView *setting = [self settingStackWithTitle:title
                                               controls:@[ controlRow ]
                                            explanation:explanation];
    [self addFullWidthView:setting];
}

- (void)addSeedRow {
    NSTextField *title = [self titleLabelWithText:@"Random seed"];
    NSView *controlRow = [[NSView alloc] initWithFrame:NSZeroRect];
    controlRow.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *field = [[NSTextField alloc] initWithFrame:NSZeroRect];
    field.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.accessibilityLabel = @"Random seed";
    field.target = self;
    field.action = @selector(seedFieldCommitted:);
    field.delegate = self;
    field.toolTip = @"A 64-bit unsigned integer. The same seed and settings reproduce the same event sequence.";
    self.seedField = field;
    [self.allControls addObject:field];

    NSButton *randomize = [NSButton buttonWithTitle:@"Randomize"
                                             target:self
                                             action:@selector(randomizeSeed:)];
    randomize.bezelStyle = NSBezelStyleRounded;
    randomize.controlSize = NSControlSizeSmall;
    randomize.translatesAutoresizingMaskIntoConstraints = NO;
    randomize.accessibilityLabel = @"Randomize simulation seed";
    randomize.toolTip = @"Choose a new seed. The chosen value is shown and can be reused.";
    [self.allControls addObject:randomize];

    [controlRow addSubview:field];
    [controlRow addSubview:randomize];
    [NSLayoutConstraint activateConstraints:@[
        [field.leadingAnchor constraintEqualToAnchor:controlRow.leadingAnchor],
        [field.topAnchor constraintEqualToAnchor:controlRow.topAnchor],
        [field.bottomAnchor constraintEqualToAnchor:controlRow.bottomAnchor],
        [field.widthAnchor constraintEqualToConstant:138.0],
        [randomize.leadingAnchor constraintEqualToAnchor:field.trailingAnchor constant:7.0],
        [randomize.centerYAnchor constraintEqualToAnchor:controlRow.centerYAnchor],
        [randomize.trailingAnchor constraintLessThanOrEqualToAnchor:controlRow.trailingAnchor],
    ]];

    NSTextField *explanation =
        [self explanationLabelWithText:
            @"Same seed plus the same settings gives a reproducible sequence. Randomize "
            @"selects a new seed before the run starts."];
    NSStackView *setting = [self settingStackWithTitle:title
                                               controls:@[ controlRow ]
                                            explanation:explanation];
    [self addFullWidthView:setting];
}

- (void)addPlaybackSpeedRow {
    NSTextField *title = [self titleLabelWithText:@"Playback speed"];
    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    popup.translatesAutoresizingMaskIntoConstraints = NO;
    popup.controlSize = NSControlSizeRegular;
    popup.accessibilityLabel = @"Playback speed";
    popup.target = self;
    popup.action = @selector(playbackSpeedChanged:);
    for (NSNumber *speed in self.playbackSpeedValues) {
        NSString *title = [NSString stringWithFormat:@"%.0f×", speed.doubleValue];
        [popup addItemWithTitle:title];
        popup.lastItem.representedObject = speed;
    }
    [popup selectItemWithTitle:@"1×"];
    self.playbackPopup = popup;
    [self.allControls addObject:popup];

    NSTextField *explanation =
        [self explanationLabelWithText:
            @"Only changes how quickly simulated time advances. It does not change the "
            @"event rates, coincidence logic, or random sequence."];
    NSStackView *setting = [self settingStackWithTitle:title
                                               controls:@[ popup ]
                                            explanation:explanation];
    [self addFullWidthView:setting];
}

- (void)addArrivalDirectionRow {
    NSTextField *title = [self titleLabelWithText:@"Arrival directions"];
    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    popup.translatesAutoresizingMaskIntoConstraints = NO;
    popup.controlSize = NSControlSizeRegular;
    popup.accessibilityLabel = @"Cosmic arrival direction model";
    popup.target = self;
    popup.action = @selector(arrivalDirectionChanged:);
    [popup addItemsWithTitles:
        @[ @"Vertical (simplified)", @"Random (realistic)" ]];
    self.arrivalDirectionPopup = popup;
    [self.allControls addObject:popup];

    NSTextField *explanation =
        [self explanationLabelWithText:
            @"Random mode samples a new downward primary direction with a cos²θ weighting "
            @"up to 80° from vertical. A candidate is retained only when its path can cross "
            @"all selected tubes, so the default 3-fold stack favors near-vertical tracks. "
            @"In shower mode, particles spread around the sampled axis and the cone stays "
            @"below horizontal."];
    NSStackView *setting = [self settingStackWithTitle:title
                                               controls:@[ popup ]
                                            explanation:explanation];
    [self addFullWidthView:setting];
}

- (NSSlider *)addSliderSettingWithTitle:(NSString *)title
                            explanation:(NSString *)explanation
                                    min:(double)minimum
                                    max:(double)maximum
                                  value:(double)value
                                    tag:(NSInteger)tag
                                 format:(NSString *)format
                                 action:(SEL)action {
    NSTextField *titleLabel = [self titleLabelWithText:title];
    NSTextField *valueLabel = [self valueLabelWithText:@""];
    NSView *titleRow = [[NSView alloc] initWithFrame:NSZeroRect];
    titleRow.translatesAutoresizingMaskIntoConstraints = NO;
    [titleRow addSubview:titleLabel];
    [titleRow addSubview:valueLabel];
    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.leadingAnchor constraintEqualToAnchor:titleRow.leadingAnchor],
        [titleLabel.topAnchor constraintEqualToAnchor:titleRow.topAnchor],
        [titleLabel.bottomAnchor constraintEqualToAnchor:titleRow.bottomAnchor],
        [valueLabel.trailingAnchor constraintEqualToAnchor:titleRow.trailingAnchor],
        [valueLabel.centerYAnchor constraintEqualToAnchor:titleLabel.centerYAnchor],
        [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:valueLabel.leadingAnchor
                                                            constant:-6.0],
    ]];

    NSSlider *slider = [NSSlider sliderWithValue:value
                                        minValue:minimum
                                        maxValue:maximum
                                          target:self
                                          action:action];
    slider.translatesAutoresizingMaskIntoConstraints = NO;
    slider.continuous = YES;
    slider.tag = tag;
    slider.accessibilityLabel = title;
    slider.accessibilityHelp = explanation;
    slider.toolTip = explanation;
    [self.allControls addObject:slider];
    self.slidersByTag[@(tag)] = slider;
    self.valueLabelsByTag[@(tag)] = valueLabel;
    self.formatsByTag[@(tag)] = format;

    NSTextField *detail = [self explanationLabelWithText:explanation];
    NSStackView *setting = [self settingStackWithTitle:titleRow
                                               controls:@[ slider ]
                                            explanation:detail];
    [self addFullWidthView:setting];
    [self updateValueLabelForTag:tag];
    return slider;
}

- (void)addCoincidenceWindowRow {
    NSTextField *title = [self titleLabelWithText:@"Coincidence window"];
    NSTextField *valueLabel = [self valueLabelWithText:@""];
    NSView *titleRow = [[NSView alloc] initWithFrame:NSZeroRect];
    titleRow.translatesAutoresizingMaskIntoConstraints = NO;
    [titleRow addSubview:title];
    [titleRow addSubview:valueLabel];
    [NSLayoutConstraint activateConstraints:@[
        [title.leadingAnchor constraintEqualToAnchor:titleRow.leadingAnchor],
        [title.topAnchor constraintEqualToAnchor:titleRow.topAnchor],
        [title.bottomAnchor constraintEqualToAnchor:titleRow.bottomAnchor],
        [valueLabel.trailingAnchor constraintEqualToAnchor:titleRow.trailingAnchor],
        [valueLabel.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:valueLabel.leadingAnchor
                                                       constant:-6.0],
    ]];

    NSSlider *slider = [NSSlider sliderWithValue:0.5
                                        minValue:0.0
                                        maxValue:1.0
                                          target:self
                                          action:@selector(coincidenceWindowChanged:)];
    slider.translatesAutoresizingMaskIntoConstraints = NO;
    slider.continuous = YES;
    slider.accessibilityLabel = @"Coincidence window in microseconds";
    slider.accessibilityHelp =
        @"Maximum allowed time between pulses in the required tubes. The slider is logarithmic from 0.1 to 1000 microseconds.";
    self.slidersByTag[@(MDSConfigTagCoincidenceWindow)] = slider;
    self.valueLabelsByTag[@(MDSConfigTagCoincidenceWindow)] = valueLabel;
    [self.allControls addObject:slider];

    NSTextField *detail =
        [self explanationLabelWithText:
            @"Maximum separation between hit timestamps for one accepted coincidence. "
            @"The slider is logarithmic from 0.1 to 1000 µs."];
    NSStackView *setting = [self settingStackWithTitle:titleRow
                                               controls:@[ slider ]
                                            explanation:detail];
    [self addFullWidthView:setting];
}

- (void)addRequiredTubesRow {
    NSTextField *title = [self titleLabelWithText:@"Required tubes"];

    NSStackView *checkboxRow = [self horizontalStackWithSpacing:8];
    checkboxRow.distribution = NSStackViewDistributionFillEqually;
    for (NSInteger index = 0; index < 3; index++) {
        NSButton *button = [NSButton checkboxWithTitle:
                                [NSString stringWithFormat:@"Tube %ld", (long)index + 1]
                                                 target:self
                                                 action:@selector(requiredTubeChanged:)];
        button.tag = MDSConfigTagRequiredTube1 + index;
        button.accessibilityLabel =
            [NSString stringWithFormat:@"Require Tube %ld for coincidence",
             (long)index + 1];
        [checkboxRow addArrangedSubview:button];
        [self.requiredTubeButtons addObject:button];
        [self.allControls addObject:button];
    }
    NSTextField *detail =
        [self explanationLabelWithText:
            @"Select at least two tubes. This supports any 2-fold pair or all three "
            @"tubes for a 3-fold coincidence."];
    self.coincidenceSummaryLabel =
        [self labelWithText:@""
                       font:[NSFont monospacedDigitSystemFontOfSize:11
                                                             weight:NSFontWeightRegular]
                      color:[NSColor secondaryLabelColor]];
    self.coincidenceSummaryLabel.accessibilityLabel = @"Current coincidence requirement";

    NSMutableArray<NSView *> *controls = [NSMutableArray arrayWithObjects:
                                           checkboxRow, detail, nil];
    [controls addObject:self.coincidenceSummaryLabel];
    NSStackView *setting = [self settingStackWithTitle:title
                                               controls:controls
                                            explanation:nil];
    [self addFullWidthView:setting];
}

- (void)addShowerSwitchRow {
    NSTextField *title = [self titleLabelWithText:@"Enable shower mode"];
    NSSwitch *showerSwitch = [[NSSwitch alloc] initWithFrame:NSZeroRect];
    showerSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    showerSwitch.target = self;
    showerSwitch.action = @selector(showerModeChanged:);
    showerSwitch.accessibilityLabel = @"Enable shower mode";
    showerSwitch.toolTip = @"Generate a small simulated shower around the primary direction for each cosmic event.";
    self.showerSwitch = showerSwitch;
    [self.allControls addObject:showerSwitch];

    NSView *row = [[NSView alloc] initWithFrame:NSZeroRect];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:title];
    [row addSubview:showerSwitch];
    [NSLayoutConstraint activateConstraints:@[
        [title.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [title.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [showerSwitch.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [showerSwitch.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [showerSwitch.leadingAnchor constraintGreaterThanOrEqualToAnchor:title.trailingAnchor
                                                                 constant:8.0],
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:22.0],
    ]];

    NSTextField *detail =
        [self explanationLabelWithText:
            @"When off, each candidate is a single track along the selected arrival "
            @"direction. When on, multiple particles are drawn in a cone around the "
            @"primary axis."];
    NSStackView *setting = [self settingStackWithTitle:row
                                               controls:@[]
                                            explanation:detail];
    [self addFullWidthView:setting];
}

#pragma mark - Layout helpers

- (NSStackView *)verticalStackWithSpacing:(CGFloat)spacing {
    NSStackView *stack = [NSStackView stackViewWithViews:@[]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.distribution = NSStackViewDistributionGravityAreas;
    stack.spacing = spacing;
    return stack;
}

- (NSStackView *)horizontalStackWithSpacing:(CGFloat)spacing {
    NSStackView *stack = [NSStackView stackViewWithViews:@[]];
    stack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    stack.alignment = NSLayoutAttributeCenterY;
    stack.spacing = spacing;
    return stack;
}

- (NSTextField *)labelWithText:(NSString *)text
                           font:(NSFont *)font
                          color:(NSColor *)color {
    NSTextField *label = [NSTextField labelWithString:text ?: @""];
    label.font = font;
    label.textColor = color;
    label.selectable = NO;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                    forOrientation:NSLayoutConstraintOrientationHorizontal];
    return label;
}

- (NSTextField *)titleLabelWithText:(NSString *)text {
    NSTextField *label = [self labelWithText:text
                                        font:[NSFont systemFontOfSize:12
                                                              weight:NSFontWeightMedium]
                                       color:[NSColor labelColor]];
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    return label;
}

- (NSTextField *)valueLabelWithText:(NSString *)text {
    NSTextField *label =
        [self labelWithText:text
                       font:[NSFont monospacedDigitSystemFontOfSize:11
                                                             weight:NSFontWeightRegular]
                      color:[NSColor secondaryLabelColor]];
    label.alignment = NSTextAlignmentRight;
    [label setContentHuggingPriority:NSLayoutPriorityRequired
                      forOrientation:NSLayoutConstraintOrientationHorizontal];
    return label;
}

- (NSTextField *)explanationLabelWithText:(NSString *)text {
    NSTextField *label = [self labelWithText:text
                                        font:[NSFont systemFontOfSize:11]
                                       color:[NSColor secondaryLabelColor]];
    label.maximumNumberOfLines = 0;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.preferredMaxLayoutWidth = 324.0;
    return label;
}

- (NSStackView *)settingStackWithTitle:(NSView *)titleView
                              controls:(NSArray<NSView *> *)controls
                           explanation:(nullable NSTextField *)explanation {
    NSStackView *stack = [self verticalStackWithSpacing:4];
    [stack addArrangedSubview:titleView];
    for (NSView *control in controls) {
        [self addFullWidthView:control toStack:stack];
    }
    if (explanation != nil) {
        [self addFullWidthView:explanation toStack:stack];
    }
    return stack;
}

- (void)addFullWidthView:(NSView *)view {
    [self addFullWidthView:view withTopSpacing:0.0];
}

- (void)addFullWidthView:(NSView *)view withTopSpacing:(CGFloat)topSpacing {
    NSView *previousView = self.contentStack.arrangedSubviews.lastObject;
    NSView *container = [[NSView alloc] initWithFrame:NSZeroRect];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:view];
    [NSLayoutConstraint activateConstraints:@[
        [view.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [view.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [view.topAnchor constraintEqualToAnchor:container.topAnchor],
        [view.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];
    [self addFullWidthView:container toStack:self.contentStack];
    if (topSpacing > 0.0 && previousView != nil) {
        [self.contentStack setCustomSpacing:topSpacing afterView:previousView];
    }
}

- (void)addFullWidthView:(NSView *)view toStack:(NSStackView *)stack {
    [stack addArrangedSubview:view];
    [view.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
}

#pragma mark - Configuration synchronization

- (void)syncControlsFromConfiguration {
    self.suppressNotifications = YES;
    self.durationField.stringValue =
        [NSString stringWithFormat:@"%.0f", self.configuration.simulationDuration];
    self.durationStepper.doubleValue = self.configuration.simulationDuration;
    self.seedField.stringValue =
        [NSString stringWithFormat:@"%llu", self.configuration.randomSeed];

    [self setSlider:MDSConfigTagTubeSpacing toValue:self.configuration.tubeSpacing];
    [self setSlider:MDSConfigTagAlignment toValue:self.configuration.alignmentOffset];
    [self setSlider:MDSConfigTagActiveLength toValue:self.configuration.activeLength];
    [self setSlider:MDSConfigTagActiveDiameter toValue:self.configuration.activeDiameter];
    for (NSInteger index = 0; index < 3; index++) {
        [self setSlider:MDSConfigTagEfficiency1 + index
                toValue:[self.configuration.tubeEfficiencies[index] doubleValue] * 100.0];
    }
    [self setSlider:MDSConfigTagBackgroundRate
            toValue:self.configuration.backgroundRatePerTube];
    [self setSlider:MDSConfigTagEventRate
            toValue:self.configuration.cosmicEventRatePerMinute];
    [self setSlider:MDSConfigTagPrimaryAngle
            toValue:self.configuration.primaryAngleFromVertical];
    [self setSlider:MDSConfigTagPrimaryAzimuth
            toValue:self.configuration.primaryAzimuth];
    [self setSlider:MDSConfigTagMultiplicity
            toValue:self.configuration.showerMultiplicity];
    [self setSlider:MDSConfigTagShowerSpread
            toValue:self.configuration.showerAngularSpread];

    NSSlider *windowSlider = self.slidersByTag[@(MDSConfigTagCoincidenceWindow)];
    const double window = MIN(1000.0,
                              MAX(0.1, self.configuration.coincidenceWindowMicroseconds));
    windowSlider.doubleValue = (log10(window) + 1.0) / 4.0;
    self.valueLabelsByTag[@(MDSConfigTagCoincidenceWindow)].stringValue =
        [self formattedCoincidenceWindow:window];

    for (NSInteger index = 0; index < 3; index++) {
        NSButton *button = self.requiredTubeButtons[index];
        button.state = (self.configuration.requiredTubeMask & (1u << index)) != 0
            ? NSControlStateValueOn : NSControlStateValueOff;
    }

    self.showerSwitch.state =
        self.configuration.isShowerModeEnabled
            ? NSControlStateValueOn : NSControlStateValueOff;
    [self.arrivalDirectionPopup selectItemAtIndex:
        self.configuration.arrivalDirectionMode ==
            MDSArrivalDirectionModeRandomRealistic ? 1 : 0];
    [self selectPlaybackSpeed];
    [self updateCrossSectionLabel];
    [self updateCoincidenceSummary];
    [self updateValueLabels];
    [self updateShowerDependentControls];
    self.suppressNotifications = NO;
}

- (void)setSlider:(NSInteger)tag toValue:(double)value {
    NSSlider *slider = self.slidersByTag[@(tag)];
    if (slider != nil) {
        slider.doubleValue = value;
    }
}

- (void)updateValueLabels {
    for (NSNumber *tag in self.formatsByTag) {
        [self updateValueLabelForTag:tag.integerValue];
    }
    [self updateCoincidenceSummary];
    [self updateCrossSectionLabel];
}

- (void)updateValueLabelForTag:(NSInteger)tag {
    NSSlider *slider = self.slidersByTag[@(tag)];
    NSTextField *label = self.valueLabelsByTag[@(tag)];
    NSString *format = self.formatsByTag[@(tag)];
    if (slider == nil || label == nil) {
        return;
    }
    double value = slider.doubleValue;
    if (tag == MDSConfigTagMultiplicity) {
        value = round(value);
    }
    label.stringValue = format != nil
        ? [NSString stringWithFormat:format, value] : @"";
    label.accessibilityValue = label.stringValue;
}

- (void)updateCoincidenceSummary {
    if (self.coincidenceSummaryLabel == nil) {
        return;
    }
    self.coincidenceSummaryLabel.stringValue =
        [NSString stringWithFormat:@"Current requirement: %@",
         [self.configuration coincidenceDescription]];
}

- (void)updateCrossSectionLabel {
    if (self.crossSectionLabel == nil) {
        return;
    }
    self.crossSectionLabel.stringValue =
        [NSString stringWithFormat:@"Active cross-section: %.2f cm² per tube",
         [self.configuration activeCrossSectionArea]];
}

- (NSString *)formattedCoincidenceWindow:(double)microseconds {
    if (microseconds < 1.0) {
        return [NSString stringWithFormat:@"%.2f µs", microseconds];
    }
    if (microseconds < 10.0) {
        return [NSString stringWithFormat:@"%.2f µs", microseconds];
    }
    if (microseconds < 100.0) {
        return [NSString stringWithFormat:@"%.1f µs", microseconds];
    }
    return [NSString stringWithFormat:@"%.0f µs", microseconds];
}

- (void)selectPlaybackSpeed {
    NSString *title = [NSString stringWithFormat:@"%.0f×", self.playbackSpeed];
    [self.playbackPopup selectItemWithTitle:title];
}

- (double)coincidenceWindowFromSlider:(NSSlider *)slider {
    return pow(10.0, -1.0 + slider.doubleValue * 4.0);
}

#pragma mark - Actions

- (void)geometrySliderChanged:(NSSlider *)sender {
    switch (sender.tag) {
        case MDSConfigTagTubeSpacing:
            self.configuration.tubeSpacing = sender.doubleValue;
            break;
        case MDSConfigTagAlignment:
            self.configuration.alignmentOffset = sender.doubleValue;
            break;
        case MDSConfigTagActiveLength:
            self.configuration.activeLength = sender.doubleValue;
            break;
        case MDSConfigTagActiveDiameter:
            self.configuration.activeDiameter = sender.doubleValue;
            break;
        default:
            return;
    }
    [self updateValueLabelForTag:sender.tag];
    [self updateCrossSectionLabel];
    [self validateAndNotify];
}

- (void)efficiencySliderChanged:(NSSlider *)sender {
    const NSInteger index = sender.tag - MDSConfigTagEfficiency1;
    if (index < 0 || index >= 3) {
        return;
    }
    NSMutableArray<NSNumber *> *efficiencies =
        [self.configuration.tubeEfficiencies mutableCopy];
    efficiencies[(NSUInteger)index] = @(sender.doubleValue / 100.0);
    self.configuration.tubeEfficiencies = efficiencies;
    [self updateValueLabelForTag:sender.tag];
    [self validateAndNotify];
}

- (void)detectionSliderChanged:(NSSlider *)sender {
    switch (sender.tag) {
        case MDSConfigTagBackgroundRate:
            self.configuration.backgroundRatePerTube = sender.doubleValue;
            break;
        case MDSConfigTagEventRate:
            self.configuration.cosmicEventRatePerMinute = sender.doubleValue;
            break;
        default:
            return;
    }
    [self updateValueLabelForTag:sender.tag];
    [self validateAndNotify];
}

- (void)coincidenceWindowChanged:(NSSlider *)sender {
    NSSlider *slider = self.slidersByTag[@(MDSConfigTagCoincidenceWindow)];
    const double microseconds = [self coincidenceWindowFromSlider:slider];
    self.configuration.coincidenceWindowMicroseconds = microseconds;
    self.valueLabelsByTag[@(MDSConfigTagCoincidenceWindow)].stringValue =
        [self formattedCoincidenceWindow:microseconds];
    [self validateAndNotify];
}

- (void)showerSliderChanged:(NSSlider *)sender {
    switch (sender.tag) {
        case MDSConfigTagPrimaryAngle:
            self.configuration.primaryAngleFromVertical = sender.doubleValue;
            break;
        case MDSConfigTagPrimaryAzimuth:
            self.configuration.primaryAzimuth = sender.doubleValue;
            break;
        case MDSConfigTagMultiplicity:
            sender.doubleValue = round(sender.doubleValue);
            self.configuration.showerMultiplicity = (NSInteger)round(sender.doubleValue);
            break;
        case MDSConfigTagShowerSpread:
            self.configuration.showerAngularSpread = sender.doubleValue;
            break;
        default:
            return;
    }
    [self updateValueLabelForTag:sender.tag];
    [self validateAndNotify];
}

- (void)requiredTubeChanged:(NSButton *)sender {
    NSUInteger mask = 0;
    for (NSInteger index = 0; index < (NSInteger)self.requiredTubeButtons.count; index++) {
        if (self.requiredTubeButtons[index].state == NSControlStateValueOn) {
            mask |= (1u << index);
        }
    }
    self.configuration.requiredTubeMask = mask;
    [self updateCoincidenceSummary];
    [self validateAndNotify];
}

- (void)showerModeChanged:(NSSwitch *)sender {
    self.configuration.showerModeEnabled =
        sender.state == NSControlStateValueOn;
    [self updateShowerDependentControls];
    [self validateAndNotify];
}

- (void)playbackSpeedChanged:(NSPopUpButton *)sender {
    NSNumber *speed = sender.selectedItem.representedObject;
    if (speed != nil) {
        self.playbackSpeed = speed.doubleValue;
    }
    [self notifyDelegate];
}

- (void)arrivalDirectionChanged:(NSPopUpButton *)sender {
    self.configuration.arrivalDirectionMode =
        sender.indexOfSelectedItem == 1
            ? MDSArrivalDirectionModeRandomRealistic
            : MDSArrivalDirectionModeVertical;
    [self updateShowerDependentControls];
    [self validateAndNotify];
}

- (void)durationFieldCommitted:(id)sender {
    [self commitDurationField];
}

- (void)durationStepperChanged:(NSStepper *)sender {
    self.configuration.simulationDuration = round(sender.doubleValue);
    self.durationField.stringValue =
        [NSString stringWithFormat:@"%.0f", self.configuration.simulationDuration];
    [self validateAndNotify];
}

- (void)seedFieldCommitted:(id)sender {
    [self commitSeedField];
}

- (void)controlTextDidEndEditing:(NSNotification *)notification {
    if (notification.object == self.durationField) {
        [self commitDurationField];
    } else if (notification.object == self.seedField) {
        [self commitSeedField];
    }
}

- (void)commitDurationField {
    NSString *trimmed = [self.durationField.stringValue
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSScanner *scanner = [NSScanner scannerWithString:trimmed];
    double value = 0.0;
    if (![scanner scanDouble:&value] || !scanner.isAtEnd ||
        !isfinite(value) || value < 1.0 || value > 3600.0) {
        NSBeep();
        self.durationField.stringValue =
            [NSString stringWithFormat:@"%.0f", self.configuration.simulationDuration];
        return;
    }
    self.configuration.simulationDuration = round(value);
    self.durationField.stringValue =
        [NSString stringWithFormat:@"%.0f", self.configuration.simulationDuration];
    self.durationStepper.doubleValue = self.configuration.simulationDuration;
    [self validateAndNotify];
}

- (void)commitSeedField {
    NSString *trimmed = [self.seedField.stringValue
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (trimmed.length == 0 || [trimmed hasPrefix:@"-"]) {
        NSBeep();
        self.seedField.stringValue =
            [NSString stringWithFormat:@"%llu", self.configuration.randomSeed];
        return;
    }
    char *end = NULL;
    errno = 0;
    unsigned long long value = strtoull(trimmed.UTF8String, &end, 10);
    if (errno != 0 || end == trimmed.UTF8String || *end != '\0') {
        NSBeep();
        self.seedField.stringValue =
            [NSString stringWithFormat:@"%llu", self.configuration.randomSeed];
        return;
    }
    self.configuration.randomSeed = value;
    [self validateAndNotify];
}

- (void)randomizeSeed:(id)sender {
    uint64_t value = 0;
    arc4random_buf(&value, sizeof(value));
    self.configuration.randomSeed = value;
    self.seedField.stringValue = [NSString stringWithFormat:@"%llu", value];
    [self validateAndNotify];
}

- (void)restoreDefaults:(id)sender {
    self.configuration = [MDSDetectorConfiguration defaultConfiguration];
    self.playbackSpeed = 1.0;
    [self syncControlsFromConfiguration];
    [self validateAndNotify];
}

- (void)helpButtonPressed:(id)sender {
    [self.delegate configurationViewControllerDidRequestHelp:self];
}

#pragma mark - Validation and state

- (void)updateShowerDependentControls {
    const BOOL showerEnabled = self.controlsEnabled &&
        self.showerSwitch.state == NSControlStateValueOn;
    for (NSControl *control in self.showerDependentControls) {
        control.enabled = showerEnabled;
    }
    const BOOL configuredAxisEnabled = showerEnabled &&
        self.configuration.arrivalDirectionMode ==
            MDSArrivalDirectionModeVertical;
    for (NSControl *control in self.showerAxisControls) {
        control.enabled = configuredAxisEnabled;
    }
}

- (void)setControlsEnabled:(BOOL)enabled {
    _controlsEnabled = enabled;
    for (NSControl *control in self.allControls) {
        control.enabled = enabled;
    }
    self.restoreDefaultsButton.enabled = enabled;
    [self updateShowerDependentControls];
}

- (void)setConfiguration:(MDSDetectorConfiguration *)configuration {
    _configuration = [configuration copy];
    if (self.isViewLoaded) {
        [self syncControlsFromConfiguration];
        [self validateAndNotify];
    }
}

- (void)validateAndNotify {
    NSError *validationError = nil;
    const BOOL valid = [self.configuration validate:&validationError];
    self.configurationValid = valid;
    if (valid) {
        self.validationLabel.hidden = YES;
        self.validationLabel.stringValue = @"";
        self.validationLabel.toolTip = nil;
    } else {
        self.validationLabel.hidden = NO;
        self.validationLabel.stringValue =
            [NSString stringWithFormat:@"Fix before starting: %@",
             validationError.localizedDescription];
        self.validationLabel.toolTip = validationError.localizedRecoverySuggestion;
    }
    [self updateCoincidenceSummary];
    [self updateCrossSectionLabel];
    [self notifyDelegate];
}

- (void)notifyDelegate {
    if (self.suppressNotifications) {
        return;
    }
    [self.delegate configurationViewController:self
                       didChangeConfiguration:self.configuration
                               validationError:self.configurationValid ? nil :
                               [self currentValidationError]
                                 playbackSpeed:self.playbackSpeed];
}

- (NSError *)currentValidationError {
    NSError *error = nil;
    [self.configuration validate:&error];
    return error;
}

@end

