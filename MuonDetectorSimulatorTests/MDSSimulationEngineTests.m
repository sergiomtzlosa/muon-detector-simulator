#import <XCTest/XCTest.h>

#import "MDSBatch.h"
#import "MDSCoincidence.h"
#import "MDSDetectorConfiguration.h"
#import "MDSHit.h"
#import "MDSSimulationEngine.h"
#import "MDSSimulationEvent.h"
#import "MDSTrack.h"

/// These tests live with the engine sources, so they can exercise the otherwise
/// private pulse-ingestion path to pin down coincidence-window boundaries without
/// having to wait for a lucky stochastic alignment.
@interface MDSSimulationEngine (MDSInternalCoincidenceTesting)
- (void)recordHits:(NSArray<MDSHit *> *)hits
      coincidences:(NSMutableArray<MDSCoincidence *> *)coincidences;
@end

@interface MDSSimulationEngineTests : XCTestCase
@end

static MDSDetectorConfiguration *MDSDeterministicTestConfiguration(void) {
    MDSDetectorConfiguration *configuration =
        [MDSDetectorConfiguration defaultConfiguration];
    configuration.simulationDuration = 20.0;
    configuration.randomSeed = 0xC0FFEE1234ULL;
    configuration.backgroundRatePerTube = 0.0;
    configuration.cosmicEventRatePerMinute = 300.0;
    configuration.tubeEfficiencies = @[ @1.0, @1.0, @1.0 ];
    configuration.requiredTubeMask = 0x7;
    configuration.coincidenceWindowMicroseconds = 1.0;
    configuration.showerModeEnabled = NO;
    return configuration;
}

static void MDSCollectBatch(MDSBatch *batch,
                            NSMutableArray<MDSSimulationEvent *> *events,
                            NSMutableArray<MDSCoincidence *> *coincidences) {
    [events addObjectsFromArray:batch.events];
    [coincidences addObjectsFromArray:batch.coincidences];
}

static MDSHit *MDSTestHit(uint64_t hitID,
                          NSInteger tubeIndex,
                          double timestamp,
                          uint64_t sourceEventID,
                          BOOL background) {
    return [[MDSHit alloc] initWithHitID:hitID
                               tubeIndex:tubeIndex
                               timestamp:timestamp
                           sourceEventID:sourceEventID
                              background:background];
}

@implementation MDSSimulationEngineTests

- (void)testEventGenerationIsDeterministicAcrossAdvanceGranularity {
    MDSDetectorConfiguration *configuration = MDSDeterministicTestConfiguration();
    NSError *error = nil;
    MDSSimulationEngine *chunked =
        [[MDSSimulationEngine alloc] initWithConfiguration:configuration error:&error];
    MDSSimulationEngine *single =
        [[MDSSimulationEngine alloc] initWithConfiguration:configuration error:&error];
    XCTAssertNotNil(chunked);
    XCTAssertNotNil(single);
    XCTAssertNil(error);

    NSMutableArray<MDSSimulationEvent *> *chunkedEvents = [NSMutableArray array];
    NSMutableArray<MDSCoincidence *> *chunkedCoincidences = [NSMutableArray array];
    for (double target = 0.25; target < configuration.simulationDuration;
         target += 0.25) {
        MDSBatch *batch = [chunked advanceToTime:target];
        MDSCollectBatch(batch, chunkedEvents, chunkedCoincidences);
    }
    MDSBatch *finalBatch =
        [chunked advanceToTime:configuration.simulationDuration];
    MDSCollectBatch(finalBatch, chunkedEvents, chunkedCoincidences);

    NSMutableArray<MDSSimulationEvent *> *singleEvents = [NSMutableArray array];
    NSMutableArray<MDSCoincidence *> *singleCoincidences = [NSMutableArray array];
    MDSBatch *batch =
        [single advanceToTime:configuration.simulationDuration];
    MDSCollectBatch(batch, singleEvents, singleCoincidences);

    XCTAssertGreaterThan(singleEvents.count, 0);
    XCTAssertEqual(chunkedEvents.count, singleEvents.count);
    XCTAssertEqual(chunkedCoincidences.count, singleCoincidences.count);
    XCTAssertGreaterThan(singleCoincidences.count, 0);
    XCTAssertEqual(chunked.acceptedCoincidenceCount, single.acceptedCoincidenceCount);

    for (NSUInteger index = 0; index < singleEvents.count; index++) {
        MDSSimulationEvent *first = chunkedEvents[index];
        MDSSimulationEvent *second = singleEvents[index];
        XCTAssertEqual(first.eventID, second.eventID);
        XCTAssertEqual(first.kind, second.kind);
        XCTAssertEqualWithAccuracy(first.timestamp, second.timestamp, 1.0e-12);
        XCTAssertEqual(first.hits.count, second.hits.count);
        for (NSUInteger hitIndex = 0; hitIndex < first.hits.count; hitIndex++) {
            MDSHit *firstHit = first.hits[hitIndex];
            MDSHit *secondHit = second.hits[hitIndex];
            XCTAssertEqual(firstHit.hitID, secondHit.hitID);
            XCTAssertEqual(firstHit.tubeIndex, secondHit.tubeIndex);
            XCTAssertEqualWithAccuracy(firstHit.timestamp, secondHit.timestamp,
                                       1.0e-12);
        }
    }

    for (NSUInteger index = 0; index < singleCoincidences.count; index++) {
        MDSCoincidence *first = chunkedCoincidences[index];
        MDSCoincidence *second = singleCoincidences[index];
        XCTAssertEqual(first.fold, second.fold);
        XCTAssertEqual(first.isAccidental, second.isAccidental);
        XCTAssertEqualWithAccuracy(first.timestamp, second.timestamp, 1.0e-12);
        XCTAssertEqualObjects(first.tubeIndices, second.tubeIndices);
        XCTAssertEqualObjects(first.sourceEventIDs, second.sourceEventIDs);
    }

    XCTAssertTrue(single.isFinished);
    XCTAssertEqualWithAccuracy(single.currentTime,
                               configuration.simulationDuration, 1.0e-9);
}

