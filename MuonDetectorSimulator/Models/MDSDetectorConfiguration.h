#import <Foundation/Foundation.h>

#import "MDSGeometry.h"

NS_ASSUME_NONNULL_BEGIN

@class MDSTube;

extern NSString *const MDSDetectorConfigurationErrorDomain;

typedef NS_ENUM(NSInteger, MDSConfigurationValidationError) {
    MDSConfigurationValidationErrorDuration = 1,
    MDSConfigurationValidationErrorSpacing,
    MDSConfigurationValidationErrorAlignment,
    MDSConfigurationValidationErrorActiveLength,
    MDSConfigurationValidationErrorActiveDiameter,
    MDSConfigurationValidationErrorEfficiency,
    MDSConfigurationValidationErrorBackgroundRate,
    MDSConfigurationValidationErrorCosmicRate,
    MDSConfigurationValidationErrorCoincidenceWindow,
    MDSConfigurationValidationErrorRequiredTubes,
    MDSConfigurationValidationErrorShowerMultiplicity,
    MDSConfigurationValidationErrorShowerDirection,
    MDSConfigurationValidationErrorShowerSpread,
    MDSConfigurationValidationErrorShowerGeometry,
    MDSConfigurationValidationErrorArrivalDirection,
};

/// How the primary direction of each candidate cosmic event is chosen. The
/// vertical mode is the original simplified model; the random mode samples a
/// downward direction with a cos²θ weighting and keeps candidates whose ray can
/// cross the selected tubes.
typedef NS_ENUM(NSInteger, MDSArrivalDirectionMode) {
    MDSArrivalDirectionModeVertical = 0,
    MDSArrivalDirectionModeRandomRealistic,
};

/// All numeric values in this object are adjustable simulation assumptions. None
/// is a calibration or a measured detector property.
@interface MDSDetectorConfiguration : NSObject <NSCopying>

@property (nonatomic, assign) NSTimeInterval simulationDuration; // seconds
@property (nonatomic, assign) uint64_t randomSeed;

/// Centre-to-centre vertical distance between adjacent tube axes, in centimetres.
@property (nonatomic, assign) double tubeSpacing;
/// Symmetric transverse offset of the top and bottom tube axes, in centimetres.
@property (nonatomic, assign) double alignmentOffset;
@property (nonatomic, assign) double activeLength;
@property (nonatomic, assign) double activeDiameter;

/// Three values in the range 0...1, ordered Tube 1 through Tube 3 (top to bottom).
@property (nonatomic, copy) NSArray<NSNumber *> *tubeEfficiencies;

/// Independent background pulses per second in each tube.
@property (nonatomic, assign) double backgroundRatePerTube;

/// Simplified arrival rate for candidate cosmic-ray tracks.
@property (nonatomic, assign) double cosmicEventRatePerMinute;

/// Selects a fixed vertical direction or a seeded, realistic random direction
/// for each candidate event. Shower particles follow the chosen primary axis.
@property (nonatomic, assign) MDSArrivalDirectionMode arrivalDirectionMode;

@property (nonatomic, assign) double coincidenceWindowMicroseconds;

/// Bits 0, 1 and 2 select Tube 1, Tube 2 and Tube 3. At least two must be set.
@property (nonatomic, assign) NSUInteger requiredTubeMask;

@property (nonatomic, assign, getter=isShowerModeEnabled) BOOL showerModeEnabled;
/// Polar angle measured from the downward vertical, in degrees.
@property (nonatomic, assign) double primaryAngleFromVertical;
/// Azimuth around the downward vertical, in degrees.
@property (nonatomic, assign) double primaryAzimuth;
/// Total simulated particles per shower, including the primary.
@property (nonatomic, assign) NSInteger showerMultiplicity;
@property (nonatomic, assign) double showerAngularSpread;

+ (instancetype)defaultConfiguration;

- (BOOL)validate:(NSError **)error;

- (double)tubeRadius;
- (double)activeCrossSectionArea;
- (NSArray<NSNumber *> *)requiredTubeIndices;
- (NSString *)coincidenceDescription;
- (MDSVector3)centerForTubeAtIndex:(NSInteger)index;

/// Convenience geometry array used by both the simulator and the 3D view.
- (NSArray<MDSTube *> *)detectorTubes;

@end

NS_ASSUME_NONNULL_END
