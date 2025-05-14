#import "MDSSimulationEngine.h"

#import <float.h>

#import "MDSBatch.h"
#import "MDSCoincidence.h"
#import "MDSDetectorConfiguration.h"
#import "MDSHit.h"
#import "MDSRandom.h"
#import "MDSSimulationEvent.h"
#import "MDSTrack.h"
#import "MDSTube.h"

static const double MDSTimingJitterSigmaSeconds = 0.025e-6;
static const double MDSTrackVisualHalfLength = 22.0;
static const NSUInteger MDSDefaultHistogramBinCount = 120;
static const double MDSRandomArrivalMaximumZenithDegrees = 80.0;
static const double MDSMaximumDownwardAngleDegrees = 85.0;
static const NSUInteger MDSRandomDirectionMaximumAttempts = 10000;
static const double MDSGeometryTolerance = 1.0e-9;

/// Samples a downward primary direction with a cos²θ angular distribution. The
/// distribution is truncated at the supplied maximum zenith angle so a shower
/// cone can be kept below the horizon. Two PRNG draws are consumed per event.
static MDSVector3 MDSRandomRealisticDownwardDirection(MDSRandom *random,
                                                       double maximumZenithDegrees,
                                                       double *zenithDegrees,
                                                       double *azimuthDegrees) {
    const double maxZenith = MIN(MAX(maximumZenithDegrees, 0.0),
                                 MDSRandomArrivalMaximumZenithDegrees);
    const double cosMaximum =
        cos(maxZenith * M_PI / 180.0);
    const double minCube = cosMaximum * cosMaximum * cosMaximum;
    const double cosZenith =
        cbrt(minCube + [random nextUniform] * (1.0 - minCube));
    const double clampedCosZenith = MIN(1.0, MAX(0.0, cosZenith));
    const double sinZenith =
        sqrt(MAX(0.0, 1.0 - clampedCosZenith * clampedCosZenith));
    const double azimuth = [random nextUniform] * 2.0 * M_PI;

    if (zenithDegrees != NULL) {
        *zenithDegrees = acos(clampedCosZenith) * 180.0 / M_PI;
    }
    if (azimuthDegrees != NULL) {
        *azimuthDegrees = azimuth * 180.0 / M_PI;
    }

    return MDSVector3Normalized(MDSVector3Make(sinZenith * cos(azimuth),
                                               -clampedCosZenith,
                                               sinZenith * sin(azimuth)));
}

static MDSVector3 MDSRandomDirectionAroundAxis(MDSRandom *random,
                                               MDSVector3 axis,
                                               double maximumAngleRadians) {
    const MDSVector3 normalizedAxis = MDSVector3Normalized(axis);
    if (maximumAngleRadians <= 0.0) {
        return normalizedAxis;
    }

    MDSVector3 reference = fabs(normalizedAxis.y) < 0.9
        ? MDSVector3Make(0.0, 1.0, 0.0)
        : MDSVector3Make(1.0, 0.0, 0.0);
    MDSVector3 tangent = MDSVector3Normalized(
        MDSVector3Cross(reference, normalizedAxis));
    MDSVector3 bitangent = MDSVector3Normalized(
        MDSVector3Cross(normalizedAxis, tangent));

    // Uniform sampling in a cone: sample cos(theta) uniformly between the cone
    // edge and its axis, then choose a uniformly distributed azimuth.
    const double cosMaximum = cos(maximumAngleRadians);
    const double cosAngle = 1.0 -
        [random nextUniform] * (1.0 - cosMaximum);
    const double sinAngle = sqrt(MAX(0.0, 1.0 - cosAngle * cosAngle));
    const double azimuth = [random nextUniform] * 2.0 * M_PI;

    MDSVector3 direction = MDSVector3Add(
        MDSVector3Multiply(normalizedAxis, cosAngle),
        MDSVector3Add(
            MDSVector3Multiply(tangent, cos(azimuth) * sinAngle),
            MDSVector3Multiply(bitangent, sin(azimuth) * sinAngle)));
    direction = MDSVector3Normalized(direction);

    // The validation layer keeps the cone below the horizon. This guard handles
    // floating-point edge cases without allowing an upward-going cosmic ray.
    if (direction.y > -0.01) {
        direction.y = -fabs(direction.y) - 0.01;
        direction = MDSVector3Normalized(direction);
    }
    return direction;
}