- (void)testStepSequenceMatchesBulkGeneration {
    MDSDetectorConfiguration *configuration = MDSDeterministicTestConfiguration();
    NSError *error = nil;
    MDSSimulationEngine *stepEngine =
        [[MDSSimulationEngine alloc] initWithConfiguration:configuration error:&error];
    MDSSimulationEngine *bulkEngine =
        [[MDSSimulationEngine alloc] initWithConfiguration:configuration error:&error];
    XCTAssertNotNil(stepEngine);
    XCTAssertNotNil(bulkEngine);

    NSMutableArray<MDSSimulationEvent *> *stepEvents = [NSMutableArray array];
    NSMutableArray<MDSCoincidence *> *stepCoincidences = [NSMutableArray array];
    NSInteger safetyCounter = 0;
    while (!stepEngine.isFinished && safetyCounter < 1000) {
        MDSBatch *batch = [stepEngine stepNextEvent];
        MDSCollectBatch(batch, stepEvents, stepCoincidences);
        safetyCounter += 1;
    }
    XCTAssertTrue(stepEngine.isFinished);
    XCTAssertLessThan(safetyCounter, 1000);

    NSMutableArray<MDSSimulationEvent *> *bulkEvents = [NSMutableArray array];
    NSMutableArray<MDSCoincidence *> *bulkCoincidences = [NSMutableArray array];
    MDSBatch *batch =
        [bulkEngine advanceToTime:configuration.simulationDuration];
    MDSCollectBatch(batch, bulkEvents, bulkCoincidences);

    XCTAssertEqual(stepEvents.count, bulkEvents.count);
    XCTAssertEqual(stepCoincidences.count, bulkCoincidences.count);
    XCTAssertEqual(stepEngine.totalHitCount, bulkEngine.totalHitCount);
    XCTAssertEqual(stepEngine.acceptedCoincidenceCount,
                   bulkEngine.acceptedCoincidenceCount);
    for (NSUInteger index = 0; index < stepEvents.count; index++) {
        XCTAssertEqual(stepEvents[index].eventID, bulkEvents[index].eventID);
        XCTAssertEqualWithAccuracy(stepEvents[index].timestamp,
                                   bulkEvents[index].timestamp, 1.0e-12);
    }
}

