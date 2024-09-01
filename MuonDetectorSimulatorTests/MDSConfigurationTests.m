#import <XCTest/XCTest.h>

#import "MDSDetectorConfiguration.h"
#import "MDSTube.h"

@interface MDSConfigurationTests : XCTestCase
@end

@implementation MDSConfigurationTests

- (void)testDefaultConfigurationIsValid {
    MDSDetectorConfiguration *configuration =
        [MDSDetectorConfiguration defaultConfiguration];
    NSError *error = nil;
    XCTAssertTrue([configuration validate:&error]);
    XCTAssertNil(error);
    XCTAssertEqual(configuration.requiredTubeMask, (NSUInteger)0x7);
    XCTAssertEqualWithAccuracy(configuration.tubeSpacing, 6.0, 1.0e-9);
    XCTAssertEqualWithAccuracy(configuration.coincidenceWindowMicroseconds,
                               1.0, 1.0e-9);
    XCTAssertEqual(configuration.tubeEfficiencies.count, 3);
    XCTAssertEqual(configuration.arrivalDirectionMode,
                   MDSArrivalDirectionModeVertical);
}

- (void)testCopyRetainsEverySetting {
    MDSDetectorConfiguration *configuration =
        [MDSDetectorConfiguration defaultConfiguration];
    configuration.simulationDuration = 321.0;
    configuration.randomSeed = 987654321;
    configuration.tubeSpacing = 9.5;
    configuration.alignmentOffset = 2.25;
    configuration.activeLength = 12.5;
    configuration.activeDiameter = 2.2;
    configuration.tubeEfficiencies = @[ @0.5, @0.6, @0.7 ];
    configuration.backgroundRatePerTube = 8.0;
    configuration.cosmicEventRatePerMinute = 45.0;
    configuration.arrivalDirectionMode =
        MDSArrivalDirectionModeRandomRealistic;
    configuration.coincidenceWindowMicroseconds = 3.5;
    configuration.requiredTubeMask = 0x5;
    configuration.showerModeEnabled = YES;
    configuration.primaryAngleFromVertical = 20.0;
    configuration.primaryAzimuth = 75.0;
    configuration.showerMultiplicity = 9;
    configuration.showerAngularSpread = 6.0;

    MDSDetectorConfiguration *copy = [configuration copy];
    NSError *error = nil;
    XCTAssertTrue([copy validate:&error]);

    XCTAssertEqualWithAccuracy(copy.simulationDuration, 321.0, 1.0e-9);
    XCTAssertEqual(copy.randomSeed, 987654321ULL);
    XCTAssertEqualWithAccuracy(copy.tubeSpacing, 9.5, 1.0e-9);
    XCTAssertEqualWithAccuracy(copy.alignmentOffset, 2.25, 1.0e-9);
    XCTAssertEqualWithAccuracy(copy.activeLength, 12.5, 1.0e-9);
    XCTAssertEqualWithAccuracy(copy.activeDiameter, 2.2, 1.0e-9);
    XCTAssertEqualObjects(copy.tubeEfficiencies, (@[ @0.5, @0.6, @0.7 ]));
    XCTAssertEqualWithAccuracy(copy.backgroundRatePerTube, 8.0, 1.0e-9);
    XCTAssertEqualWithAccuracy(copy.cosmicEventRatePerMinute, 45.0, 1.0e-9);
    XCTAssertEqual(copy.arrivalDirectionMode,
                   MDSArrivalDirectionModeRandomRealistic);
    XCTAssertEqualWithAccuracy(copy.coincidenceWindowMicroseconds, 3.5, 1.0e-9);
    XCTAssertEqual(copy.requiredTubeMask, (NSUInteger)0x5);
    XCTAssertTrue(copy.isShowerModeEnabled);
    XCTAssertEqualWithAccuracy(copy.primaryAngleFromVertical, 20.0, 1.0e-9);
    XCTAssertEqualWithAccuracy(copy.primaryAzimuth, 75.0, 1.0e-9);
    XCTAssertEqual(copy.showerMultiplicity, 9);
    XCTAssertEqualWithAccuracy(copy.showerAngularSpread, 6.0, 1.0e-9);
}