/// Returns the range of target positions in the y = 0 plane whose straight line
/// along `direction` crosses every required tube. A target line can be written as
/// x(y) = x0 + y * dx/dy and z(y) = z0 + y * dz/dy; intersecting each tube's
/// projected active rectangle leaves independent intervals for x0 and z0.
static BOOL MDSDirectionCrossingIntervals(MDSVector3 direction,
                                          NSArray<MDSTube *> *tubes,
                                          NSUInteger requiredTubeMask,
                                          double *targetXMinimum,
                                          double *targetXMaximum,
                                          double *targetZMinimum,
                                          double *targetZMaximum) {
    if (direction.y >= -MDSGeometryTolerance) {
        return NO;
    }

    const double slopeX = direction.x / direction.y;
    const double slopeZ = direction.z / direction.y;
    BOOL hasInterval = NO;
    double xMinimum = -DBL_MAX;
    double xMaximum = DBL_MAX;
    double zMinimum = -DBL_MAX;
    double zMaximum = DBL_MAX;

    for (MDSTube *tube in tubes) {
        if ((requiredTubeMask & ((NSUInteger)1u << tube.tubeIndex)) == 0) {
            continue;
        }

        const double y = tube.center.y;
        const double halfLength = tube.length * 0.5;
        const double xOffset = y * slopeX;
        const double candidateXMinimum = -halfLength - xOffset;
        const double candidateXMaximum = halfLength - xOffset;
        const double zOffset = y * slopeZ;
        const double candidateZMinimum = tube.center.z - tube.radius - zOffset;
        const double candidateZMaximum = tube.center.z + tube.radius - zOffset;

        if (!hasInterval) {
            xMinimum = candidateXMinimum;
            xMaximum = candidateXMaximum;
            zMinimum = candidateZMinimum;
            zMaximum = candidateZMaximum;
            hasInterval = YES;
        } else {
            xMinimum = MAX(xMinimum, candidateXMinimum);
            xMaximum = MIN(xMaximum, candidateXMaximum);
            zMinimum = MAX(zMinimum, candidateZMinimum);
            zMaximum = MIN(zMaximum, candidateZMaximum);
        }

        if (xMinimum > xMaximum + MDSGeometryTolerance ||
            zMinimum > zMaximum + MDSGeometryTolerance) {
            return NO;
        }
    }

    if (!hasInterval) {
        return NO;
    }

    if (targetXMinimum != NULL) {
        *targetXMinimum = xMinimum;
    }
    if (targetXMaximum != NULL) {
        *targetXMaximum = xMaximum;
    }
    if (targetZMinimum != NULL) {
        *targetZMinimum = zMinimum;
    }
    if (targetZMaximum != NULL) {
        *targetZMaximum = zMaximum;
    }
    return YES;
}

static BOOL MDSRandomTargetCrossingTubes(MDSRandom *random,
                                         NSArray<MDSTube *> *tubes,
                                         NSUInteger requiredTubeMask,
                                         MDSVector3 direction,
                                         MDSVector3 *target) {
    double xMinimum = 0.0;
    double xMaximum = 0.0;
    double zMinimum = 0.0;
    double zMaximum = 0.0;
    if (!MDSDirectionCrossingIntervals(direction, tubes, requiredTubeMask,
                                       &xMinimum, &xMaximum,
                                       &zMinimum, &zMaximum)) {
        return NO;
    }

    if (target != NULL) {
        *target = MDSVector3Make(
            [random uniformFrom:xMinimum to:xMaximum], 0.0,
            [random uniformFrom:zMinimum to:zMaximum]);
    }
    return YES;
}

static double MDSRequiredTubeCenterSlopeZ(NSArray<MDSTube *> *tubes,
                                          NSUInteger requiredTubeMask,
                                          double *verticalSpan) {
    MDSTube *lowestTube = nil;
    MDSTube *highestTube = nil;
    for (MDSTube *tube in tubes) {
        if ((requiredTubeMask & ((NSUInteger)1u << tube.tubeIndex)) == 0) {
            continue;
        }
        if (lowestTube == nil || tube.center.y < lowestTube.center.y) {
            lowestTube = tube;
        }
        if (highestTube == nil || tube.center.y > highestTube.center.y) {
            highestTube = tube;
        }
    }
    if (lowestTube == nil || highestTube == nil) {
        if (verticalSpan != NULL) {
            *verticalSpan = 0.0;
        }
        return 0.0;
    }

    const double height = highestTube.center.y - lowestTube.center.y;
    if (verticalSpan != NULL) {
        *verticalSpan = fabs(height);
    }
    if (fabs(height) < MDSGeometryTolerance) {
        return 0.0;
    }
    return (highestTube.center.z - lowestTube.center.z) / height;
}

