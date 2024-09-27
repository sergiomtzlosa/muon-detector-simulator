#import "MDSHowItWorksWindowController.h"

@implementation MDSHowItWorksWindowController

- (instancetype)init {
    NSWindow *window =
        [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 760, 680)
                                    styleMask:(NSWindowStyleMaskTitled |
                                               NSWindowStyleMaskClosable |
                                               NSWindowStyleMaskResizable)
                                      backing:NSBackingStoreBuffered
                                        defer:NO];
    window.title = @"How It Works";
    window.minSize = NSMakeSize(560, 460);
    window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    window.releasedWhenClosed = NO;
    window.backgroundColor = [NSColor whiteColor];

    self = [super initWithWindow:window];
    if (self) {
        [self buildInterface];
        [window center];
    }
    return self;
}

- (void)buildInterface {
    NSView *contentView = self.window.contentView;
    contentView.wantsLayer = YES;
    contentView.layer.backgroundColor = [NSColor whiteColor].CGColor;

    NSTextField *title = [self labelWithText:@"How the simulation works"
                                        font:[NSFont systemFontOfSize:22
                                                              weight:NSFontWeightSemibold]
                                       color:[NSColor labelColor]];
    NSTextField *subtitle = [self labelWithText:
        @"A three-tube Geiger–Müller telescope, modeled in software."
                                            font:[NSFont systemFontOfSize:12]
                                           color:[NSColor secondaryLabelColor]];

    NSView *disclaimer = [[NSView alloc] initWithFrame:NSZeroRect];
    disclaimer.translatesAutoresizingMaskIntoConstraints = NO;
    disclaimer.wantsLayer = YES;
    disclaimer.layer.backgroundColor =
        [NSColor colorWithSRGBRed:0.991 green:0.949 blue:0.882 alpha:1.0].CGColor;
    disclaimer.layer.cornerRadius = 6.0;
    disclaimer.layer.borderWidth = 1.0;
    disclaimer.layer.borderColor =
        [NSColor colorWithSRGBRed:0.941 green:0.843 blue:0.639 alpha:1.0].CGColor;

    NSImageView *warningIcon = [[NSImageView alloc] initWithFrame:NSZeroRect];
    warningIcon.image = [NSImage imageWithSystemSymbolName:@"exclamationmark.triangle.fill"
                                  accessibilityDescription:@"Important"];
    warningIcon.contentTintColor = [NSColor systemOrangeColor];
    warningIcon.translatesAutoresizingMaskIntoConstraints = NO;
    [disclaimer addSubview:warningIcon];

    NSTextField *disclaimerText = [self labelWithText:
        @"This is an educational simulation only. It does not measure radiation, "
        @"identify particles, or communicate with real detector hardware."
                                                    font:[NSFont systemFontOfSize:11.5
                                                                          weight:NSFontWeightMedium]
                                                   color:[NSColor labelColor]];
    disclaimerText.maximumNumberOfLines = 0;
    disclaimerText.lineBreakMode = NSLineBreakByWordWrapping;
    disclaimerText.preferredMaxLayoutWidth = 620.0;
    disclaimerText.translatesAutoresizingMaskIntoConstraints = NO;
    [disclaimer addSubview:disclaimerText];

    [NSLayoutConstraint activateConstraints:@[
        [warningIcon.leadingAnchor constraintEqualToAnchor:disclaimer.leadingAnchor constant:11.0],
        [warningIcon.topAnchor constraintEqualToAnchor:disclaimer.topAnchor constant:10.0],
        [warningIcon.widthAnchor constraintEqualToConstant:15.0],
        [warningIcon.heightAnchor constraintEqualToConstant:15.0],
        [disclaimerText.leadingAnchor constraintEqualToAnchor:warningIcon.trailingAnchor constant:8.0],
        [disclaimerText.trailingAnchor constraintEqualToAnchor:disclaimer.trailingAnchor constant:-11.0],
        [disclaimerText.topAnchor constraintEqualToAnchor:disclaimer.topAnchor constant:8.0],
        [disclaimerText.bottomAnchor constraintEqualToAnchor:disclaimer.bottomAnchor constant:-9.0],
    ]];

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.hasVerticalScroller = YES;
    scrollView.autohidesScrollers = YES;
    scrollView.drawsBackground = NO;
    scrollView.borderType = NSNoBorder;
    scrollView.horizontalScrollElasticity = NSScrollElasticityNone;

    NSTextView *textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 700, 400)];
    textView.editable = NO;
    textView.selectable = YES;
    textView.richText = YES;
    textView.drawsBackground = NO;
    textView.textContainerInset = NSMakeSize(24.0, 16.0);
    textView.minSize = NSMakeSize(0, 0);
    textView.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    textView.verticallyResizable = YES;
    textView.horizontallyResizable = NO;
    textView.autoresizingMask = NSViewWidthSizable;
    textView.textContainer.widthTracksTextView = YES;
    textView.textContainer.containerSize = NSMakeSize(700.0, CGFLOAT_MAX);
    textView.accessibilityLabel = @"How the simulation works";
    [textView.textStorage setAttributedString:[self explanatoryContent]];
    scrollView.documentView = textView;

    NSButton *closeButton = [NSButton buttonWithTitle:@"Close"
                                               target:self
                                               action:@selector(closeWindow:)];
    closeButton.bezelStyle = NSBezelStyleRounded;
    closeButton.keyEquivalent = @"\e";
    closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    closeButton.accessibilityLabel = @"Close How It Works";

    NSTextField *footer = [self labelWithText:
        @"Muon Detector Simulator · educational model · no hardware connection"
                                           font:[NSFont systemFontOfSize:10.5]
                                          color:[NSColor tertiaryLabelColor]];

    NSBox *footerSeparator = [[NSBox alloc] initWithFrame:NSZeroRect];
    footerSeparator.boxType = NSBoxSeparator;
    footerSeparator.translatesAutoresizingMaskIntoConstraints = NO;

    [contentView addSubview:title];
    [contentView addSubview:subtitle];
    [contentView addSubview:disclaimer];
    [contentView addSubview:scrollView];
    [contentView addSubview:footerSeparator];
    [contentView addSubview:footer];
    [contentView addSubview:closeButton];

    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:20.0],
        [title.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:24.0],
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:contentView.trailingAnchor constant:-24.0],
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:3.0],
        [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [subtitle.trailingAnchor constraintLessThanOrEqualToAnchor:contentView.trailingAnchor constant:-24.0],
        [disclaimer.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:13.0],
        [disclaimer.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:24.0],
        [disclaimer.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-24.0],
        [scrollView.topAnchor constraintEqualToAnchor:disclaimer.bottomAnchor constant:10.0],
        [scrollView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:2.0],
        [scrollView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-2.0],
        [scrollView.bottomAnchor constraintEqualToAnchor:footerSeparator.topAnchor constant:-6.0],
        [footerSeparator.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:24.0],
        [footerSeparator.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-24.0],
        [footerSeparator.bottomAnchor constraintEqualToAnchor:closeButton.topAnchor constant:-10.0],
        [footer.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:24.0],
        [footer.centerYAnchor constraintEqualToAnchor:closeButton.centerYAnchor],
        [footer.trailingAnchor constraintLessThanOrEqualToAnchor:closeButton.leadingAnchor constant:-12.0],
        [closeButton.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-22.0],
        [closeButton.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-16.0],
        [closeButton.widthAnchor constraintGreaterThanOrEqualToConstant:82.0],
    ]];
}