- (void)testAcceptedCoincidencesRespectSelectedTubesAndWindow {
    MDSDetectorConfiguration *configuration = MDSDeterministicTestConfiguration();
    configuration.simulationDuration = 30.0;
    configuration.cosmicEventRatePerMinute = 600.0;
    NSError *error = nil;
    MDSSimulationEngine *engine =
        [[MDSSimulationEngine alloc] initWithConfiguration:configuration error:&error];
    XCTAssertNotNil(engine);

    NSMutableArray<MDSSimulationEvent *> *events = [NSMutableArray array];
    NSMutableArray<MDSCoincidence *> *coincidences = [NSMutableArray array];
    MDSCollectBatch([engine advanceToTime:30.0], events, coincidences);

    XCTAssertGreaterThan(coincidences.count, 0);
    NSSet<NSNumber *> *requiredTubes = [NSSet setWithArray:@[ @0, @1, @2 ]];
    for (MDSCoincidence *coincidence in coincidences) {
        XCTAssertEqual(coincidence.fold, 3);
        XCTAssertEqualObjects([NSSet setWithArray:coincidence.tubeIndices],
                              requiredTubes);
        XCTAssertFalse(coincidence.isAccidental);
        XCTAssertEqual(coincidence.sourceEventIDs.count, 1);
        XCTAssertEqual(coincidence.hits.count, 3);

        double earliest = coincidence.timestamp;
        double latest = coincidence.timestamp;
        for (MDSHit *hit in coincidence.hits) {
            earliest = MIN(earliest, hit.timestamp);
            latest = MAX(latest, hit.timestamp);
            XCTAssertNotNil(hit);
            XCTAssertTrue(hit.isConsumed);
        }
        XCTAssertLessThanOrEqual(latest - earliest,
            configuration.coincidenceWindowMicroseconds * 1.0e-6 + 1.0e-12);
    }
}

- (void)testStatisticsAndHistogramsRemainConsistent {
    MDSDetectorConfiguration *configuration = MDSDeterministicTestConfiguration();
    configuration.simulationDuration = 25.0;
    configuration.randomSeed = 123;
    configuration.backgroundRatePerTube = 4.0;
    configuration.cosmicEventRatePerMinute = 180.0;
    configuration.tubeEfficiencies = @[ @0.9, @0.92, @0.88 ];
    configuration.coincidenceWindowMicroseconds = 1.5;
    NSError *error = nil;
    MDSSimulationEngine *engine =
        [[MDSSimulationEngine alloc] initWithConfiguration:configuration error:&error];
    XCTAssertNotNil(engine);

    NSMutableArray<MDSSimulationEvent *> *events = [NSMutableArray array];
    NSMutableArray<MDSCoincidence *> *coincidences = [NSMutableArray array];
    MDSCollectBatch([engine advanceToTime:25.0], events, coincidences);

    XCTAssertEqual(events.count,
        engine.cosmicCandidateCount + engine.backgroundEventCount);
    XCTAssertEqual(coincidences.count, engine.acceptedCoincidenceCount);
    XCTAssertEqual(engine.acceptedCoincidenceCount,
        engine.twoFoldCoincidenceCount + engine.threeFoldCoincidenceCount);
    XCTAssertLessThanOrEqual(engine.accidentalCoincidenceCount,
                             engine.acceptedCoincidenceCount);

    const NSUInteger totalHits = engine.totalHitCount;
    const NSUInteger perTubeTotal =
        [engine hitCountForTubeAtIndex:0] +
        [engine hitCountForTubeAtIndex:1] +
        [engine hitCountForTubeAtIndex:2];
    XCTAssertEqual(totalHits, perTubeTotal);
    XCTAssertEqualObjects(engine.hitCountsPerTube,
        (@[ @([engine hitCountForTubeAtIndex:0]),
            @([engine hitCountForTubeAtIndex:1]),
            @([engine hitCountForTubeAtIndex:2]) ]));

    NSArray<NSNumber *> *hitHistogram = engine.histogramHitCounts;
    NSArray<NSNumber *> *coincidenceHistogram = engine.histogramCoincidenceCounts;
    XCTAssertEqual(hitHistogram.count, engine.histogramBinCount);
    XCTAssertEqual(coincidenceHistogram.count, engine.histogramBinCount);

    NSUInteger histogramHits = 0;
    for (NSNumber *value in hitHistogram) {
        histogramHits += value.unsignedIntegerValue;
    }
    XCTAssertEqual(histogramHits, totalHits);

    NSUInteger histogramCoincidences = 0;
    for (NSNumber *value in coincidenceHistogram) {
        histogramCoincidences += value.unsignedIntegerValue;
    }
    XCTAssertEqual(histogramCoincidences, engine.acceptedCoincidenceCount);

    XCTAssertEqualWithAccuracy(engine.acceptedCoincidenceRatePerMinute,
        (double)engine.acceptedCoincidenceCount / 25.0 * 60.0, 1.0e-9);
    XCTAssertEqualWithAccuracy(engine.hitRatePerMinute,
        (double)totalHits / 25.0 * 60.0, 1.0e-9);
    XCTAssertTrue(engine.isFinished);
}