/// Random arrival directions are retained only when a straight line can cross
/// every tube required by the coincidence logic. This keeps the candidate rate
/// comparable across direction modes instead of producing a stream of tracks that
/// inevitably miss an outer tube. The returned target lies in the y = 0 plane and
/// is sampled uniformly inside the feasible crossing interval.
static BOOL MDSRandomDirectionCrossingTubes(
    MDSRandom *random,
    NSArray<MDSTube *> *tubes,
    NSUInteger requiredTubeMask,
    double maximumZenithDegrees,
    MDSVector3 *direction,
    double *zenithDegrees,
    double *azimuthDegrees,
    MDSVector3 *target) {
    double verticalSpan = 0.0;
    const double centerSlopeZ =
        MDSRequiredTubeCenterSlopeZ(tubes, requiredTubeMask, &verticalSpan);
    const double maximumSlope = tan(MAX(0.0, maximumZenithDegrees) * M_PI / 180.0);
    const double radius = tubes.firstObject.radius;
    const double radiusSlack = verticalSpan > MDSGeometryTolerance
        ? 2.0 * radius / verticalSpan : 0.0;
    if (fabs(centerSlopeZ) <= maximumSlope + radiusSlack +
            MDSGeometryTolerance) {
        for (NSUInteger attempt = 0;
             attempt < MDSRandomDirectionMaximumAttempts;
             attempt++) {
            double candidateZenith = 0.0;
            double candidateAzimuth = 0.0;
            MDSVector3 candidateDirection = MDSRandomRealisticDownwardDirection(
                random, maximumZenithDegrees, &candidateZenith, &candidateAzimuth);
            MDSVector3 candidateTarget = MDSVector3Make(0.0, 0.0, 0.0);
            if (!MDSRandomTargetCrossingTubes(random, tubes, requiredTubeMask,
                                              candidateDirection,
                                              &candidateTarget)) {
                continue;
            }

            if (direction != NULL) {
                *direction = candidateDirection;
            }
            if (zenithDegrees != NULL) {
                *zenithDegrees = candidateZenith;
            }
            if (azimuthDegrees != NULL) {
                *azimuthDegrees = candidateAzimuth;
            }
            if (target != NULL) {
                *target = candidateTarget;
            }
            return YES;
        }

        // The random draws can be extremely inefficient when the selected tubes
        // permit only a narrow band of directions. Use the line through the
        // extreme tube centres as a deterministic valid fallback.
        const double fallbackSlopeZ =
            MIN(MAX(centerSlopeZ, -maximumSlope), maximumSlope);
        MDSVector3 fallbackDirection = MDSVector3Normalized(
            MDSVector3Make(0.0, -1.0, fallbackSlopeZ));
        MDSVector3 fallbackTarget = MDSVector3Make(0.0, 0.0, 0.0);
        if (MDSRandomTargetCrossingTubes(random, tubes, requiredTubeMask,
                                          fallbackDirection, &fallbackTarget)) {
            if (direction != NULL) {
                *direction = fallbackDirection;
            }
            if (zenithDegrees != NULL) {
                *zenithDegrees = acos(MIN(1.0, MAX(-1.0, -fallbackDirection.y))) *
                    180.0 / M_PI;
            }
            if (azimuthDegrees != NULL) {
                double azimuth = atan2(fallbackDirection.z, fallbackDirection.x) *
                    180.0 / M_PI;
                if (azimuth < 0.0) {
                    azimuth += 360.0;
                }
                *azimuthDegrees = azimuth;
            }
            if (target != NULL) {
                *target = fallbackTarget;
            }
            return YES;
        }
    }

    // Extreme geometry can put the selected tubes outside any downward cone.
    // Fall back to an unconditioned direction and let the normal aperture target
    // represent a missed candidate rather than looping forever.
    double fallbackZenith = 0.0;
    double fallbackAzimuth = 0.0;
    MDSVector3 fallbackDirection = MDSRandomRealisticDownwardDirection(
        random, maximumZenithDegrees, &fallbackZenith, &fallbackAzimuth);
    if (direction != NULL) {
        *direction = fallbackDirection;
    }
    if (zenithDegrees != NULL) {
        *zenithDegrees = fallbackZenith;
    }
    if (azimuthDegrees != NULL) {
        *azimuthDegrees = fallbackAzimuth;
    }
    return NO;
}

@interface MDSSimulationEngine ()

@property (nonatomic, copy, readwrite) MDSDetectorConfiguration *configuration;
@property (nonatomic, assign, readwrite) NSTimeInterval currentTime;
@property (nonatomic, assign, readwrite) NSTimeInterval simulationDuration;
@property (nonatomic, assign, readwrite, getter=isFinished) BOOL finished;
@property (nonatomic, assign, readwrite) NSUInteger histogramBinCount;

- (NSMutableArray<NSNumber *> *)emptyHistogram;
- (double)cosmicRatePerSecond;
- (double)firstArrivalForRate:(double)ratePerSecond;
- (double)nextArrivalAfterTime:(double)baseTime rate:(double)ratePerSecond;
- (BOOL)nextArrivalTime:(double *)arrivalTime
               isCosmic:(BOOL *)isCosmic
         backgroundTube:(NSInteger *)backgroundTube;
- (void)generateArrivalAtTime:(double)arrivalTime
                     isCosmic:(BOOL)isCosmic
               backgroundTube:(NSInteger)backgroundTube
                       events:(NSMutableArray<MDSSimulationEvent *> *)events
                 coincidences:(NSMutableArray<MDSCoincidence *> *)coincidences;
- (void)generateCosmicEventAtTime:(double)eventTime
                           events:(NSMutableArray<MDSSimulationEvent *> *)events
                     coincidences:(NSMutableArray<MDSCoincidence *> *)coincidences;
- (void)generateBackgroundEventAtTime:(double)eventTime
                                 tube:(NSInteger)tubeIndex
                               events:(NSMutableArray<MDSSimulationEvent *> *)events
                         coincidences:(NSMutableArray<MDSCoincidence *> *)coincidences;
