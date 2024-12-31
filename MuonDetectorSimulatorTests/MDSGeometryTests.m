#import <XCTest/XCTest.h>

#import "MDSGeometry.h"
#import "MDSTube.h"

@interface MDSGeometryTests : XCTestCase
@end

@implementation MDSGeometryTests

- (void)testRayAlongCylinderAxisUsesEndCaps {
    double entry = 0.0;
    double exit = 0.0;
    const BOOL intersects = MDSRayCylinderIntersection(
        MDSVector3Make(-10.0, 0.0, 0.0),
        MDSVector3Make(1.0, 0.0, 0.0),
        MDSVector3Make(0.0, 0.0, 0.0),
        1.0, 10.0, &entry, &exit);

    XCTAssertTrue(intersects);
    XCTAssertEqualWithAccuracy(entry, 5.0, 1.0e-9);
    XCTAssertEqualWithAccuracy(exit, 15.0, 1.0e-9);
}

- (void)testRayStartingInsideCylinderStartsAtZero {
    double entry = -1.0;
    double exit = -1.0;
    const BOOL intersects = MDSRayCylinderIntersection(
        MDSVector3Make(0.0, 0.0, 0.0),
        MDSVector3Make(1.0, 0.0, 0.0),
        MDSVector3Make(0.0, 0.0, 0.0),
        1.0, 10.0, &entry, &exit);

    XCTAssertTrue(intersects);
    XCTAssertEqualWithAccuracy(entry, 0.0, 1.0e-9);
    XCTAssertEqualWithAccuracy(exit, 5.0, 1.0e-9);
}

- (void)testRayPerpendicularToAxisUsesRadialBounds {
    double entry = 0.0;
    double exit = 0.0;
    const BOOL intersects = MDSRayCylinderIntersection(
        MDSVector3Make(0.0, 2.0, 0.0),
        MDSVector3Make(0.0, -1.0, 0.0),
        MDSVector3Make(0.0, 0.0, 0.0),
        1.0, 10.0, &entry, &exit);

    XCTAssertTrue(intersects);
    XCTAssertEqualWithAccuracy(entry, 1.0, 1.0e-9);
    XCTAssertEqualWithAccuracy(exit, 3.0, 1.0e-9);
}

- (void)testRayMissesCylinderRadially {
    double entry = 0.0;
    double exit = 0.0;
    const BOOL intersects = MDSRayCylinderIntersection(
        MDSVector3Make(-10.0, 2.0, 0.0),
        MDSVector3Make(1.0, 0.0, 0.0),
        MDSVector3Make(0.0, 0.0, 0.0),
        1.0, 10.0, &entry, &exit);

    XCTAssertFalse(intersects);
}

- (void)testPerpendicularRayOutsideEndCapMissesCylinder {
    double entry = 0.0;
    double exit = 0.0;
    const BOOL intersects = MDSRayCylinderIntersection(
        MDSVector3Make(-6.0, 0.0, 0.0),
        MDSVector3Make(0.0, 1.0, 0.0),
        MDSVector3Make(0.0, 0.0, 0.0),
        1.0, 10.0, &entry, &exit);

    XCTAssertFalse(intersects);
}

- (void)testDiagonalRayUsesEndCapAndRadialIntersections {
    double entry = 0.0;
    double exit = 0.0;
    const BOOL intersects = MDSRayCylinderIntersection(
        MDSVector3Make(-10.0, 0.0, 0.0),
        MDSVector3Make(1.0, 0.1, 0.0),
        MDSVector3Make(0.0, 0.0, 0.0),
        1.0, 10.0, &entry, &exit);

    XCTAssertTrue(intersects);
    XCTAssertGreaterThan(entry, 0.0);
    XCTAssertGreaterThan(exit, entry);
    XCTAssertLessThan(exit, 16.0);
}

- (void)testZeroDirectionIsRejected {
    double entry = 0.0;
    double exit = 0.0;
    XCTAssertFalse(MDSRayCylinderIntersection(
        MDSVector3Make(-2.0, 0.0, 0.0),
        MDSVector3Make(0.0, 0.0, 0.0),
        MDSVector3Make(0.0, 0.0, 0.0),
        1.0, 10.0, &entry, &exit));
}

- (void)testTubeDelegatesToGeometryAndClampsEfficiency {
    MDSTube *tube = [[MDSTube alloc] initWithTubeIndex:1
                                                center:MDSVector3Make(0.0, 6.0, 0.0)
                                                radius:0.7
                                                length:10.0
                                            efficiency:1.8];
    XCTAssertEqual(tube.displayNumber, 2);
    XCTAssertEqualWithAccuracy(tube.efficiency, 1.0, 1.0e-12);
    XCTAssertEqualWithAccuracy(tube.crossSectionArea, M_PI * 0.7 * 0.7, 1.0e-12);

    double entry = 0.0;
    double exit = 0.0;
    XCTAssertTrue([tube intersectsRayFrom:MDSVector3Make(0.0, 10.0, 0.0)
                               direction:MDSVector3Make(0.0, -1.0, 0.0)
                          entryDistance:&entry
                           exitDistance:&exit]);
    XCTAssertEqualWithAccuracy(entry, 3.3, 1.0e-9);
    XCTAssertEqualWithAccuracy(exit, 4.7, 1.0e-9);
}

@end