- (void)testBackgroundProducesAccidentalCoincidences {
    MDSDetectorConfiguration *configuration =
        [MDSDetectorConfiguration defaultConfiguration];
    configuration.simulationDuration = 10.0;
    configuration.randomSeed = 4242;
    configuration.cosmicEventRatePerMinute = 0.0;
    configuration.backgroundRatePerTube = 250.0;
    configuration.coincidenceWindowMicroseconds = 10000.0;
    configuration.requiredTubeMask = 0x7;
    NSError *error = nil;
    MDSSimulationEngine *engine =
        [[MDSSimulationEngine alloc] initWithConfiguration:configuration error:&error];
    XCTAssertNotNil(engine);

    NSMutableArray<MDSSimulationEvent *> *events = [NSMutableArray array];
    NSMutableArray<MDSCoincidence *> *coincidences = [NSMutableArray array];
    MDSCollectBatch([engine advanceToTime:10.0], events, coincidences);

    XCTAssertGreaterThan(engine.backgroundEventCount, 0);
    XCTAssertGreaterThan(engine.acceptedCoincidenceCount, 0);
    XCTAssertEqual(engine.acceptedCoincidenceCount,
                   engine.accidentalCoincidenceCount);
    XCTAssertEqual(engine.cosmicCandidateCount, 0);
    XCTAssertEqual(engine.totalHitCount, engine.backgroundEventCount);
    for (MDSCoincidence *coincidence in coincidences) {
        XCTAssertTrue(coincidence.isAccidental);
        for (MDSHit *hit in coincidence.hits) {
            XCTAssertTrue(hit.isBackground);
        }
    }
}

- (void)testShowerModeCreatesConfiguredNumberOfDownwardParticles {
    MDSDetectorConfiguration *configuration =
        [MDSDetectorConfiguration defaultConfiguration];
    configuration.simulationDuration = 20.0;
    configuration.randomSeed = 777;
    configuration.backgroundRatePerTube = 0.0;
    configuration.cosmicEventRatePerMinute = 180.0;
    configuration.tubeEfficiencies = @[ @1.0, @1.0, @1.0 ];
    configuration.coincidenceWindowMicroseconds = 1.0;
    configuration.showerModeEnabled = YES;
    configuration.primaryAngleFromVertical = 15.0;
    configuration.primaryAzimuth = 45.0;
    configuration.showerMultiplicity = 6;
    configuration.showerAngularSpread = 10.0;
    NSError *error = nil;
    MDSSimulationEngine *engine =
        [[MDSSimulationEngine alloc] initWithConfiguration:configuration error:&error];
    XCTAssertNotNil(engine);

    NSMutableArray<MDSSimulationEvent *> *events = [NSMutableArray array];
    NSMutableArray<MDSCoincidence *> *coincidences = [NSMutableArray array];
    MDSCollectBatch([engine advanceToTime:20.0], events, coincidences);

    XCTAssertGreaterThan(events.count, 0);
    XCTAssertEqual(engine.cosmicCandidateCount, events.count);
    XCTAssertEqual(engine.showerEventCount, events.count);
    XCTAssertEqual(engine.totalParticleCount,
                   (NSUInteger)events.count * 6);

    const double theta = configuration.primaryAngleFromVertical * M_PI / 180.0;
    const double phi = configuration.primaryAzimuth * M_PI / 180.0;
    const MDSVector3 axis = MDSVector3Make(sin(theta) * cos(phi),
                                           -cos(theta),
                                           sin(theta) * sin(phi));
    for (MDSSimulationEvent *event in events) {
        XCTAssertEqual(event.kind, MDSSimulationEventKindShower);
        XCTAssertEqual(event.tracks.count, 6);
        XCTAssertEqual(event.particleCount, 6);
        for (MDSTrack *track in event.tracks) {
            XCTAssertTrue(track.isShowerParticle);
            XCTAssertLessThan(track.direction.y, 0.0);
            const double dot = MDSVector3Dot(track.direction, axis);
            const double angle = acos(MIN(1.0, MAX(-1.0, dot))) * 180.0 / M_PI;
            XCTAssertLessThanOrEqual(angle,
                configuration.showerAngularSpread + 1.0e-6);
        }
    }
}

