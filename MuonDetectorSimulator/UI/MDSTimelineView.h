#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// Compact two-lane activity histogram. The upper lane shows all tube hits; the
/// lower lane shows accepted coincidences. Both use the same simulated-time axis.
@interface MDSTimelineView : NSView

@property (nonatomic, copy) NSArray<NSNumber *> *hitCounts;
@property (nonatomic, copy) NSArray<NSNumber *> *coincidenceCounts;
@property (nonatomic, assign) NSTimeInterval simulationDuration;
@property (nonatomic, assign) NSTimeInterval currentTime;

- (void)updateAccessibilitySummary;

@end

NS_ASSUME_NONNULL_END



