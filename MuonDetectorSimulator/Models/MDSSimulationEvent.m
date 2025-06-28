#import "MDSSimulationEvent.h"

#import "MDSHit.h"
#import "MDSTrack.h"

@implementation MDSSimulationEvent

- (instancetype)initWithEventID:(uint64_t)eventID
                      timestamp:(NSTimeInterval)timestamp
                           kind:(MDSSimulationEventKind)kind
                         tracks:(NSArray<MDSTrack *> *)tracks
                           hits:(NSArray<MDSHit *> *)hits
                  particleCount:(NSInteger)particleCount
        primaryAngleFromVertical:(double)primaryAngleFromVertical
                primaryAzimuth:(double)primaryAzimuth {
    self = [super init];
    if (self) {
        _eventID = eventID;
        _timestamp = timestamp;
        _kind = kind;
        _tracks = [tracks copy];
        _hits = [hits copy];
        _particleCount = particleCount;
        _primaryAngleFromVertical = primaryAngleFromVertical;
        _primaryAzimuth = primaryAzimuth;
    }
    return self;
}

- (BOOL)isParticleEvent {
    return self.kind != MDSSimulationEventKindBackground;
}

- (NSString *)description {
    static NSString *kindNames[] = { @"cosmic", @"shower", @"background" };
    return [NSString stringWithFormat:
            @"<MDSSimulationEvent %llu %@ t=%.6f tracks=%lu hits=%lu>",
            self.eventID, kindNames[self.kind], self.timestamp,
            (unsigned long)self.tracks.count, (unsigned long)self.hits.count];
}

@end














