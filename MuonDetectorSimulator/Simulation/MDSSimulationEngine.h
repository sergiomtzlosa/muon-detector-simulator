#import <Foundation/Foundation.h>

#import "MDSGeometry.h"

NS_ASSUME_NONNULL_BEGIN

@class MDSBatch;
@class MDSDetectorConfiguration;

/// Foundation-only model of a three-tube muon telescope. It owns all event
/// generation, hit timestamps, coincidence matching and summary statistics.
@interface MDSSimulationEngine : NSObject

@property (nonatomic, copy, readonly) MDSDetectorConfiguration *configuration;
@property (nonatomic, assign, readonly) NSTimeInterval currentTime;
@property (nonatomic, assign, readonly) NSTimeInterval simulationDuration;
@property (nonatomic, assign, readonly, getter=isFinished) BOOL finished;
@property (nonatomic, assign, readonly) NSUInteger histogramBinCount;

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithConfiguration:(MDSDetectorConfiguration *)configuration
                                         error:(NSError **)error
    NS_DESIGNATED_INITIALIZER;

/// Restarts the simulation at time zero with the same seed and settings.
- (void)restart;

/// Generates all scheduled events up to an absolute simulated time. The returned
/// batch contains only newly generated events and coincidences.
- (MDSBatch *)advanceToTime:(NSTimeInterval)simulatedTime;

/// Advances to the next scheduled detector event. Use this for single-step mode.
- (MDSBatch *)stepNextEvent;

- (NSUInteger)totalHitCount;
- (NSUInteger)hitCountForTubeAtIndex:(NSInteger)tubeIndex;
- (NSArray<NSNumber *> *)hitCountsPerTube;
- (NSUInteger)cosmicCandidateCount;
- (NSUInteger)showerEventCount;
- (NSUInteger)backgroundEventCount;
- (NSUInteger)acceptedCoincidenceCount;
- (NSUInteger)twoFoldCoincidenceCount;
- (NSUInteger)threeFoldCoincidenceCount;
- (NSUInteger)accidentalCoincidenceCount;
- (NSUInteger)totalParticleCount;

- (double)acceptedCoincidenceRatePerMinute;
- (double)hitRatePerMinute;

- (NSArray<NSNumber *> *)histogramHitCounts;
- (NSArray<NSNumber *> *)histogramCoincidenceCounts;

@end

NS_ASSUME_NONNULL_END