- (void)testExactCoincidenceWindowAndAccidentalFlagWithSyntheticPulses {
    MDSDetectorConfiguration *configuration =
        [MDSDetectorConfiguration defaultConfiguration];
    configuration.backgroundRatePerTube = 0.0;
    configuration.cosmicEventRatePerMinute = 0.0;
    configuration.simulationDuration = 100.0;
    configuration.requiredTubeMask = 0x7;
    configuration.coincidenceWindowMicroseconds = 1.0;

    NSError *error = nil;
    MDSSimulationEngine *engine =
        [[MDSSimulationEngine alloc] initWithConfiguration:configuration error:&error];
    XCTAssertNotNil(engine);

    const double base = 10.0;
    NSArray<MDSHit *> *hits = @[
        MDSTestHit(1, 0, base, 42, NO),
        MDSTestHit(2, 1, base + 0.5e-6, 42, NO),
        MDSTestHit(3, 2, base + 1.0e-6, 42, NO),
    ];
    NSMutableArray<MDSCoincidence *> *coincidences = [NSMutableArray array];
    [engine recordHits:hits coincidences:coincidences];

    XCTAssertEqual(coincidences.count, 1);
    MDSCoincidence *coincidence = coincidences.firstObject;
    XCTAssertEqual(coincidence.fold, 3);
    XCTAssertFalse(coincidence.isAccidental);
    XCTAssertEqualWithAccuracy(coincidence.timestamp, base + 1.0e-6, 1.0e-15);
    for (MDSHit *hit in hits) {
        XCTAssertTrue(hit.isConsumed);
    }

    configuration.coincidenceWindowMicroseconds = 1.0;
    MDSSimulationEngine *outsideWindow =
        [[MDSSimulationEngine alloc] initWithConfiguration:configuration error:&error];
    XCTAssertNotNil(outsideWindow);
    NSArray<MDSHit *> *outsideHits = @[
        MDSTestHit(4, 0, base, 43, NO),
        MDSTestHit(5, 1, base + 0.5e-6, 43, NO),
        MDSTestHit(6, 2, base + 1.002e-6, 43, NO),
    ];
    NSMutableArray<MDSCoincidence *> *outsideCoincidences = [NSMutableArray array];
    [outsideWindow recordHits:outsideHits coincidences:outsideCoincidences];
    XCTAssertEqual(outsideCoincidences.count, 0);

    MDSDetectorConfiguration *twoFoldConfiguration = [configuration copy];
    twoFoldConfiguration.requiredTubeMask = 0x3;
    twoFoldConfiguration.coincidenceWindowMicroseconds = 5.0;
    MDSSimulationEngine *twoFoldEngine =
        [[MDSSimulationEngine alloc] initWithConfiguration:twoFoldConfiguration
                                                     error:&error];
    XCTAssertNotNil(twoFoldEngine);
    NSArray<MDSHit *> *mixedHits = @[
        MDSTestHit(7, 0, base, 100, NO),
        MDSTestHit(8, 1, base + 0.75e-6, 101, NO),
        MDSTestHit(9, 2, base + 1.5e-6, 102, NO),
    ];
    NSMutableArray<MDSCoincidence *> *mixedCoincidences = [NSMutableArray array];
    [twoFoldEngine recordHits:mixedHits coincidences:mixedCoincidences];
    XCTAssertEqual(mixedCoincidences.count, 1);
    XCTAssertEqual(mixedCoincidences.firstObject.fold, 2);
    XCTAssertTrue(mixedCoincidences.firstObject.isAccidental);
}