- (void)closeWindow:(id)sender {
    [self close];
}

#pragma mark - Attributed content

- (NSAttributedString *)explanatoryContent {
    NSMutableAttributedString *content = [[NSMutableAttributedString alloc] init];

    [self appendHeading:@"A model, not a measuring instrument" to:content];
    [self appendParagraph:
        @"The application simulates a small stack of three Geiger–Müller (GM) tubes. "
        @"Candidate cosmic rays are generated from a seeded random process, traced through "
        @"cylindrical active volumes, and converted into timestamped electronic pulses. "
        @"Every number on screen comes from this model. Nothing is read from a physical "
        @"detector, and the displayed rates are not calibrated environmental measurements."
                          to:content];

    [self appendHeading:@"Cosmic rays and muons" to:content];
    [self appendParagraph:
        @"High-energy particles from space strike the atmosphere and create cascades of "
        @"secondary particles. Charged muons are among the particles that commonly reach "
        @"the ground. A muon is ionizing, so crossing a gas-filled detector can leave a "
        @"small trail of ion pairs. The simulation refers to the incoming candidate as a "
        @"muon because that is the usual signal in a ground-level cosmic-ray telescope."
                          to:content];

    [self appendHeading:@"What a Geiger–Müller tube does" to:content];
    [self appendParagraph:
        @"A GM tube contains gas and electrodes held at high voltage. Ionization can start "
        @"an avalanche that produces a short electrical pulse. This model represents each "
        @"tube's active gas volume as a finite cylinder and draws rays through it. A "
        @"crossing becomes a pulse only if an independent efficiency trial succeeds. The "
        @"model does not produce a pulse-height measurement and cannot determine a "
        @"particle's mass, charge, identity, or energy."
                          to:content];

    [self appendHeading:@"Why three tubes use coincidence" to:content];
    [self appendParagraph:
        @"Background pulses arise from natural radioactivity, electronics, and other "
        @"sources. Requiring pulses in two or all three tubes within a short time window "
        @"rejects most unrelated singles. A particle traveling through the stack can "
        @"register in the selected tubes closely enough in time to be accepted. A 3-fold "
        @"requirement is more selective than a 2-fold pair, but neither proves the particle "
        @"was a muon. The event log reports the accepted multiplicity and marks sets formed "
        @"from more than one source or background pulses as accidental."
                          to:content];

    [self appendHeading:@"What the simulation models" to:content];
    [self appendBullet:@"Finite cylindrical active volumes, ray/cylinder intersection, and "
        @"a separate detection efficiency for each tube."
                    to:content];
    [self appendBullet:@"Poisson candidate arrivals. The default normal mode uses a "
        @"simplified vertical direction; random realistic mode samples a new downward "
        @"primary axis with a cos²θ weighting up to 80° from vertical. Random candidates "
        @"are accepted only when the ray can cross every selected tube, so a 3-fold stack "
        @"has a narrow geometric acceptance. Shower mode spreads a uniform cone around "
        @"either the configured or sampled axis."
                    to:content];
    [self appendBullet:@"Random directions are seeded: the same seed and settings reproduce "
        @"the same sequence. In random shower mode the sampled axis is limited so the "
        @"whole cone stays below horizontal."
                    to:content];
    [self appendBullet:@"Independent Poisson background pulses at each tube, applied as an "
        @"observed pulse rate."
                    to:content];
    [self appendBullet:@"Gaussian timing jitter with a fixed standard deviation of 0.025 µs "
        @"(clipped at three standard deviations) on particle pulses."
                    to:content];
    [self appendBullet:@"A coincidence scan across selected tubes. On each new pulse, the "
        @"engine searches backward within the chosen window, accepts a complete set if "
        @"possible, and consumes those pulses so each one contributes at most once."
                    to:content];
    [self appendBullet:@"A reproducible seeded random sequence, histogram bins, per-tube hit "
        @"totals, and accepted 2-fold/3-fold counts."
                    to:content];
    [self appendBullet:@"Presentation-only track controls: a particle-type filter, a labels "
        @"toggle, and an optional fade for recent particle tracks. None changes the "
        @"model or the exported counts."
                    to:content];

    [self appendHeading:@"Deliberate simplifications" to:content];
    [self appendBullet:@"No dead time, recovery time, afterpulsing, threshold variation, "
        @"pulse shape, amplifier response, or high-voltage behavior."
                    to:content];
    [self appendBullet:@"No detailed particle transport, energy loss, multiple scattering, "
        @"track reconstruction, or material geometry. A track is a straight ray."
                    to:content];
    [self appendBullet:@"A shower is a set of straight rays sampled in a cone. It is not a "
        @"full atmospheric cascade, and its multiplicity is a user assumption rather than "
        @"a prediction."
                    to:content];
    [self appendBullet:@"The cosmic event rate is an adjustable candidate-arrival rate aimed "
        @"through the selected tube volumes. It is not a calibrated muon flux and does not "
        @"include altitude, weather, geomagnetic latitude, east-west asymmetry, or a "
        @"calibrated detector acceptance. The random cos²θ direction model is a teaching "
        @"approximation, capped at 80° from vertical and filtered by the selected-tube "
        @"geometry."
                    to:content];
    [self appendBullet:@"Background pulses are abstract Poisson noise. Environmental "
        @"spectra and real shielding are not modeled."
                    to:content];
    [self appendBullet:@"No real electronics are controlled. The app makes no claim to "
        @"measure radiation or to protect anyone from it."
                    to:content];

    [self appendHeading:@"Units and reproducibility" to:content];
    [self appendParagraph:
        @"Lengths are in centimetres, simulated time and hit timestamps are in seconds, "
        @"coincidence windows are shown in microseconds, background is pulses per second "
        @"per tube, and the candidate cosmic rate is events per simulated minute. The "
        @"displayed coincidence rate is accepted coincidences divided by elapsed simulated "
        @"time. Because the event generator is seeded, the same seed and settings produce "
        @"the same event sequence. Playback speed changes only how fast that sequence is "
        @"shown; Step advances through the same sequence one event at a time."
                          to:content];

    [self appendHeading:@"Reading the display" to:content];
    [self appendParagraph:
        @"Green tracks are particle events that participated in an accepted coincidence. "
        @"Amber tracks did not; violet tracks are shower particles, with a green halo when "
        @"the shower produced an accepted set. With Fade tracks enabled (the default), "
        @"every recent particle track remains visible and then fades out. Shower tracks "
        @"linger longer than single muon candidates so the full fan can be inspected; "
        @"accepted tracks keep their green styling during the hold. Turn the option off to keep "
        @"tracks on screen. The event log includes per-hit timestamps, and the two-lane "
        @"timeline shows all tube hits above accepted coincidences. The Particles menu "
        @"filters only the recent 3D tracks (all, muon candidates, or shower particles); "
        @"neither the filter nor fading changes the simulation, counts, histogram, or "
        @"event log."
                          to:content];
    [self appendParagraph:
        @"The 3D view shows three crystal-style GM tubes in a removable display shield. "
        @"Use the shield button to remove or replace the clear cover and inspect the tubes; "
        @"this changes only the presentation, not the simulation. A localized electric spark marks a "
        @"simulated tube pulse: green for an accepted coincidence, cyan for another particle "
        @"hit, and a faint blue flash for a background pulse. Sparks are illustrative "
        @"annotations, not reconstructed interaction positions."
                          to:content];

    [self appendHeading:@"Saving a report" to:content];
    [self appendParagraph:
        @"The Export JSON button in the Results header (or File > Export Results as JSON) "
        @"writes a structured JSON snapshot of the current run. File > Export Results as "
        @"CSV writes the same data as a spreadsheet-friendly CSV file. Both formats include "
        @"the model settings, seed, summary counts, per-tube totals, histogram bins, and the "
        @"retained event log. The log is capped at 3,000 most recent rows for display, while "
        @"the summary counts and histogram remain complete. The file carries the same "
        @"simulation-only disclaimer and is not a measurement record."
                          to:content];

    [self appendHeading:@"Limits of coincidence" to:content];
    [self appendParagraph:
        @"Coincidence greatly reduces random singles, but it does not establish that a "
        @"particle is a muon, nor does it measure its energy or mass. An accidental overlap, "
        @"a shower particle crossing the stack, or unrelated background within the window "
        @"can satisfy the condition. Increasing the window raises accidental acceptance; "
        @"lowering it can reject genuine hits because of timing jitter. The simulator is "
        @"intended to invite that trade-off, not to claim a calibrated result."
                          to:content];

    [self appendHeading:@"Important disclaimer" to:content];
    [self appendParagraph:
        @"This application is an educational simulation. It does not measure radiation and "
        @"cannot be used for safety, dosimetry, medical, or scientific measurements. All "
        @"detector behavior and rates are modeled assumptions, not observations."
                          to:content];

    return content;
}

