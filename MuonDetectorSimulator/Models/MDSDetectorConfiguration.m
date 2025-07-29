#import "MDSDetectorConfiguration.h"

#import "MDSTube.h"

NSString *const MDSDetectorConfigurationErrorDomain =
    @"MDSDetectorConfigurationErrorDomain";

static NSError *MDSConfigurationError(MDSConfigurationValidationError code,
                                      NSString *description,
                                      NSString *suggestion) {
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    userInfo[NSLocalizedDescriptionKey] = description;
    if (suggestion.length > 0) {
        userInfo[NSLocalizedRecoverySuggestionErrorKey] = suggestion;
    }
    return [NSError errorWithDomain:MDSDetectorConfigurationErrorDomain
                               code:code
                           userInfo:userInfo];
}

@interface MDSDetectorConfiguration ()
- (NSUInteger)bitCountForMask:(NSUInteger)mask;
@end

@implementation MDSDetectorConfiguration

+ (instancetype)defaultConfiguration {
    MDSDetectorConfiguration *configuration = [[self alloc] init];
    configuration.simulationDuration = 60.0;
    configuration.randomSeed = 12345;
    configuration.tubeSpacing = 6.0;
    configuration.alignmentOffset = 0.0;
    configuration.activeLength = 10.0;
    configuration.activeDiameter = 1.4;
    configuration.tubeEfficiencies = @[ @0.90, @0.92, @0.88 ];
    configuration.backgroundRatePerTube = 2.0;
    configuration.cosmicEventRatePerMinute = 30.0;
    configuration.arrivalDirectionMode = MDSArrivalDirectionModeVertical;
    configuration.coincidenceWindowMicroseconds = 1.0;
    configuration.requiredTubeMask = 0x7;
    configuration.showerModeEnabled = NO;
    configuration.primaryAngleFromVertical = 10.0;
    configuration.primaryAzimuth = 30.0;
    configuration.showerMultiplicity = 6;
    configuration.showerAngularSpread = 8.0;
    return configuration;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _tubeEfficiencies = @[ @0.90, @0.92, @0.88 ];
        _arrivalDirectionMode = MDSArrivalDirectionModeVertical;
        _requiredTubeMask = 0x7;
        _showerMultiplicity = 6;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    MDSDetectorConfiguration *copy =
        [[[self class] allocWithZone:zone] init];
    copy.simulationDuration = self.simulationDuration;
    copy.randomSeed = self.randomSeed;
    copy.tubeSpacing = self.tubeSpacing;
    copy.alignmentOffset = self.alignmentOffset;
    copy.activeLength = self.activeLength;
    copy.activeDiameter = self.activeDiameter;
    copy.tubeEfficiencies = self.tubeEfficiencies;
    copy.backgroundRatePerTube = self.backgroundRatePerTube;
    copy.cosmicEventRatePerMinute = self.cosmicEventRatePerMinute;
    copy.arrivalDirectionMode = self.arrivalDirectionMode;
    copy.coincidenceWindowMicroseconds = self.coincidenceWindowMicroseconds;
    copy.requiredTubeMask = self.requiredTubeMask;
    copy.showerModeEnabled = self.showerModeEnabled;
    copy.primaryAngleFromVertical = self.primaryAngleFromVertical;
    copy.primaryAzimuth = self.primaryAzimuth;
    copy.showerMultiplicity = self.showerMultiplicity;
    copy.showerAngularSpread = self.showerAngularSpread;
    return copy;
}