- (void)recordHits:(NSArray<MDSHit *> *)hits
      coincidences:(NSMutableArray<MDSCoincidence *> *)coincidences;
- (void)attemptCoincidenceForNewHit:(MDSHit *)anchor
                       coincidences:(NSMutableArray<MDSCoincidence *> *)coincidences;
- (nullable MDSHit *)latestUnconsumedHitInTube:(NSInteger)tubeIndex
                                   betweenTime:(double)earliestTime
                                       andTime:(double)latestTime;
- (void)pruneActiveHitsBeforeTime:(double)cutoffTime;
- (void)incrementHistogram:(NSMutableArray<NSNumber *> *)histogram
                    atTime:(NSTimeInterval)time;

@end

@implementation MDSSimulationEngine {
    MDSRandom *_random;
    NSArray<MDSTube *> *_tubes;
    NSMutableArray<MDSHit *> *_activeHitsByTube[3];
    NSMutableArray<NSNumber *> *_histogramHits;
    NSMutableArray<NSNumber *> *_histogramCoincidences;
    double _nextCosmicTime;
    double _nextBackgroundTimes[3];
    uint64_t _nextEventID;
    uint64_t _nextHitID;
    NSUInteger _totalHitCount;
    NSUInteger _hitsPerTube[3];
    NSUInteger _cosmicCandidateCount;
    NSUInteger _showerEventCount;
    NSUInteger _backgroundEventCount;
    NSUInteger _acceptedCoincidenceCount;
    NSUInteger _twoFoldCoincidenceCount;
    NSUInteger _threeFoldCoincidenceCount;
    NSUInteger _accidentalCoincidenceCount;
    NSUInteger _totalParticleCount;
}

- (instancetype)initWithConfiguration:(MDSDetectorConfiguration *)configuration
                                 error:(NSError **)error {
    NSError *validationError = nil;
    if (![configuration validate:&validationError]) {
        if (error) {
            *error = validationError;
        }
        return nil;
    }

    self = [super init];
    if (self) {
        _configuration = [configuration copy];
        _histogramBinCount = MDSDefaultHistogramBinCount;
        _tubes = [_configuration detectorTubes];
        [self restart];
    }
    return self;
}

- (void)restart {
    _random = [[MDSRandom alloc] initWithSeed:self.configuration.randomSeed];
    self.currentTime = 0.0;
    self.simulationDuration = self.configuration.simulationDuration;
    self.finished = NO;
    _nextEventID = 1;
    _nextHitID = 1;

    _totalHitCount = 0;
    for (NSInteger index = 0; index < 3; index++) {
        _hitsPerTube[index] = 0;
        _activeHitsByTube[index] = [NSMutableArray array];
    }
    _cosmicCandidateCount = 0;
    _showerEventCount = 0;
    _backgroundEventCount = 0;
    _acceptedCoincidenceCount = 0;
    _twoFoldCoincidenceCount = 0;
    _threeFoldCoincidenceCount = 0;
    _accidentalCoincidenceCount = 0;
    _totalParticleCount = 0;

    _histogramHits = [self emptyHistogram];
    _histogramCoincidences = [self emptyHistogram];

    // All arrival streams are independent Poisson processes. Scheduling them in a
    // fixed order also makes the sequence deterministic for a given seed.
    _nextCosmicTime = [self firstArrivalForRate:[self cosmicRatePerSecond]];
    for (NSInteger index = 0; index < 3; index++) {
        _nextBackgroundTimes[index] =
            [self firstArrivalForRate:self.configuration.backgroundRatePerTube];
    }
}

- (NSMutableArray<NSNumber *> *)emptyHistogram {
    NSMutableArray<NSNumber *> *bins =
        [NSMutableArray arrayWithCapacity:self.histogramBinCount];
    for (NSUInteger index = 0; index < self.histogramBinCount; index++) {
        [bins addObject:@0];
    }
    return bins;
}

- (double)cosmicRatePerSecond {
    return self.configuration.cosmicEventRatePerMinute / 60.0;
}

- (double)firstArrivalForRate:(double)ratePerSecond {
    if (!isfinite(ratePerSecond) || ratePerSecond <= 0.0) {
        return DBL_MAX;
    }
    return [_random exponentialWithRate:ratePerSecond];
}

- (double)nextArrivalAfterTime:(double)baseTime rate:(double)ratePerSecond {
    if (!isfinite(ratePerSecond) || ratePerSecond <= 0.0) {
        return DBL_MAX;
    }
    return baseTime + [_random exponentialWithRate:ratePerSecond];
}

