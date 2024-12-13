#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// A point or direction in detector space. One scene unit represents one centimetre.
typedef struct {
    double x;
    double y;
    double z;
} MDSVector3;

static inline MDSVector3 MDSVector3Make(double x, double y, double z) {
    MDSVector3 v;
    v.x = x;
    v.y = y;
    v.z = z;
    return v;
}

static inline MDSVector3 MDSVector3Add(MDSVector3 a, MDSVector3 b) {
    return MDSVector3Make(a.x + b.x, a.y + b.y, a.z + b.z);
}

static inline MDSVector3 MDSVector3Subtract(MDSVector3 a, MDSVector3 b) {
    return MDSVector3Make(a.x - b.x, a.y - b.y, a.z - b.z);
}

static inline MDSVector3 MDSVector3Multiply(MDSVector3 v, double scalar) {
    return MDSVector3Make(v.x * scalar, v.y * scalar, v.z * scalar);
}

static inline double MDSVector3Dot(MDSVector3 a, MDSVector3 b) {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

static inline MDSVector3 MDSVector3Cross(MDSVector3 a, MDSVector3 b) {
    return MDSVector3Make(a.y * b.z - a.z * b.y,
                          a.z * b.x - a.x * b.z,
                          a.x * b.y - a.y * b.x);
}

static inline double MDSVector3Length(MDSVector3 v) {
    return sqrt(MDSVector3Dot(v, v));
}

static inline MDSVector3 MDSVector3Normalized(MDSVector3 v) {
    const double length = MDSVector3Length(v);
    if (length < 1.0e-12) {
        return MDSVector3Make(0.0, 0.0, 0.0);
    }
    return MDSVector3Multiply(v, 1.0 / length);
}

static inline double MDSVector3Distance(MDSVector3 a, MDSVector3 b) {
    return MDSVector3Length(MDSVector3Subtract(a, b));
}

FOUNDATION_EXPORT BOOL MDSRayCylinderIntersection(MDSVector3 rayOrigin,
                                                  MDSVector3 rayDirection,
                                                  MDSVector3 cylinderCenter,
                                                  double radius,
                                                  double length,
                                                  double * _Nullable entryDistance,
                                                  double * _Nullable exitDistance);

FOUNDATION_EXPORT NSString *MDSFormatAngle(double degrees);
FOUNDATION_EXPORT NSString *MDSFormatDistance(double centimetres);

NS_ASSUME_NONNULL_END
​​​​​​​​​​​​​​​​​​​​