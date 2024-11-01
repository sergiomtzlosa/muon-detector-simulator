#import <Foundation/Foundation.h>

#import "MDSGeometry.h"

NS_ASSUME_NONNULL_BEGIN

/// Display geometry for one simulated particle. The engine owns the physics; the
/// SceneKit controller only renders this resolved ray.
@interface MDSTrack : NSObject

@property (nonatomic, assign, readonly) MDSVector3 startPoint;
@property (nonatomic, assign, readonly) MDSVector3 endPoint;
@property (nonatomic, assign, readonly) MDSVector3 direction;
@property (nonatomic, assign, readonly, getter=isShowerParticle) BOOL showerParticle;

/// Bit n is set when this track crossed the active volume of tube n.
@property (nonatomic, assign, readonly) NSUInteger crossedTubeMask;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithStartPoint:(MDSVector3)startPoint
                          endPoint:(MDSVector3)endPoint
                         direction:(MDSVector3)direction
                    showerParticle:(BOOL)showerParticle
                   crossedTubeMask:(NSUInteger)crossedTubeMask NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
​​​​​​​​​​​​​​​​​​​​