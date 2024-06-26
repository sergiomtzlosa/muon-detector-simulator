#import <Foundation/Foundation.h>

#import "MDSGeometry.h"

NS_ASSUME_NONNULL_BEGIN

/// A single Geiger–Müller tube model. Tubes are centred in detector space and
/// their active gas volume is a finite cylinder whose axis is parallel to X.
@interface MDSTube : NSObject

@property (nonatomic, assign, readonly) NSInteger tubeIndex;

/// One-based number shown to the user (Tube 1, Tube 2, Tube 3).
@property (nonatomic, assign, readonly) NSInteger displayNumber;
@property (nonatomic, assign, readonly) MDSVector3 center;
@property (nonatomic, assign, readonly) double radius;
@property (nonatomic, assign, readonly) double length;

/// Detection probability in the range 0...1.
@property (nonatomic, assign, readonly) double efficiency;

@property (nonatomic, assign, readonly) double crossSectionArea;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithTubeIndex:(NSInteger)tubeIndex
                           center:(MDSVector3)center
                           radius:(double)radius
                           length:(double)length
                       efficiency:(double)efficiency NS_DESIGNATED_INITIALIZER;

- (BOOL)intersectsRayFrom:(MDSVector3)origin
                direction:(MDSVector3)direction
           entryDistance:(double * _Nullable)entryDistance
            exitDistance:(double * _Nullable)exitDistance;

@end

NS_ASSUME_NONNULL_END
​​​​​​​​​