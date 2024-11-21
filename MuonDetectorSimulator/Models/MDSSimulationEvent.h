#import <Foundation/Foundation.h>

#import "MDSGeometry.h"

NS_ASSUME_NONNULL_BEGIN

@class MDSHit;
@class MDSTrack;

typedef NS_ENUM(NSInteger, MDSSimulationEventKind) {
    MDSSimulationEventKindCosmic = 0,
    MDSSimulationEventKindShower,
    MDSSimulationEventKindBackground,
};

/// A simulated arrival. A cosmic or shower event contains one or more tracks and
/// any resulting tube pulses. A background event contains exactly one hit and no
/// track.
@interface MDSSimulationEvent : NSObject

@property (nonatomic, assign, readonly) uint64_t eventID;
@property (nonatomic, assign, readonly) NSTimeInterval timestamp;
@property (nonatomic, assign, readonly) MDSSimulationEventKind kind;
@property (nonatomic, copy, readonly) NSArray<MDSTrack *> *tracks;
@property (nonatomic, copy, readonly) NSArray<MDSHit *> *hits;
@property (nonatomic, assign, readonly) NSInteger particleCount;
@property (nonatomic, assign, readonly) double primaryAngleFromVertical;
@property (nonatomic, assign, readonly) double primaryAzimuth;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithEventID:(uint64_t)eventID
                      timestamp:(NSTimeInterval)timestamp
                           kind:(MDSSimulationEventKind)kind
                         tracks:(NSArray<MDSTrack *> *)tracks
                           hits:(NSArray<MDSHit *> *)hits
                  particleCount:(NSInteger)particleCount
        primaryAngleFromVertical:(double)primaryAngleFromVertical
                primaryAzimuth:(double)primaryAzimuth NS_DESIGNATED_INITIALIZER;

@property (nonatomic, assign, readonly, getter=isParticleEvent) BOOL particleEvent;

@end

NS_ASSUME_NONNULL_END
​​​​​​​​​​​​​​​​​​