- (void)testInvalidValuesAreRejected {
    NSArray<NSNumber *> *badDurations = @[ @(0.0), @(86401.0) ];
    for (NSNumber *value in badDurations) {
        MDSDetectorConfiguration *configuration =
            [MDSDetectorConfiguration defaultConfiguration];
        configuration.simulationDuration = value.doubleValue;
        NSError *error = nil;
        XCTAssertFalse([configuration validate:&error]);
        XCTAssertNotNil(error);
        XCTAssertEqual(error.code,
                       MDSConfigurationValidationErrorDuration);
    }

    MDSDetectorConfiguration *configuration =
        [MDSDetectorConfiguration defaultConfiguration];
    configuration.activeDiameter = 4.0;
    configuration.tubeSpacing = 2.0;
    NSError *error = nil;
    XCTAssertFalse([configuration validate:&error]);
    XCTAssertEqual(error.code, MDSConfigurationValidationErrorSpacing);

    configuration = [MDSDetectorConfiguration defaultConfiguration];
    configuration.tubeEfficiencies = @[ @1.2, @0.9, @0.9 ];
    error = nil;
    XCTAssertFalse([configuration validate:&error]);
    XCTAssertEqual(error.code, MDSConfigurationValidationErrorEfficiency);

    configuration = [MDSDetectorConfiguration defaultConfiguration];
    configuration.requiredTubeMask = 0x2;
    error = nil;
    XCTAssertFalse([configuration validate:&error]);
    XCTAssertEqual(error.code, MDSConfigurationValidationErrorRequiredTubes);

    configuration = [MDSDetectorConfiguration defaultConfiguration];
    configuration.requiredTubeMask = 0x8;
    error = nil;
    XCTAssertFalse([configuration validate:&error]);
    XCTAssertEqual(error.code, MDSConfigurationValidationErrorRequiredTubes);

    configuration = [MDSDetectorConfiguration defaultConfiguration];
    configuration.coincidenceWindowMicroseconds = 0.0;
    error = nil;
    XCTAssertFalse([configuration validate:&error]);
    XCTAssertEqual(error.code,
                   MDSConfigurationValidationErrorCoincidenceWindow);

    configuration = [MDSDetectorConfiguration defaultConfiguration];
    configuration.backgroundRatePerTube = -1.0;
    error = nil;
    XCTAssertFalse([configuration validate:&error]);
    XCTAssertEqual(error.code,
                   MDSConfigurationValidationErrorBackgroundRate);

    configuration = [MDSDetectorConfiguration defaultConfiguration];
    configuration.cosmicEventRatePerMinute = -1.0;
    error = nil;
    XCTAssertFalse([configuration validate:&error]);
    XCTAssertEqual(error.code, MDSConfigurationValidationErrorCosmicRate);
}

- (void)testShowerConeCannotExtendAboveHorizontal {
    MDSDetectorConfiguration *configuration =
        [MDSDetectorConfiguration defaultConfiguration];
    configuration.showerModeEnabled = YES;
    configuration.primaryAngleFromVertical = 80.0;
    configuration.showerAngularSpread = 10.0;
    NSError *error = nil;
    XCTAssertFalse([configuration validate:&error]);
    XCTAssertEqual(error.code,
                   MDSConfigurationValidationErrorShowerGeometry);

    // Random arrival mode supplies its own safe axis, so the stored fallback
    // axis does not make the configuration invalid in that mode.
    configuration.arrivalDirectionMode =
        MDSArrivalDirectionModeRandomRealistic;
    error = nil;
    XCTAssertTrue([configuration validate:&error]);
    XCTAssertNil(error);
}

- (void)testInvalidArrivalDirectionModeIsRejected {
    MDSDetectorConfiguration *configuration =
        [MDSDetectorConfiguration defaultConfiguration];
    configuration.arrivalDirectionMode = (MDSArrivalDirectionMode)99;
    NSError *error = nil;
    XCTAssertFalse([configuration validate:&error]);
    XCTAssertEqual(error.code,
                   MDSConfigurationValidationErrorArrivalDirection);
}

- (void)testRequiredTubeIndicesAndDescription {
    MDSDetectorConfiguration *configuration =
        [MDSDetectorConfiguration defaultConfiguration];
    XCTAssertEqualObjects([configuration requiredTubeIndices], (@[ @0, @1, @2 ]));
    XCTAssertTrue([[configuration coincidenceDescription]
        containsString:@"Tube 1 + Tube 2 + Tube 3"]);
    XCTAssertTrue([[configuration coincidenceDescription] containsString:@"3-fold"]);

    configuration.requiredTubeMask = 0x5;
    XCTAssertEqualObjects([configuration requiredTubeIndices], (@[ @0, @2 ]));
    XCTAssertTrue([[configuration coincidenceDescription] containsString:@"2-fold"]);
}

- (void)testTubeCentresUseSpacingAndAlignment {
    MDSDetectorConfiguration *configuration =
        [MDSDetectorConfiguration defaultConfiguration];
    configuration.tubeSpacing = 8.0;
    configuration.alignmentOffset = 2.0;

    const MDSVector3 top = [configuration centerForTubeAtIndex:0];
    const MDSVector3 middle = [configuration centerForTubeAtIndex:1];
    const MDSVector3 bottom = [configuration centerForTubeAtIndex:2];
    XCTAssertEqualWithAccuracy(top.x, 0.0, 1.0e-9);
    XCTAssertEqualWithAccuracy(top.y, 8.0, 1.0e-9);
    XCTAssertEqualWithAccuracy(top.z, 2.0, 1.0e-9);
    XCTAssertEqualWithAccuracy(middle.y, 0.0, 1.0e-9);
    XCTAssertEqualWithAccuracy(middle.z, 0.0, 1.0e-9);
    XCTAssertEqualWithAccuracy(bottom.y, -8.0, 1.0e-9);
    XCTAssertEqualWithAccuracy(bottom.z, -2.0, 1.0e-9);

    NSArray<MDSTube *> *tubes = [configuration detectorTubes];
    XCTAssertEqual(tubes.count, 3);
    XCTAssertEqual(tubes[0].displayNumber, 1);
    XCTAssertEqual(tubes[2].displayNumber, 3);
    XCTAssertEqualWithAccuracy(tubes[1].efficiency, 0.92, 1.0e-12);
}

@end
​​​​​​​​​​​​​