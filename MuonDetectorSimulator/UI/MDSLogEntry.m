#import "MDSLogEntry.h"

#import "MDSCoincidence.h"
#import "MDSHit.h"
#import "MDSSimulationEvent.h"

NSString *MDSFormatSimulatedTime(NSTimeInterval seconds) {
    const BOOL negative = seconds < 0.0;
    const NSTimeInterval absolute = negative ? -seconds : seconds;
    const NSInteger totalMilliseconds =
        (NSInteger)llround(absolute * 1000.0);
    const NSInteger milliseconds = totalMilliseconds % 1000;
    const NSInteger totalSeconds = totalMilliseconds / 1000;
    const NSInteger secondsPart = totalSeconds % 60;
    const NSInteger minutes = totalSeconds / 60;
    return [NSString stringWithFormat:@"%@%02ld:%02ld.%03ld",
            negative ? @"-" : @"", (long)minutes, (long)secondsPart,
            (long)milliseconds];
}

NSString *MDSFormatHitList(NSArray<MDSHit *> *hits) {
    if (hits.count == 0) {
        return @"No tube hits";
    }
    NSArray<MDSHit *> *sorted = [hits sortedArrayUsingComparator:
        ^NSComparisonResult(MDSHit *first, MDSHit *second) {
            if (first.tubeIndex == second.tubeIndex) {
                return [@(first.timestamp) compare:@(second.timestamp)];
            }
            return first.tubeIndex < second.tubeIndex
                ? NSOrderedAscending : NSOrderedDescending;
        }];

    NSMutableArray<NSString *> *components = [NSMutableArray array];
    for (MDSHit *hit in sorted) {
        [components addObject:
            [NSString stringWithFormat:@"T%ld %@", (long)hit.tubeIndex + 1,
             MDSFormatSimulatedTime(hit.timestamp)]];
    }
    return [components componentsJoinedByString:@"  ·  "];
}

@implementation MDSLogEntry

- (instancetype)initWithTimestamp:(NSTimeInterval)timestamp
                         timeText:(NSString *)timeText
                       sourceText:(NSString *)sourceText
                      detailsText:(NSString *)detailsText
                       resultText:(NSString *)resultText
                            style:(MDSLogEntryStyle)style {
    self = [super init];
    if (self) {
        _timestamp = timestamp;
        _timeText = [timeText copy];
        _sourceText = [sourceText copy];
        _detailsText = [detailsText copy];
        _resultText = [resultText copy];
        _style = style;
    }
    return self;
}

+ (instancetype)entryForEvent:(MDSSimulationEvent *)event {
    NSString *source = @"Cosmic ray";
    MDSLogEntryStyle style = MDSLogEntryStyleParticle;
    if (event.kind == MDSSimulationEventKindShower) {
        source = [NSString stringWithFormat:@"Shower · %ld particles",
                  (long)event.particleCount];
    } else if (event.kind == MDSSimulationEventKindBackground) {
        source = @"Background";
        style = MDSLogEntryStyleBackground;
    }

    NSString *result = nil;
    if (event.kind == MDSSimulationEventKindBackground) {
        result = @"Single pulse";
    } else if (event.hits.count == 0) {
        result = @"No tube hits";
    } else {
        result = [NSString stringWithFormat:@"%lu hit%@",
                  (unsigned long)event.hits.count,
                  event.hits.count == 1 ? @"" : @"s"];
    }

    return [[self alloc] initWithTimestamp:event.timestamp
                                  timeText:MDSFormatSimulatedTime(event.timestamp)
                                sourceText:source
                               detailsText:MDSFormatHitList(event.hits)
                                resultText:result
                                     style:style];
}

+ (instancetype)entryForCoincidence:(MDSCoincidence *)coincidence {
    NSMutableArray<NSString *> *tubeNames = [NSMutableArray array];
    for (NSNumber *tubeIndex in coincidence.tubeIndices) {
        [tubeNames addObject:[NSString stringWithFormat:@"Tube %ld",
                              (long)tubeIndex.integerValue + 1]];
    }
    NSMutableArray<NSString *> *hitTimes = [NSMutableArray array];
    for (MDSHit *hit in coincidence.hits) {
        [hitTimes addObject:MDSFormatSimulatedTime(hit.timestamp)];
    }
    NSString *source = coincidence.isAccidental
        ? @"Coincidence · accidental" : @"Coincidence";
    NSString *details = [NSString stringWithFormat:@"%@ · %@",
                         [tubeNames componentsJoinedByString:@" + "],
                         [hitTimes componentsJoinedByString:@" / "]];
    NSString *result = [NSString stringWithFormat:@"%ld-fold accepted",
                        (long)coincidence.fold];
    return [[self alloc] initWithTimestamp:coincidence.timestamp
                                  timeText:MDSFormatSimulatedTime(coincidence.timestamp)
                                sourceText:source
                               detailsText:details
                                resultText:result
                                     style:MDSLogEntryStyleCoincidence];
}

@end
​​​​​​​​​​​