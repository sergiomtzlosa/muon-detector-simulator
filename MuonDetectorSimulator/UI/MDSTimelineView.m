#import "MDSTimelineView.h"

@implementation MDSTimelineView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _hitCounts = @[];
        _coincidenceCounts = @[];
        _simulationDuration = 60.0;
        [self setAccessibilityElement:YES];
        [self setAccessibilityRole:NSAccessibilityImageRole];
        [self setAccessibilityLabel:@"Detector activity timeline"];
        self.toolTip = @"Simulated tube hits and accepted coincidences over time.";
    }
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

- (void)setHitCounts:(NSArray<NSNumber *> *)hitCounts {
    _hitCounts = [hitCounts copy] ?: @[];
    [self setNeedsDisplay:YES];
}

- (void)setCoincidenceCounts:(NSArray<NSNumber *> *)coincidenceCounts {
    _coincidenceCounts = [coincidenceCounts copy] ?: @[];
    [self setNeedsDisplay:YES];
}

- (void)setCurrentTime:(NSTimeInterval)currentTime {
    _currentTime = currentTime;
    [self setNeedsDisplay:YES];
}

- (void)setSimulationDuration:(NSTimeInterval)simulationDuration {
    _simulationDuration = MAX(1.0, simulationDuration);
    [self setNeedsDisplay:YES];
}