- (BOOL)validate:(NSError **)error {
    if (!isfinite(self.simulationDuration) ||
        self.simulationDuration < 1.0 ||
        self.simulationDuration > 86400.0) {
        if (error) {
            *error = MDSConfigurationError(
                MDSConfigurationValidationErrorDuration,
                @"Simulation duration is outside the supported range.",
                @"Choose a simulated duration between 1 second and 24 hours.");
        }
        return NO;
    }

    if (!isfinite(self.tubeSpacing) || self.tubeSpacing < 0.5 ||
        self.tubeSpacing > 100.0) {
        if (error) {
            *error = MDSConfigurationError(
                MDSConfigurationValidationErrorSpacing,
                @"Tube spacing is outside the supported range.",
                @"Choose a centre-to-centre spacing between 0.5 cm and 100 cm.");
        }
        return NO;
    }

    if (!isfinite(self.alignmentOffset) || self.alignmentOffset < 0.0 ||
        self.alignmentOffset > 25.0) {
        if (error) {
            *error = MDSConfigurationError(
                MDSConfigurationValidationErrorAlignment,
                @"Tube alignment offset is outside the supported range.",
                @"Choose an offset between 0 cm and 25 cm.");
        }
        return NO;
    }

    if (!isfinite(self.activeLength) || self.activeLength < 1.0 ||
        self.activeLength > 100.0) {
        if (error) {
            *error = MDSConfigurationError(
                MDSConfigurationValidationErrorActiveLength,
                @"The tube's active length is outside the supported range.",
                @"Choose an active length between 1 cm and 100 cm.");
        }
        return NO;
    }

    if (!isfinite(self.activeDiameter) || self.activeDiameter < 0.2 ||
        self.activeDiameter > 20.0) {
        if (error) {
            *error = MDSConfigurationError(
                MDSConfigurationValidationErrorActiveDiameter,
                @"The tube's active diameter is outside the supported range.",
                @"Choose an active diameter between 0.2 cm and 20 cm.");
        }
        return NO;
    }

    if (self.tubeSpacing < self.activeDiameter) {
        if (error) {
            *error = MDSConfigurationError(
                MDSConfigurationValidationErrorSpacing,
                @"Adjacent active volumes overlap.",
                @"Increase tube spacing so it is at least as large as the active diameter.");
        }
        return NO;
    }

    if (self.tubeEfficiencies.count != 3) {
        if (error) {
            *error = MDSConfigurationError(
                MDSConfigurationValidationErrorEfficiency,
                @"Each of the three tubes needs a detection efficiency.",
                @"Provide three efficiency values.");
        }
        return NO;
    }

    for (NSNumber *efficiency in self.tubeEfficiencies) {
        const double value = efficiency.doubleValue;
        if (!isfinite(value) || value < 0.0 || value > 1.0) {
            if (error) {
                *error = MDSConfigurationError(
                    MDSConfigurationValidationErrorEfficiency,
                    @"A tube efficiency is outside the valid range.",
                    @"Set each efficiency between 0% and 100%.");
            }
            return NO;
        }
    }

    if (!isfinite(self.backgroundRatePerTube) ||
        self.backgroundRatePerTube < 0.0 ||
        self.backgroundRatePerTube > 1000.0) {
        if (error) {
            *error = MDSConfigurationError(
                MDSConfigurationValidationErrorBackgroundRate,
                @"Background count rate is outside the supported range.",
                @"Choose a background rate between 0 and 1000 pulses per second per tube.");
        }
        return NO;
    }

    if (!isfinite(self.cosmicEventRatePerMinute) ||
        self.cosmicEventRatePerMinute < 0.0 ||
        self.cosmicEventRatePerMinute > 100000.0) {
        if (error) {
            *error = MDSConfigurationError(
                MDSConfigurationValidationErrorCosmicRate,
                @"Cosmic event rate is outside the supported range.",
                @"Choose a simplified event rate between 0 and 100000 events per minute.");
        }
        return NO;
    }

    if (self.arrivalDirectionMode != MDSArrivalDirectionModeVertical &&
        self.arrivalDirectionMode != MDSArrivalDirectionModeRandomRealistic) {
        if (error) {
            *error = MDSConfigurationError(
                MDSConfigurationValidationErrorArrivalDirection,
                @"The arrival-direction model is invalid.",
                @"Choose vertical or random realistic arrival directions.");
        }
        return NO;
    }

    if (!isfinite(self.coincidenceWindowMicroseconds) ||
        self.coincidenceWindowMicroseconds <= 0.0 ||
        self.coincidenceWindowMicroseconds > 1000000.0) {
        if (error) {
            *error = MDSConfigurationError(
                MDSConfigurationValidationErrorCoincidenceWindow,
                @"Coincidence window is outside the supported range.",
                @"Choose a positive coincidence window in microseconds.");
        }
        return NO;
    }

    if (self.requiredTubeMask == 0 ||
        (self.requiredTubeMask & ~(NSUInteger)0x7) != 0) {
        if (error) {
            *error = MDSConfigurationError(
                MDSConfigurationValidationErrorRequiredTubes,
                @"The required-tube selection is invalid.",
                @"Select Tube 1, Tube 2, or Tube 3 using a valid combination.");
        }
        return NO;
    }

    if ([self bitCountForMask:self.requiredTubeMask] < 2) {
        if (error) {
            *error = MDSConfigurationError(
                MDSConfigurationValidationErrorRequiredTubes,
                @"At least two tubes are required for a coincidence.",
                @"Select a two-fold or three-fold combination of tubes.");
        }
        return NO;
    }

    if (self.showerMultiplicity < 1 || self.showerMultiplicity > 30) {
        if (error) {
            *error = MDSConfigurationError(
                MDSConfigurationValidationErrorShowerMultiplicity,
                @"Shower multiplicity is outside the supported range.",
                @"Choose between 1 and 30 particles per shower.");
        }
        return NO;
    }

    if (!isfinite(self.primaryAngleFromVertical) ||
        self.primaryAngleFromVertical < 0.0 ||
        self.primaryAngleFromVertical > 85.0) {
        if (error) {
            *error = MDSConfigurationError(
                MDSConfigurationValidationErrorShowerDirection,
                @"Primary-particle angle is outside the supported range.",
                @"Choose an angle between 0° and 85° from the downward vertical.");
        }
        return NO;
    }

    if (!isfinite(self.primaryAzimuth) ||
        self.primaryAzimuth < 0.0 || self.primaryAzimuth > 360.0) {
        if (error) {
            *error = MDSConfigurationError(
                MDSConfigurationValidationErrorShowerDirection,
                @"Primary-particle azimuth is outside the supported range.",
                @"Choose an azimuth between 0° and 360°.");
        }
        return NO;
    }

    if (!isfinite(self.showerAngularSpread) ||
        self.showerAngularSpread < 0.0 ||
        self.showerAngularSpread > 80.0) {
        if (error) {
            *error = MDSConfigurationError(
                MDSConfigurationValidationErrorShowerSpread,
                @"Shower angular spread is outside the supported range.",
                @"Choose an angular spread between 0° and 80°.");
        }
        return NO;
    }

    // Random arrival mode chooses a safe primary axis below the horizon, so the
    // configured fallback axis does not constrain the shower cone in that mode.
    if (self.isShowerModeEnabled &&
        self.arrivalDirectionMode == MDSArrivalDirectionModeVertical &&
        self.primaryAngleFromVertical + self.showerAngularSpread > 85.0) {
        if (error) {
            *error = MDSConfigurationError(
                MDSConfigurationValidationErrorShowerGeometry,
                @"The shower cone extends above the horizontal.",
                @"Keep the primary angle plus the angular spread at or below 85°.");
        }
        return NO;
    }

    return YES;
}