- (void)testConsumedPulseCannotBeReusedButOtherPulsesCanFormNewSet {
    MDSDetectorConfiguration *configuration =
        [MDSDetectorConfiguration defaultConfiguration];
    configuration.backgroundRatePerTube = 0.0;
    configuration.cosmicEventRatePerMinute = 0.0;
    configuration.simulationDuration = 100.0;
    configuration.requiredTubeMask = 0x3;
    configuration.coincidenceWindowMicroseconds = 2.0;
    NSError *error = nil;
    MDSSimulationEngine *engine =
        [[MDSSimulationEngine alloc] initWithConfiguration:configuration error:&error];
    XCTAssertNotNil(engine);

    const double base = 20.0;
    NSArray<MDSHit *> *hits = @[
        MDSTestHit(10, 0, base + 1.5e-6, 55, NO),
        MDSTestHit(11, 0, base + 1.7e-6, 55, NO),
        MDSTestHit(12, 1, base + 2.0e-6, 55, NO),
        MDSTestHit(13, 1, base + 3.0e-6, 55, NO),
    ];
    NSMutableArray<MDSCoincidence *> *coincidences = [NSMutableArray array];
    [engine recordHits:hits coincidences:coincidences];

    XCTAssertEqual(coincidences.count, 2);
    NSMutableSet<NSNumber *> *usedHitIDs = [NSMutableSet set];
    for (MDSCoincidence *coincidence in coincidences) {
        XCTAssertEqual(coincidence.fold, 2);
        for (MDSHit *hit in coincidence.hits) {
            XCTAssertFalse([usedHitIDs containsObject:@(hit.hitID)]);
            [usedHitIDs addObject:@(hit.hitID)];
        }
    }
    XCTAssertEqual(usedHitIDs.count, 4);
}

- (void)testRandomRealisticArrivalDirectionsAreDownwardSeededAndVaried {
    MDSDetectorConfiguration *configuration =
        [MDSDeterministicTestConfiguration() copy];
    configuration.simulationDuration = 60.0;
    configuration.cosmicEventRatePerMinute = 600.0;
    configuration.arrivalDirectionMode =
        MDSArrivalDirectionModeRandomRealistic;

    NSError *error = nil;
    MDSSimulationEngine *first =
        [[MDSSimulationEngine alloc] initWithConfiguration:configuration
                                                     error:&error];
    MDSSimulationEngine *second =
        [[MDSSimulationEngine alloc] initWithConfiguration:configuration
                                                     error:&error];
    XCTAssertNotNil(first);
    XCTAssertNotNil(second);
    XCTAssertNil(error);

    NSMutableArray<MDSSimulationEvent *> *firstEvents = [NSMutableArray array];
    NSMutableArray<MDSSimulationEvent *> *secondEvents = [NSMutableArray array];
    NSMutableArray<MDSCoincidence *> *ignored = [NSMutableArray array];
    MDSCollectBatch([first advanceToTime:configuration.simulationDuration],
                    firstEvents, ignored);
    MDSCollectBatch([second advanceToTime:configuration.simulationDuration],
                    secondEvents, ignored);

    XCTAssertGreaterThan(firstEvents.count, 100);
    XCTAssertEqual(firstEvents.count, secondEvents.count);
    double largestAngle = 0.0;
    double smallestAzimuth = 360.0;
    double largestAzimuth = 0.0;
    NSMutableSet<NSNumber *> *roundedAngles = [NSMutableSet set];

    for (NSUInteger index = 0; index < firstEvents.count; index++) {
        MDSSimulationEvent *event = firstEvents[index];
        MDSSimulationEvent *repeated = secondEvents[index];
        XCTAssertEqual(event.kind, MDSSimulationEventKindCosmic);
        XCTAssertEqual(event.tracks.count, 1);
        XCTAssertEqualWithAccuracy(event.primaryAngleFromVertical,
                                   repeated.primaryAngleFromVertical, 1.0e-12);
        XCTAssertEqualWithAccuracy(event.primaryAzimuth,
                                   repeated.primaryAzimuth, 1.0e-12);
        XCTAssertGreaterThanOrEqual(event.primaryAngleFromVertical, 0.0);
        XCTAssertLessThanOrEqual(event.primaryAngleFromVertical, 80.0 + 1.0e-9);
        XCTAssertGreaterThanOrEqual(event.primaryAzimuth, 0.0);
        XCTAssertLessThan(event.primaryAzimuth, 360.0);

        const double theta = event.primaryAngleFromVertical * M_PI / 180.0;
        const double phi = event.primaryAzimuth * M_PI / 180.0;
        const MDSVector3 expectedDirection =
            MDSVector3Make(sin(theta) * cos(phi), -cos(theta),
                           sin(theta) * sin(phi));
        MDSTrack *track = event.tracks.firstObject;
        XCTAssertLessThan(track.direction.y, 0.0);
        XCTAssertEqualWithAccuracy(track.direction.x, expectedDirection.x, 1.0e-9);
        XCTAssertEqualWithAccuracy(track.direction.y, expectedDirection.y, 1.0e-9);
        XCTAssertEqualWithAccuracy(track.direction.z, expectedDirection.z, 1.0e-9);
        XCTAssertEqualWithAccuracy(MDSVector3Length(track.direction), 1.0, 1.0e-9);
        XCTAssertEqualWithAccuracy(track.direction.x, repeated.tracks.firstObject.direction.x,
                                   1.0e-12);
        XCTAssertEqualWithAccuracy(track.direction.z, repeated.tracks.firstObject.direction.z,
                                   1.0e-12);

        largestAngle = MAX(largestAngle, event.primaryAngleFromVertical);
        smallestAzimuth = MIN(smallestAzimuth, event.primaryAzimuth);
        largestAzimuth = MAX(largestAzimuth, event.primaryAzimuth);
        [roundedAngles addObject:@((NSInteger)llround(
            event.primaryAngleFromVertical))];
    }

    XCTAssertGreaterThan(largestAngle, 5.0);
    XCTAssertGreaterThan(largestAzimuth - smallestAzimuth, 30.0);
    XCTAssertGreaterThan(roundedAngles.count, 8);
}