- (MDSBatch *)advanceToTime:(NSTimeInterval)simulatedTime {
    NSMutableArray<MDSSimulationEvent *> *events = [NSMutableArray array];
    NSMutableArray<MDSCoincidence *> *coincidences = [NSMutableArray array];

    if (self.finished) {
        return [[MDSBatch alloc] initWithEvents:events coincidences:coincidences];
    }

    NSTimeInterval target = simulatedTime;
    if (!isfinite(target) || target < 0.0) {
        target = 0.0;
    }
    target = MIN(target, self.simulationDuration);
    target = MAX(target, self.currentTime);

    while (true) {
        double arrivalTime = 0.0;
        BOOL isCosmic = NO;
        NSInteger backgroundTube = -1;
        if (![self nextArrivalTime:&arrivalTime
                          isCosmic:&isCosmic
                    backgroundTube:&backgroundTube]) {
            break;
        }
        if (arrivalTime > target + 1.0e-12 ||
            arrivalTime > self.simulationDuration + 1.0e-12) {
            break;
        }

        [self generateArrivalAtTime:arrivalTime
                           isCosmic:isCosmic
                     backgroundTube:backgroundTube
                             events:events
                       coincidences:coincidences];
    }

    self.currentTime = target;
    if (self.currentTime >= self.simulationDuration - 1.0e-9) {
        self.currentTime = self.simulationDuration;
        self.finished = YES;
    }

    return [[MDSBatch alloc] initWithEvents:events coincidences:coincidences];
}

- (MDSBatch *)stepNextEvent {
    NSMutableArray<MDSSimulationEvent *> *events = [NSMutableArray array];
    NSMutableArray<MDSCoincidence *> *coincidences = [NSMutableArray array];

    if (self.finished) {
        return [[MDSBatch alloc] initWithEvents:events coincidences:coincidences];
    }

    double arrivalTime = 0.0;
    BOOL isCosmic = NO;
    NSInteger backgroundTube = -1;
    if (![self nextArrivalTime:&arrivalTime
                      isCosmic:&isCosmic
                backgroundTube:&backgroundTube] ||
        arrivalTime > self.simulationDuration + 1.0e-12) {
        self.currentTime = self.simulationDuration;
        self.finished = YES;
        return [[MDSBatch alloc] initWithEvents:events coincidences:coincidences];
    }

    [self generateArrivalAtTime:arrivalTime
                       isCosmic:isCosmic
                 backgroundTube:backgroundTube
                         events:events
                   coincidences:coincidences];
    self.currentTime = MIN(arrivalTime, self.simulationDuration);
    if (self.currentTime >= self.simulationDuration - 1.0e-9) {
        self.currentTime = self.simulationDuration;
        self.finished = YES;
    }

    return [[MDSBatch alloc] initWithEvents:events coincidences:coincidences];
}

- (BOOL)nextArrivalTime:(double *)arrivalTime
               isCosmic:(BOOL *)isCosmic
         backgroundTube:(NSInteger *)backgroundTube {
    double bestTime = _nextCosmicTime;
    BOOL bestIsCosmic = YES;
    NSInteger bestTube = -1;

    for (NSInteger index = 0; index < 3; index++) {
        const double candidate = _nextBackgroundTimes[index];
        if (candidate < bestTime - 1.0e-12) {
            bestTime = candidate;
            bestIsCosmic = NO;
            bestTube = index;
        }
    }

    if (!isfinite(bestTime) || bestTime == DBL_MAX) {
        return NO;
    }

    if (arrivalTime) {
        *arrivalTime = bestTime;
    }
    if (isCosmic) {
        *isCosmic = bestIsCosmic;
    }
    if (backgroundTube) {
        *backgroundTube = bestTube;
    }
    return YES;
}

- (void)generateArrivalAtTime:(double)arrivalTime
                     isCosmic:(BOOL)isCosmic
               backgroundTube:(NSInteger)backgroundTube
                       events:(NSMutableArray<MDSSimulationEvent *> *)events
                 coincidences:(NSMutableArray<MDSCoincidence *> *)coincidences {
    if (isCosmic) {
        _nextCosmicTime =
            [self nextArrivalAfterTime:arrivalTime rate:[self cosmicRatePerSecond]];
        [self generateCosmicEventAtTime:arrivalTime
                                events:events
                          coincidences:coincidences];
    } else {
        const double rate = self.configuration.backgroundRatePerTube;
        _nextBackgroundTimes[backgroundTube] =
            [self nextArrivalAfterTime:arrivalTime rate:rate];
        [self generateBackgroundEventAtTime:arrivalTime
                                      tube:backgroundTube
                                    events:events
                              coincidences:coincidences];
    }
}