- (NSMutableParagraphStyle *)bodyParagraphStyle {
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.lineSpacing = 3.0;
    style.paragraphSpacing = 7.0;
    return style;
}

- (void)appendHeading:(NSString *)heading to:(NSMutableAttributedString *)content {
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.paragraphSpacingBefore = 15.0;
    style.paragraphSpacing = 4.0;
    NSAttributedString *piece = [[NSAttributedString alloc] initWithString:
        [heading stringByAppendingString:@"\n"]
        attributes:@{
            NSFontAttributeName: [NSFont systemFontOfSize:14.5
                                                   weight:NSFontWeightSemibold],
            NSForegroundColorAttributeName: [NSColor labelColor],
            NSParagraphStyleAttributeName: style,
        }];
    [content appendAttributedString:piece];
}

- (void)appendParagraph:(NSString *)paragraph to:(NSMutableAttributedString *)content {
    NSAttributedString *piece = [[NSAttributedString alloc] initWithString:
        [paragraph stringByAppendingString:@"\n"]
        attributes:@{
            NSFontAttributeName: [NSFont systemFontOfSize:12.5],
            NSForegroundColorAttributeName: [NSColor labelColor],
            NSParagraphStyleAttributeName: [self bodyParagraphStyle],
        }];
    [content appendAttributedString:piece];
}

- (void)appendBullet:(NSString *)bullet to:(NSMutableAttributedString *)content {
    NSMutableParagraphStyle *style = [self bodyParagraphStyle];
    style.firstLineHeadIndent = 4.0;
    style.headIndent = 18.0;
    style.paragraphSpacing = 4.0;
    NSAttributedString *piece = [[NSAttributedString alloc] initWithString:
        [NSString stringWithFormat:@"•  %@\n", bullet]
        attributes:@{
            NSFontAttributeName: [NSFont systemFontOfSize:12.5],
            NSForegroundColorAttributeName: [NSColor labelColor],
            NSParagraphStyleAttributeName: style,
        }];
    [content appendAttributedString:piece];
}

- (NSTextField *)labelWithText:(NSString *)text
                          font:(NSFont *)font
                         color:(NSColor *)color {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = font;
    label.textColor = color;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

@end
​​​​​​​​