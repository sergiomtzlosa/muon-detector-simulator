#import <XCTest/XCTest.h>

#import "MDSRandom.h"

@interface MDSRandomTests : XCTestCase
@end

@implementation MDSRandomTests

- (void)testSameSeedProducesIdenticalSequence {
    MDSRandom *first = [[MDSRandom alloc] initWithSeed:0x123456789ABCDEF0ULL];
    MDSRandom *second = [[MDSRandom alloc] initWithSeed:0x123456789ABCDEF0ULL];

    for (NSInteger index = 0; index < 1000; index++) {
        XCTAssertEqual([first nextUInt64], [second nextUInt64]);
    }
}

- (void)testDifferentSeedsDiverge {
    MDSRandom *first = [[MDSRandom alloc] initWithSeed:1];
    MDSRandom *second = [[MDSRandom alloc] initWithSeed:2];

    NSInteger equalDraws = 0;
    for (NSInteger index = 0; index < 100; index++) {
        if ([first nextUInt64] == [second nextUInt64]) {
            equalDraws += 1;
        }
    }
    XCTAssertEqual(equalDraws, 0);
}

- (void)testUniformValuesStayInRange {
    MDSRandom *random = [[MDSRandom alloc] initWithSeed:99];
    for (NSInteger index = 0; index < 10000; index++) {
        const double value = [random nextUniform];
        XCTAssertGreaterThanOrEqual(value, 0.0);
        XCTAssertLessThan(value, 1.0);
    }

    for (NSInteger index = 0; index < 1000; index++) {
        const double value = [random uniformFrom:-2.5 to:7.5];
        XCTAssertGreaterThanOrEqual(value, -2.5);
        XCTAssertLessThan(value, 7.5);
    }
}

- (void)testIntegerDrawsIncludeBothEndsAndDoNotExceedRange {
    MDSRandom *random = [[MDSRandom alloc] initWithSeed:11];
    BOOL sawMinimum = NO;
    BOOL sawMaximum = NO;
    for (NSInteger index = 0; index < 2000; index++) {
        const NSUInteger value = [random integerFrom:2 to:5];
        XCTAssertGreaterThanOrEqual(value, 2);
        XCTAssertLessThanOrEqual(value, 5);
        sawMinimum = sawMinimum || value == 2;
        sawMaximum = sawMaximum || value == 5;
    }
    XCTAssertTrue(sawMinimum);
    XCTAssertTrue(sawMaximum);
}

- (void)testStatisticalDrawsHaveExpectedScale {
    MDSRandom *exponentialRandom = [[MDSRandom alloc] initWithSeed:44];
    double exponentialSum = 0.0;
    const NSInteger exponentialCount = 20000;
    for (NSInteger index = 0; index < exponentialCount; index++) {
        const double value = [exponentialRandom exponentialWithRate:10.0];
        XCTAssertGreaterThanOrEqual(value, 0.0);
        exponentialSum += value;
    }
    XCTAssertEqualWithAccuracy(exponentialSum / exponentialCount, 0.1, 0.004);

    MDSRandom *normalRandom = [[MDSRandom alloc] initWithSeed:45];
    double normalSum = 0.0;
    double squareSum = 0.0;
    const NSInteger normalCount = 20000;
    for (NSInteger index = 0; index < normalCount; index++) {
        const double value = [normalRandom normalWithMean:3.0
                                        standardDeviation:2.0];
        normalSum += value;
        squareSum += value * value;
    }
    const double mean = normalSum / normalCount;
    const double variance = squareSum / normalCount - mean * mean;
    XCTAssertEqualWithAccuracy(mean, 3.0, 0.06);
    XCTAssertEqualWithAccuracy(sqrt(variance), 2.0, 0.06);
}

@end
​​​​​​​​​​​​​​​​​​​​​​​​​