- (void)generateCosmicEventAtTime:(double)eventTime
                           events:(NSMutableArray<MDSSimulationEvent *> *)events
                     coincidences:(NSMutableArray<MDSCoincidence *> *)coincidences {
    const uint64_t eventID = _nextEventID++;
    const BOOL isShower = self.configuration.isShowerModeEnabled;
    const NSInteger particleCount = isShower
        ? self.configuration.showerMultiplicity : 1;
    const MDSSimulationEventKind kind =
        isShower ? MDSSimulationEventKindShower : MDSSimulationEventKindCosmic;

    MDSVector3 primaryDirection = MDSVector3Make(0.0, -1.0, 0.0);
    MDSVector3 primaryTarget = MDSVector3Make(0.0, 0.0, 0.0);
    BOOL hasPrimaryTarget = NO;
    double primaryAngle = 0.0;
    double primaryAzimuth = 0.0;
    const BOOL randomArrival =
        self.configuration.arrivalDirectionMode ==
            MDSArrivalDirectionModeRandomRealistic;
    if (randomArrival) {
        double maximumZenith = MDSRandomArrivalMaximumZenithDegrees;
        if (isShower) {
            maximumZenith = MIN(maximumZenith,
                MAX(0.0, MDSMaximumDownwardAngleDegrees -
                    self.configuration.showerAngularSpread));
        }
        hasPrimaryTarget = MDSRandomDirectionCrossingTubes(
            _random, _tubes, self.configuration.requiredTubeMask, maximumZenith,
            &primaryDirection, &primaryAngle, &primaryAzimuth, &primaryTarget);
    } else if (isShower) {
        primaryAngle = self.configuration.primaryAngleFromVertical;
        primaryAzimuth = self.configuration.primaryAzimuth;
        const double theta = primaryAngle * M_PI / 180.0;
        const double phi = primaryAzimuth * M_PI / 180.0;
        primaryDirection = MDSVector3Make(sin(theta) * cos(phi),
                                          -cos(theta),
                                          sin(theta) * sin(phi));
        primaryDirection = MDSVector3Normalized(primaryDirection);
    }

    if (!randomArrival) {
        hasPrimaryTarget = MDSRandomTargetCrossingTubes(
            _random, _tubes, self.configuration.requiredTubeMask,
            primaryDirection, &primaryTarget);
    }

    const double radius = [self.configuration tubeRadius];
    const double halfLength = self.configuration.activeLength * 0.5;
    const double apertureX = halfLength + 0.45;
    const double apertureZ = self.configuration.alignmentOffset + radius + 0.45;
    const double spreadRadians =
        self.configuration.showerAngularSpread * M_PI / 180.0;

    NSMutableArray<MDSTrack *> *tracks = [NSMutableArray arrayWithCapacity:particleCount];
    NSMutableArray<MDSHit *> *hits = [NSMutableArray array];

    for (NSInteger particleIndex = 0; particleIndex < particleCount; particleIndex++) {
        MDSVector3 direction = primaryDirection;
        if (isShower && particleIndex > 0) {
            direction = MDSRandomDirectionAroundAxis(_random, primaryDirection,
                                                      spreadRadians);
        }

        // Sample a target within the telescope aperture. This is a deliberate
        // simplification: it represents the subset of an isotropic flux whose
        // tracks are directed toward this small detector. In random mode the
        // primary target comes from the feasible crossing interval so every
        // sampled candidate can reach each required tube.
        MDSVector3 target;
        if (particleIndex == 0 && hasPrimaryTarget) {
            target = primaryTarget;
        } else {
            target = MDSVector3Make(
                [_random uniformFrom:-apertureX to:apertureX],
                [_random uniformFrom:-self.configuration.tubeSpacing * 0.45
                                  to:self.configuration.tubeSpacing * 0.45],
                [_random uniformFrom:-apertureZ to:apertureZ]);
        }
        const double maximumTubeY =
            self.configuration.tubeSpacing + radius + 0.1 +
            self.configuration.tubeSpacing * 0.45;
        const double minimumYComponent = MAX(0.05, fabs(direction.y));
        const double visualHalfLength = MAX(
            MDSTrackVisualHalfLength, maximumTubeY / minimumYComponent);
        const MDSVector3 start = MDSVector3Subtract(
            target, MDSVector3Multiply(direction, visualHalfLength));
        const MDSVector3 end = MDSVector3Add(
            target, MDSVector3Multiply(direction, visualHalfLength));

        NSUInteger crossedTubeMask = 0;
        for (MDSTube *tube in _tubes) {
            double entry = 0.0;
            double exit = 0.0;
            if (![tube intersectsRayFrom:start
                                direction:direction
                           entryDistance:&entry
                            exitDistance:&exit]) {
                continue;
            }
            crossedTubeMask |= (NSUInteger)(1u << tube.tubeIndex);
            if ([_random nextUniform] >= tube.efficiency) {
                continue;
            }

            const double jitter =
                [_random normalWithMean:0.0
                      standardDeviation:MDSTimingJitterSigmaSeconds];
            const double clampedJitter =
                MIN(MAX(jitter, -3.0 * MDSTimingJitterSigmaSeconds),
                    3.0 * MDSTimingJitterSigmaSeconds);
            const double pulseTime = MAX(0.0, eventTime + clampedJitter);
            MDSHit *hit = [[MDSHit alloc] initWithHitID:_nextHitID++
                                             tubeIndex:tube.tubeIndex
                                             timestamp:pulseTime
                                         sourceEventID:eventID
                                            background:NO];
            [hits addObject:hit];
        }

        MDSTrack *track =
            [[MDSTrack alloc] initWithStartPoint:start
                                        endPoint:end
                                       direction:direction
                                  showerParticle:isShower
                                 crossedTubeMask:crossedTubeMask];
        [tracks addObject:track];
    }

    _cosmicCandidateCount += 1;
    if (isShower) {
        _showerEventCount += 1;
    }
    _totalParticleCount += (NSUInteger)particleCount;

    MDSSimulationEvent *event =
        [[MDSSimulationEvent alloc] initWithEventID:eventID
                                          timestamp:eventTime
                                               kind:kind
                                             tracks:tracks
                                               hits:hits
                                      particleCount:particleCount
                            primaryAngleFromVertical:primaryAngle
                                    primaryAzimuth:primaryAzimuth];
    [events addObject:event];
    [self recordHits:hits coincidences:coincidences];
}

