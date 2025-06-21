#import "MDSHit.h"

@implementation MDSHit

- (instancetype)initWithHitID:(uint64_t)hitID
                    tubeIndex:(NSInteger)tubeIndex
                    timestamp:(NSTimeInterval)timestamp
                sourceEventID:(uint64_t)sourceEventID
                   background:(BOOL)background {
    self = [super init];
    if (self) {
        _hitID = hitID;
        _tubeIndex = tubeIndex;
        _timestamp = timestamp;
        _sourceEventID = sourceEventID;
        _background = background;
        _consumed = NO;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:
            @"<MDSHit %llu tube=%ld t=%.9f source=%llu%@>",
            self.hitID, (long)(self.tubeIndex + 1), self.timestamp,
            self.sourceEventID, self.isBackground ? @" background" : @""];
}

@end

















