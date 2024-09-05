#import "MDSTube.h"

@implementation MDSTube

- (instancetype)initWithTubeIndex:(NSInteger)tubeIndex
                           center:(MDSVector3)center
                           radius:(double)radius
                           length:(double)length
                       efficiency:(double)efficiency {
    self = [super init];
    if (self) {
        _tubeIndex = tubeIndex;
        _displayNumber = tubeIndex + 1;
        _center = center;
        _radius = radius;
        _length = length;
        _efficiency = MIN(MAX(efficiency, 0.0), 1.0);
        _crossSectionArea = M_PI * radius * radius;
    }
    return self;
}

- (BOOL)intersectsRayFrom:(MDSVector3)origin
                direction:(MDSVector3)direction
           entryDistance:(double * _Nullable)entryDistance
            exitDistance:(double * _Nullable)exitDistance {
    return MDSRayCylinderIntersection(origin, direction, self.center, self.radius,
                                      self.length, entryDistance, exitDistance);
}

- (NSString *)description {
    return [NSString stringWithFormat:
            @"<MDSTube %ld center=(%.2f, %.2f, %.2f) length=%.2f radius=%.2f efficiency=%.2f>",
            (long)self.displayNumber, self.center.x, self.center.y, self.center.z,
            self.length, self.radius, self.efficiency];
}

@end
​​​​​​​​​​​​​​​