- (void)generateBackgroundEventAtTime:(double)eventTime
                                 tube:(NSInteger)tubeIndex
                               events:(NSMutableArray<MDSSimulationEvent *> *)events
                         coincidences:(NSMutableArray<MDSCoincidence *> *)coincidences {
    const uint64_t eventID = _nextEventID++;
    MDSHit *hit = [[MDSHit alloc] initWithHitID:_nextHitID++
                                     tubeIndex:tubeIndex
                                     timestamp:eventTime
                                 sourceEventID:eventID
                                    background:YES];
    _backgroundEventCount += 1;

    MDSSimulationEvent *event =
        [[MDSSimulationEvent alloc] initWithEventID:eventID
                                          timestamp:eventTime
                                               kind:MDSSimulationEventKindBackground
                                             tracks:@[]
                                               hits:@[ hit ]
                                      particleCount:0
                            primaryAngleFromVertical:0.0
                                    primaryAzimuth:0.0];
    [events addObject:event];

    // Background is an already-recorded pulse rate, so the tube efficiency is not
    // applied a second time to these independent noise pulses.
    [self recordHits:@[ hit ] coincidences:coincidences];
}

- (void)recordHits:(NSArray<MDSHit *> *)hits
      coincidences:(NSMutableArray<MDSCoincidence *> *)coincidences {
    if (hits.count == 0) {
        return;
    }

    NSArray<MDSHit *> *sortedHits = [hits sortedArrayUsingComparator:
        ^NSComparisonResult(MDSHit *first, MDSHit *second) {
            if (first.timestamp < second.timestamp) {
                return NSOrderedAscending;
            }
            if (first.timestamp > second.timestamp) {
                return NSOrderedDescending;
            }
            return first.hitID < second.hitID ? NSOrderedAscending : NSOrderedDescending;
        }];

    for (MDSHit *hit in sortedHits) {
        _totalHitCount += 1;
        _hitsPerTube[hit.tubeIndex] += 1;
        [self incrementHistogram:_histogramHits atTime:hit.timestamp];

        NSMutableArray<MDSHit *> *tubeHits = _activeHitsByTube[hit.tubeIndex];
        NSUInteger insertionIndex = tubeHits.count;
        while (insertionIndex > 0 &&
               tubeHits[insertionIndex - 1].timestamp > hit.timestamp) {
            insertionIndex -= 1;
        }
        [tubeHits insertObject:hit atIndex:insertionIndex];

        [self attemptCoincidenceForNewHit:hit
                             coincidences:coincidences];
        [self pruneActiveHitsBeforeTime:hit.timestamp -
             self.configuration.coincidenceWindowMicroseconds * 1.0e-6];
    }
}

- (void)attemptCoincidenceForNewHit:(MDSHit *)anchor
                       coincidences:(NSMutableArray<MDSCoincidence *> *)coincidences {
    if (anchor.isConsumed ||
        (self.configuration.requiredTubeMask & (1u << anchor.tubeIndex)) == 0) {
        return;
    }

    const double windowSeconds =
        self.configuration.coincidenceWindowMicroseconds * 1.0e-6;
    const double earliestTime = anchor.timestamp - windowSeconds;
    NSMutableArray<MDSHit *> *selectedHits = [NSMutableArray arrayWithCapacity:3];

    for (NSNumber *tubeNumber in [self.configuration requiredTubeIndices]) {
        const NSInteger tubeIndex = tubeNumber.integerValue;
        if (tubeIndex == anchor.tubeIndex) {
            [selectedHits addObject:anchor];
            continue;
        }

        MDSHit *candidate = [self latestUnconsumedHitInTube:tubeIndex
                                               betweenTime:earliestTime
                                                     andTime:anchor.timestamp];
        if (candidate == nil) {
            return;
        }
        [selectedHits addObject:candidate];
    }

    if (selectedHits.count < 2) {
        return;
    }

    const double coincidenceTime = anchor.timestamp;
    NSMutableSet<NSNumber *> *uniqueSourceSet = [NSMutableSet set];
    BOOL includesBackground = NO;
    for (MDSHit *hit in selectedHits) {
        [uniqueSourceSet addObject:@(hit.sourceEventID)];
        includesBackground = includesBackground || hit.isBackground;
    }

    const BOOL accidental = uniqueSourceSet.count > 1 || includesBackground;
    [selectedHits sortUsingComparator:
        ^NSComparisonResult(MDSHit *first, MDSHit *second) {
            return first.tubeIndex < second.tubeIndex
                ? NSOrderedAscending : NSOrderedDescending;
        }];

    NSMutableArray<NSNumber *> *tubeNumbers =
        [NSMutableArray arrayWithCapacity:selectedHits.count];
    for (MDSHit *hit in selectedHits) {
        hit.consumed = YES;
        [tubeNumbers addObject:@(hit.tubeIndex)];
        [_activeHitsByTube[hit.tubeIndex] removeObjectIdenticalTo:hit];
    }

    NSArray<NSNumber *> *uniqueSourceEventIDs =
        [[uniqueSourceSet allObjects] sortedArrayUsingSelector:@selector(compare:)];
    MDSCoincidence *coincidence =
        [[MDSCoincidence alloc] initWithTimestamp:coincidenceTime
                                      tubeIndices:tubeNumbers
                                             hits:selectedHits
                                  sourceEventIDs:uniqueSourceEventIDs
                                      accidental:accidental];
    [coincidences addObject:coincidence];
    _acceptedCoincidenceCount += 1;
    if (tubeNumbers.count == 2) {
        _twoFoldCoincidenceCount += 1;
    } else if (tubeNumbers.count >= 3) {
        _threeFoldCoincidenceCount += 1;
    }
    if (accidental) {
        _accidentalCoincidenceCount += 1;
    }
    [self incrementHistogram:_histogramCoincidences atTime:coincidenceTime];
}