- (void)testRandomRealisticCandidatesCrossRequiredTubesAndCoincide {
    MDSDetectorConfiguration *configuration =
        [MDSDetectorConfiguration defaultConfiguration];
    configuration.simulationDuration = 60.0;
    configuration.randomSeed = 12345;
    configuration.backgroundRatePerTube = 0.0;
    configuration.cosmicEventRatePerMinute = 30.0;
    configuration.tubeEfficiencies = @[ @1.0, @1.0, @1.0 ];
    configuration.arrivalDirectionMode =
        MDSArrivalDirectionModeRandomRealistic;
    configuration.requiredTubeMask = 0x7;

    NSError *error = nil;
    MDSSimulationEngine *engine =
        [[MDSSimulationEngine alloc] initWithConfiguration:configuration
                                                     error:&error];
    XCTAssertNotNil(engine);
    XCTAssertNil(error);

    NSMutableArray<MDSSimulationEvent *> *events = [NSMutableArray array];
    NSMutableArray<MDSCoincidence *> *coincidences = [NSMutableArray array];
    MDSCollectBatch([engine advanceToTime:configuration.simulationDuration],
                    events, coincidences);

    XCTAssertGreaterThan(engine.cosmicCandidateCount, 0);
    XCTAssertEqual(engine.threeFoldCoincidenceCount,
                   engine.cosmicCandidateCount);
    XCTAssertEqual(coincidences.count, engine.acceptedCoincidenceCount);
    for (MDSSimulationEvent *event in events) {
        MDSTrack *track = event.tracks.firstObject;
        XCTAssertNotNil(track);
        XCTAssertEqual(track.crossedTubeMask & configuration.requiredTubeMask,
                       configuration.requiredTubeMask);
    }
}

