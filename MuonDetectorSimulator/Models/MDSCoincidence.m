#import "MDSCoincidence.h"

#import "MDSHit.h"

@implementation MDSCoincidence

- (instancetype)initWithTimestamp:(NSTimeInterval)timestamp
                      tubeIndices:(NSArray<NSNumber *> *)tubeIndices
                             hits:(NSArray<MDSHit *> *)hits
                  sourceEventIDs:(NSArray<NSNumber *> *)sourceEventIDs
                      accidental:(BOOL)accidental {
    self = [super init];
    if (self) {
        _timestamp = timestamp;
        _tubeIndices = [tubeIndices copy];
        _hits = [hits copy];
        _sourceEventIDs = [sourceEventIDs copy];
        _fold = (NSInteger)_tubeIndices.count;
        _accidental = accidental;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<MDSCoincidence %ld-fold t=%.9f sources=%@>",
            (long)self.fold, self.timestamp, self.sourceEventIDs];
}

@end
​​​​​​​​​​​​​​