/// Returns the most recent unconsumed pulse in a tube inside the closed interval
/// [earliestTime, latestTime]. Active arrays are ordered by pulse time.
- (nullable MDSHit *)latestUnconsumedHitInTube:(NSInteger)tubeIndex
                                   betweenTime:(double)earliestTime
                                       andTime:(double)latestTime {
    NSArray<MDSHit *> *hits = _activeHitsByTube[tubeIndex];
    for (NSInteger index = (NSInteger)hits.count - 1; index >= 0; index--) {
        MDSHit *hit = hits[(NSUInteger)index];
        if (hit.timestamp > latestTime + 1.0e-12) {
            continue;
        }
        if (hit.timestamp < earliestTime - 1.0e-12) {
            break;
        }
        if (!hit.isConsumed) {
            return hit;
        }
    }
    return nil;
}

- (void)pruneActiveHitsBeforeTime:(double)cutoffTime {
    for (NSInteger tubeIndex = 0; tubeIndex < 3; tubeIndex++) {
        NSMutableArray<MDSHit *> *hits = _activeHitsByTube[tubeIndex];
        while (hits.count > 0 && hits.firstObject.timestamp < cutoffTime - 1.0e-12) {
            [hits removeObjectAtIndex:0];
        }
    }
}

- (void)incrementHistogram:(NSMutableArray<NSNumber *> *)histogram
                    atTime:(NSTimeInterval)time {
    if (self.simulationDuration <= 0.0 || self.histogramBinCount == 0) {
        return;
    }
    double normalized = MAX(0.0, time / self.simulationDuration);
    NSUInteger index = (NSUInteger)floor(normalized * self.histogramBinCount);
    index = MIN(index, self.histogramBinCount - 1);
    histogram[index] = @(histogram[index].unsignedIntegerValue + 1);
}

- (NSUInteger)totalHitCount {
    return _totalHitCount;
}

- (NSUInteger)hitCountForTubeAtIndex:(NSInteger)tubeIndex {
    if (tubeIndex < 0 || tubeIndex >= 3) {
        return 0;
    }
    return _hitsPerTube[tubeIndex];
}

- (NSArray<NSNumber *> *)hitCountsPerTube {
    return @[ @(_hitsPerTube[0]), @(_hitsPerTube[1]), @(_hitsPerTube[2]) ];
}

- (NSUInteger)cosmicCandidateCount {
    return _cosmicCandidateCount;
}

- (NSUInteger)showerEventCount {
    return _showerEventCount;
}

- (NSUInteger)backgroundEventCount {
    return _backgroundEventCount;
}

- (NSUInteger)acceptedCoincidenceCount {
    return _acceptedCoincidenceCount;
}

- (NSUInteger)twoFoldCoincidenceCount {
    return _twoFoldCoincidenceCount;
}

- (NSUInteger)threeFoldCoincidenceCount {
    return _threeFoldCoincidenceCount;
}

- (NSUInteger)accidentalCoincidenceCount {
    return _accidentalCoincidenceCount;
}

- (NSUInteger)totalParticleCount {
    return _totalParticleCount;
}

- (double)acceptedCoincidenceRatePerMinute {
    if (self.currentTime <= 0.0) {
        return 0.0;
    }
    return (double)_acceptedCoincidenceCount / self.currentTime * 60.0;
}

- (double)hitRatePerMinute {
    if (self.currentTime <= 0.0) {
        return 0.0;
    }
    return (double)_totalHitCount / self.currentTime * 60.0;
}

- (NSArray<NSNumber *> *)histogramHitCounts {
    return [_histogramHits copy];
}

- (NSArray<NSNumber *> *)histogramCoincidenceCounts {
    return [_histogramCoincidences copy];
}

@end