- (void)updateAccessibilitySummary {
    NSUInteger totalHits = 0;
    for (NSNumber *count in self.hitCounts) {
        totalHits += count.unsignedIntegerValue;
    }
    NSUInteger totalCoincidences = 0;
    for (NSNumber *count in self.coincidenceCounts) {
        totalCoincidences += count.unsignedIntegerValue;
    }
    [self setAccessibilityValue:
        [NSString stringWithFormat:
            @"%lu simulated tube hits and %lu accepted coincidences across %.0f seconds.",
            (unsigned long)totalHits, (unsigned long)totalCoincidences,
            self.simulationDuration]];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    NSRect bounds = self.bounds;
    const CGFloat insetLeft = 12.0;
    const CGFloat insetRight = 12.0;
    const CGFloat insetTop = 8.0;
    const CGFloat insetBottom = 18.0;
    NSRect plotRect = NSMakeRect(NSMinX(bounds) + insetLeft,
                                 NSMinY(bounds) + insetTop,
                                 MAX(0.0, NSWidth(bounds) - insetLeft - insetRight),
                                 MAX(0.0, NSHeight(bounds) - insetTop - insetBottom));
    if (plotRect.size.width < 20.0 || plotRect.size.height < 20.0) {
        return;
    }

    const CGFloat laneGap = 4.0;
    const CGFloat hitsLaneHeight = floor((NSHeight(plotRect) - laneGap) * 0.64);
    const CGFloat coincidenceLaneHeight =
        NSHeight(plotRect) - hitsLaneHeight - laneGap;
    NSRect hitsLane = NSMakeRect(NSMinX(plotRect), NSMinY(plotRect),
                                 NSWidth(plotRect), hitsLaneHeight);
    NSRect coincidenceLane = NSMakeRect(NSMinX(plotRect),
                                        NSMaxY(hitsLane) + laneGap,
                                        NSWidth(plotRect), coincidenceLaneHeight);

    [[NSColor colorWithWhite:0.965 alpha:1.0] setFill];
    NSRectFill(hitsLane);
    NSRectFill(coincidenceLane);

    [[NSColor colorWithWhite:0.88 alpha:1.0] setStroke];
    NSBezierPath *grid = [NSBezierPath bezierPath];
    [grid setLineWidth:0.5];
    for (NSInteger index = 0; index <= 4; index++) {
        const CGFloat fraction = (CGFloat)index / 4.0;
        const CGFloat x = NSMinX(plotRect) + fraction * NSWidth(plotRect);
        [grid moveToPoint:NSMakePoint(x, NSMinY(plotRect))];
        [grid lineToPoint:NSMakePoint(x, NSMaxY(plotRect))];
    }
    [grid stroke];

    const NSUInteger binCount = MAX(self.hitCounts.count,
                                    MAX(self.coincidenceCounts.count, 1));
    const CGFloat binWidth = NSWidth(plotRect) / (CGFloat)binCount;

    NSUInteger maximumHits = 1;
    for (NSNumber *count in self.hitCounts) {
        maximumHits = MAX(maximumHits, count.unsignedIntegerValue);
    }
    NSUInteger maximumCoincidences = 1;
    for (NSNumber *count in self.coincidenceCounts) {
        maximumCoincidences = MAX(maximumCoincidences,
                                  count.unsignedIntegerValue);
    }

    NSColor *hitColor = [NSColor colorWithSRGBRed:0.29 green:0.49 blue:0.66 alpha:0.72];
    NSColor *coincidenceColor = [NSColor colorWithSRGBRed:0.16 green:0.58 blue:0.35 alpha:0.82];

    for (NSUInteger index = 0; index < self.hitCounts.count; index++) {
        const NSUInteger count = self.hitCounts[index].unsignedIntegerValue;
        if (count == 0) {
            continue;
        }
        const CGFloat fraction = (CGFloat)count / (CGFloat)maximumHits;
        const CGFloat height = MAX(1.0, fraction * (NSHeight(hitsLane) - 2.0));
        NSRect bar = NSMakeRect(NSMinX(hitsLane) + (CGFloat)index * binWidth + 0.3,
                                NSMaxY(hitsLane) - height - 1.0,
                                MAX(1.0, binWidth - 0.6),
                                height);
        [hitColor setFill];
        NSRectFillUsingOperation(bar, NSCompositingOperationSourceOver);
    }

    for (NSUInteger index = 0; index < self.coincidenceCounts.count; index++) {
        const NSUInteger count = self.coincidenceCounts[index].unsignedIntegerValue;
        if (count == 0) {
            continue;
        }
        const CGFloat fraction = (CGFloat)count / (CGFloat)maximumCoincidences;
        const CGFloat height = MAX(2.0,
                                   fraction * (NSHeight(coincidenceLane) - 2.0));
        NSRect bar = NSMakeRect(NSMinX(coincidenceLane) + (CGFloat)index * binWidth + 0.3,
                                NSMaxY(coincidenceLane) - height - 1.0,
                                MAX(1.0, binWidth - 0.6),
                                height);
        [coincidenceColor setFill];
        NSRectFillUsingOperation(bar, NSCompositingOperationSourceOver);
    }

    if (self.simulationDuration > 0.0) {
        const double progress = MIN(1.0, MAX(0.0, self.currentTime / self.simulationDuration));
        const CGFloat x = NSMinX(plotRect) + (CGFloat)progress * NSWidth(plotRect);
        NSBezierPath *playhead = [NSBezierPath bezierPath];
        playhead.lineWidth = 1.0;
        [[NSColor colorWithWhite:0.35 alpha:0.35] setStroke];
        [playhead moveToPoint:NSMakePoint(x, NSMinY(plotRect))];
        [playhead lineToPoint:NSMakePoint(x, NSMaxY(plotRect))];
        [playhead stroke];
    }

    NSDictionary<NSAttributedStringKey, id> *attributes = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:9
                                                              weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: [NSColor secondaryLabelColor],
    };
    NSString *start = @"0 s";
    NSString *middle = [NSString stringWithFormat:@"%.0f s",
                        self.simulationDuration * 0.5];
    NSString *end = [NSString stringWithFormat:@"%.0f s", self.simulationDuration];
    [start drawAtPoint:NSMakePoint(NSMinX(plotRect), NSMaxY(bounds) - 14.0)
        withAttributes:attributes];
    NSSize middleSize = [middle sizeWithAttributes:attributes];
    [middle drawAtPoint:NSMakePoint(NSMidX(plotRect) - middleSize.width * 0.5,
                                    NSMaxY(bounds) - 14.0)
        withAttributes:attributes];
    NSSize endSize = [end sizeWithAttributes:attributes];
    [end drawAtPoint:NSMakePoint(NSMaxX(plotRect) - endSize.width,
                                 NSMaxY(bounds) - 14.0)
        withAttributes:attributes];

    BOOL hasAnyActivity = NO;
    for (NSNumber *count in self.hitCounts) {
        if (count.unsignedIntegerValue > 0) {
            hasAnyActivity = YES;
            break;
        }
    }
    if (!hasAnyActivity) {
        NSDictionary<NSAttributedStringKey, id> *emptyAttributes = @{
            NSFontAttributeName: [NSFont systemFontOfSize:10],
            NSForegroundColorAttributeName: [NSColor tertiaryLabelColor],
        };
        NSString *message = @"No simulated activity yet";
        NSSize messageSize = [message sizeWithAttributes:emptyAttributes];
        [message drawAtPoint:NSMakePoint(NSMidX(plotRect) - messageSize.width * 0.5,
                                         NSMidY(plotRect) - messageSize.height * 0.5)
              withAttributes:emptyAttributes];
    }
}

@end



