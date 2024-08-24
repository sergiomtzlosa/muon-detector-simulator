#import "MDSTrack.h"

@implementation MDSTrack

- (instancetype)initWithStartPoint:(MDSVector3)startPoint
                          endPoint:(MDSVector3)endPoint
                         direction:(MDSVector3)direction
                    showerParticle:(BOOL)showerParticle
                   crossedTubeMask:(NSUInteger)crossedTubeMask {
    self = [super init];
    if (self) {
        _startPoint = startPoint;
        _endPoint = endPoint;
        _direction = direction;
        _showerParticle = showerParticle;
        _crossedTubeMask = crossedTubeMask;
    }
    return self;
}

@end
​​​​​​​​​​​​​​​