- (NSUInteger)bitCountForMask:(NSUInteger)mask {
    NSUInteger count = 0;
    while (mask != 0) {
        count += (mask & 1u);
        mask >>= 1;
    }
    return count;
}

- (double)tubeRadius {
    return self.activeDiameter * 0.5;
}

- (double)activeCrossSectionArea {
    return M_PI * self.tubeRadius * self.tubeRadius;
}

- (NSArray<NSNumber *> *)requiredTubeIndices {
    NSMutableArray<NSNumber *> *indices = [NSMutableArray arrayWithCapacity:3];
    for (NSInteger index = 0; index < 3; index++) {
        if ((self.requiredTubeMask & (1u << index)) != 0) {
            [indices addObject:@(index)];
        }
    }
    return indices;
}

- (NSString *)coincidenceDescription {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSNumber *number in [self requiredTubeIndices]) {
        [names addObject:[NSString stringWithFormat:@"Tube %ld",
                          (long)number.integerValue + 1]];
    }
    NSString *suffix = [self bitCountForMask:self.requiredTubeMask] == 3
        ? @"3-fold" : @"2-fold";
    return [NSString stringWithFormat:@"%@ · %@", [names componentsJoinedByString:@" + "],
            suffix];
}

- (MDSVector3)centerForTubeAtIndex:(NSInteger)index {
    const double verticalIndex = 1.0 - (double)index;
    return MDSVector3Make(0.0,
                          verticalIndex * self.tubeSpacing,
                          verticalIndex * self.alignmentOffset);
}

- (NSArray<MDSTube *> *)detectorTubes {
    NSMutableArray<MDSTube *> *tubes = [NSMutableArray arrayWithCapacity:3];
    for (NSInteger index = 0; index < 3; index++) {
        NSNumber *efficiency = self.tubeEfficiencies[index];
        MDSTube *tube =
            [[MDSTube alloc] initWithTubeIndex:index
                                        center:[self centerForTubeAtIndex:index]
                                        radius:[self tubeRadius]
                                        length:self.activeLength
                                    efficiency:efficiency.doubleValue];
        [tubes addObject:tube];
    }
    return tubes;
}

@end