- (void)testRandomRealisticCandidatesRespectTwoFoldGeometry {
    MDSDetectorConfiguration *configuration =
        [MDSDetectorConfiguration defaultConfiguration];
    configuration.simulationDuration = 60.0;
    configuration.randomSeed = 2024;
    configuration.backgroundRatePerTube = 0.0;
    configuration.cosmicEventRatePerMinute = 30.0;
    configuration.tubeEfficiencies = @[ @1.0, @1.0, @1.0 ];
    configuration.arrivalDirectionMode =
        MDSArrivalDirectionModeRandomRealistic;
    configuration.requiredTubeMask = 0x3;

    NSError *error = nil;
    MDSSimulationEngine *engine =
        [[MDSSimulationEngine alloc] initWithConfiguration:configuration
                                                     error:&error];
    XCTAssertNotNil(engine);
    XCTAssertNil(error);

    NSMutableArray<MDSSimulationEvent *> *events = [NSMutableArray array];
    NSMutableArray<MDSCoincidence *> *coincidences = [NSMutableArray array];
    MDSCollectBatch([engine advanceToTime:configuration.simulationDuration],
                    events, coincidences);

    XCTAssertGreaterThan(engine.twoFoldCoincidenceCount, 0);
    XCTAssertEqual(engine.twoFoldCoincidenceCount,
                   engine.acceptedCoincidenceCount);
    for (MDSSimulationEvent *event in events) {
        MDSTrack *track = event.tracks.firstObject;
        XCTAssertNotNil(track);
        XCTAssertEqual(track.crossedTubeMask & configuration.requiredTubeMask,
                       configuration.requiredTubeMask);
    }
}

- (void)testRandomShowerAxisAndConeStayBelowHorizontal {
    MDSDetectorConfiguration *configuration =
        [MDSDeterministicTestConfiguration() copy];
    configuration.simulationDuration = 30.0;
    configuration.cosmicEventRatePerMinute = 300.0;
    configuration.showerModeEnabled = YES;
    configuration.showerMultiplicity = 5;
    configuration.showerAngularSpread = 12.0;
    configuration.arrivalDirectionMode =
        MDSArrivalDirectionModeRandomRealistic;
    configuration.tubeEfficiencies = @[ @1.0, @1.0, @1.0 ];

    NSError *error = nil;
    MDSSimulationEngine *engine =
        [[MDSSimulationEngine alloc] initWithConfiguration:configuration
                                                     error:&error];
    XCTAssertNotNil(engine);
    XCTAssertNil(error);

    NSMutableArray<MDSSimulationEvent *> *events = [NSMutableArray array];
    NSMutableArray<MDSCoincidence *> *ignored = [NSMutableArray array];
    MDSCollectBatch([engine advanceToTime:configuration.simulationDuration],
                    events, ignored);
    XCTAssertGreaterThan(events.count, 50);

    const double maxPrimaryAngle = 85.0 - configuration.showerAngularSpread;
    const double coneCosine = cos(configuration.showerAngularSpread * M_PI / 180.0);
    double largestPrimaryAngle = 0.0;
    for (MDSSimulationEvent *event in events) {
        if (event.kind != MDSSimulationEventKindShower) {
            continue;
        }
        XCTAssertEqual(event.tracks.count,
                       (NSUInteger)configuration.showerMultiplicity);
        XCTAssertLessThanOrEqual(event.primaryAngleFromVertical,
                                 maxPrimaryAngle + 1.0e-9);
        largestPrimaryAngle = MAX(largestPrimaryAngle,
                                  event.primaryAngleFromVertical);
        MDSTrack *primaryTrack = event.tracks.firstObject;
        XCTAssertEqual(primaryTrack.crossedTubeMask & configuration.requiredTubeMask,
                       configuration.requiredTubeMask);

        const double theta = event.primaryAngleFromVertical * M_PI / 180.0;
        const double phi = event.primaryAzimuth * M_PI / 180.0;
        const MDSVector3 axis =
            MDSVector3Make(sin(theta) * cos(phi), -cos(theta),
                           sin(theta) * sin(phi));
        for (MDSTrack *track in event.tracks) {
            XCTAssertLessThan(track.direction.y, 0.0);
            XCTAssertGreaterThanOrEqual(MDSVector3Dot(track.direction, axis),
                                        coneCosine - 1.0e-9);
            XCTAssertTrue(track.isShowerParticle || event.tracks.count == 1);
        }
    }
    XCTAssertGreaterThan(largestPrimaryAngle, 5.0);
}

- (void)testInvalidConfigurationCannotCreateEngine {
    MDSDetectorConfiguration *configuration =
        [MDSDetectorConfiguration defaultConfiguration];
    configuration.simulationDuration = -1.0;
    NSError *error = nil;
    MDSSimulationEngine *engine =
        [[MDSSimulationEngine alloc] initWithConfiguration:configuration error:&error];
    XCTAssertNil(engine);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, MDSDetectorConfigurationErrorDomain);
}

@end











