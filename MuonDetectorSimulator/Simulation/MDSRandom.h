#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Small deterministic PRNG (SplitMix64) used by the simulation. It is deliberately
/// independent of UIKit/AppKit and of wall-clock time, so the same seed and
/// configuration produce the same event sequence.
@interface MDSRandom : NSObject

@property (nonatomic, assign, readonly) uint64_t seed;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithSeed:(uint64_t)seed NS_DESIGNATED_INITIALIZER;

- (uint64_t)nextUInt64;
- (double)nextUniform; // [0, 1)
- (double)uniformFrom:(double)minimum to:(double)maximum;
- (NSUInteger)integerFrom:(NSUInteger)minimum to:(NSUInteger)maximum;
- (double)exponentialWithRate:(double)rate;
- (double)normalWithMean:(double)mean standardDeviation:(double)standardDeviation;

@end

NS_ASSUME_NONNULL_END
​​​​​​​​​