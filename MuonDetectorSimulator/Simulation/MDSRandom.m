#import "MDSRandom.h"

#import <float.h>
#import <math.h>

@implementation MDSRandom {
    uint64_t _state;
    BOOL _hasSpareNormal;
    double _spareNormal;
}

- (instancetype)initWithSeed:(uint64_t)seed {
    self = [super init];
    if (self) {
        _seed = seed;
        _state = seed;
        _hasSpareNormal = NO;
        _spareNormal = 0.0;
    }
    return self;
}

- (uint64_t)nextUInt64 {
    // SplitMix64: fast, well-distributed, and easy to reproduce.
    uint64_t z = (_state += 0x9E3779B97F4A7C15ULL);
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
    return z ^ (z >> 31);
}

- (double)nextUniform {
    return (double)([self nextUInt64] >> 11) * (1.0 / 9007199254740992.0);
}

- (double)uniformFrom:(double)minimum to:(double)maximum {
    if (maximum <= minimum) {
        return minimum;
    }
    return minimum + [self nextUniform] * (maximum - minimum);
}

- (NSUInteger)integerFrom:(NSUInteger)minimum to:(NSUInteger)maximum {
    if (maximum <= minimum) {
        return minimum;
    }
    const NSUInteger span = maximum - minimum + 1;
    return minimum + (NSUInteger)([self nextUniform] * (double)span);
}

- (double)exponentialWithRate:(double)rate {
    if (!isfinite(rate) || rate <= 0.0) {
        return DBL_MAX;
    }
    double uniform = [self nextUniform];
    if (uniform <= DBL_MIN) {
        uniform = DBL_MIN;
    }
    return -log(uniform) / rate;
}

- (double)normalWithMean:(double)mean standardDeviation:(double)standardDeviation {
    if (_hasSpareNormal) {
        _hasSpareNormal = NO;
        return mean + standardDeviation * _spareNormal;
    }

    double u1 = [self nextUniform];
    if (u1 <= DBL_MIN) {
        u1 = DBL_MIN;
    }
    const double u2 = [self nextUniform];
    const double magnitude = sqrt(-2.0 * log(u1));
    const double angle = 2.0 * M_PI * u2;
    _spareNormal = magnitude * sin(angle);
    _hasSpareNormal = YES;
    return mean + standardDeviation * magnitude * cos(angle);
}

@end












