#import "MDSGeometry.h"

#import <float.h>

BOOL MDSRayCylinderIntersection(MDSVector3 rayOrigin,
                                MDSVector3 rayDirection,
                                MDSVector3 cylinderCenter,
                                double radius,
                                double length,
                                double *entryDistance,
                                double *exitDistance) {
    if (radius <= 0.0 || length <= 0.0) {
        return NO;
    }

    const MDSVector3 direction = MDSVector3Normalized(rayDirection);
    if (MDSVector3Length(direction) < 0.5) {
        return NO;
    }

    const MDSVector3 localOrigin = MDSVector3Subtract(rayOrigin, cylinderCenter);
    const double halfLength = length * 0.5;
    const double radialDirectionSquared =
        direction.y * direction.y + direction.z * direction.z;

    double intervalStart = 0.0;
    double intervalEnd = 0.0;

    if (radialDirectionSquared < 1.0e-12) {
        // The ray is parallel to the tube axis. A hit is possible only when the
        // ray's transverse coordinates are inside the active radius.
        if (localOrigin.y * localOrigin.y + localOrigin.z * localOrigin.z >
            radius * radius) {
            return NO;
        }

        if (fabs(direction.x) < 1.0e-12) {
            if (fabs(localOrigin.x) > halfLength) {
                return NO;
            }
            intervalStart = 0.0;
            intervalEnd = DBL_MAX;
        } else {
            double first = (-halfLength - localOrigin.x) / direction.x;
            double second = (halfLength - localOrigin.x) / direction.x;
            if (first > second) {
                double temporary = first;
                first = second;
                second = temporary;
            }
            intervalStart = MAX(first, 0.0);
            intervalEnd = second;
        }
    } else {
        const double a = radialDirectionSquared;
        const double b = 2.0 * (localOrigin.y * direction.y +
                                localOrigin.z * direction.z);
        const double c = localOrigin.y * localOrigin.y +
                         localOrigin.z * localOrigin.z - radius * radius;
        const double discriminant = b * b - 4.0 * a * c;
        if (discriminant < 0.0) {
            return NO;
        }

        const double root = sqrt(MAX(discriminant, 0.0));
        double radialEnter = (-b - root) / (2.0 * a);
        double radialExit = (-b + root) / (2.0 * a);
        if (radialEnter > radialExit) {
            double temporary = radialEnter;
            radialEnter = radialExit;
            radialExit = temporary;
        }

        double axialEnter = -DBL_MAX;
        double axialExit = DBL_MAX;
        if (fabs(direction.x) > 1.0e-12) {
            axialEnter = (-halfLength - localOrigin.x) / direction.x;
            axialExit = (halfLength - localOrigin.x) / direction.x;
            if (axialEnter > axialExit) {
                double temporary = axialEnter;
                axialEnter = axialExit;
                axialExit = temporary;
            }
        } else if (fabs(localOrigin.x) > halfLength) {
            return NO;
        }

        intervalStart = MAX(radialEnter, axialEnter);
        intervalEnd = MIN(radialExit, axialExit);
    }

    intervalStart = MAX(intervalStart, 0.0);
    if (intervalEnd < intervalStart || intervalEnd < 0.0) {
        return NO;
    }

    if (entryDistance != NULL) {
        *entryDistance = intervalStart;
    }
    if (exitDistance != NULL) {
        *exitDistance = intervalEnd;
    }
    return YES;
}

NSString *MDSFormatAngle(double degrees) {
    return [NSString stringWithFormat:@"%.0f°", degrees];
}

NSString *MDSFormatDistance(double centimetres) {
    return [NSString stringWithFormat:@"%.1f cm", centimetres];
}




