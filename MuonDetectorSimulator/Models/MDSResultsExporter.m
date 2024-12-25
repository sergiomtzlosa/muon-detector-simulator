#import "MDSResultsExporter.h"

#import "MDSDetectorConfiguration.h"
#import "MDSLogEntry.h"
#import "MDSSimulationEngine.h"

static NSString *MDSResultsCSVEscape(NSString *value) {
    NSString *text = value ?: @"";
    text = [text stringByReplacingOccurrencesOfString:@"\""
                                           withString:@"\"\""];
    return [NSString stringWithFormat:@"\"%@\"", text];
}

static void MDSResultsAppendRow(NSMutableString *csv,
                                NSArray<NSString *> *fields) {
    NSMutableArray<NSString *> *escaped =
        [NSMutableArray arrayWithCapacity:fields.count];
    for (NSString *field in fields) {
        [escaped addObject:MDSResultsCSVEscape(field)];
    }
    [csv appendString:[escaped componentsJoinedByString:@","]];
    [csv appendString:@"\r\n"];
}

static void MDSResultsAppendBlankRow(NSMutableString *csv) {
    [csv appendString:@"\r\n"];
}

static NSString *MDSResultsFormatNumber(double value, NSUInteger digits) {
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    formatter.usesGroupingSeparator = NO;
    formatter.minimumFractionDigits = digits;
    formatter.maximumFractionDigits = digits;
    return [formatter stringFromNumber:@(value)] ?: @"0";
}

static NSString *MDSResultsBoolString(BOOL value) {
    return value ? @"Yes" : @"No";
}

static NSString *MDSResultsArrivalDirectionName(MDSArrivalDirectionMode mode) {
    return mode == MDSArrivalDirectionModeRandomRealistic
        ? @"random_realistic"
        : @"vertical";
}

static NSString *MDSResultsArrivalDirectionDescription(MDSArrivalDirectionMode mode) {
    return mode == MDSArrivalDirectionModeRandomRealistic
        ? @"Random realistic (cos^2(theta) weighting, downward, up to 80 degrees from vertical, selected-tube acceptance)"
        : @"Vertical (simplified)";
}

static NSString *MDSResultsLogStyleName(MDSLogEntryStyle style) {
    switch (style) {
        case MDSLogEntryStyleParticle:
            return @"particle";
        case MDSLogEntryStyleBackground:
            return @"background";
        case MDSLogEntryStyleCoincidence:
            return @"coincidence";
        case MDSLogEntryStyleNeutral:
        default:
            return @"neutral";
    }
}

static NSString *MDSResultsFormattedDateStamp(NSDate *date) {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.dateFormat = @"yyyy-MM-dd 'at' HH-mm-ss";
    return [formatter stringFromDate:date ?: [NSDate date]] ?: @"";
}

static NSString *MDSResultsISO8601Timestamp(void) {
    NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
    formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime |
        NSISO8601DateFormatWithFractionalSeconds;
    return [formatter stringFromDate:[NSDate date]] ?: @"";
}

@implementation MDSResultsExporter

+ (NSString *)CSVReportForEngine:(MDSSimulationEngine *)engine
                      logEntries:(NSArray<MDSLogEntry *> *)logEntries
                 logWasTruncated:(BOOL)logWasTruncated {
    NSParameterAssert(engine != nil);

    MDSDetectorConfiguration *configuration = engine.configuration;
    NSMutableString *csv = [NSMutableString string];

    MDSResultsAppendRow(csv, @[ @"Muon Detector Simulator - simulated results" ]);
    MDSResultsAppendRow(csv, @[
        @"Simulation only. No detector hardware was contacted and this is not a radiation measurement."
    ]);
    MDSResultsAppendRow(csv, @[
        @"The model does not identify a particle or measure its mass or energy."
    ]);
    MDSResultsAppendBlankRow(csv);

    MDSResultsAppendRow(csv, @[ @"CONFIGURATION" ]);
    MDSResultsAppendRow(csv, @[ @"Field", @"Value" ]);
    MDSResultsAppendRow(csv, @[ @"Random seed",
        [NSString stringWithFormat:@"%llu", configuration.randomSeed] ]);
    MDSResultsAppendRow(csv, @[ @"Simulated duration (s)",
        MDSResultsFormatNumber(configuration.simulationDuration, 3) ]);
    MDSResultsAppendRow(csv, @[ @"Arrival direction model",
        configuration.arrivalDirectionMode == MDSArrivalDirectionModeRandomRealistic
            ? @"Random realistic (cos^2(theta) weighting, downward)"
            : @"Vertical (simplified)" ]);
    MDSResultsAppendRow(csv, @[ @"Primary axis source",
        configuration.arrivalDirectionMode == MDSArrivalDirectionModeRandomRealistic
            ? @"Sampled per event"
            : @"Configured fixed direction" ]);
    MDSResultsAppendRow(csv, @[ @"Shower mode",
        MDSResultsBoolString(configuration.isShowerModeEnabled) ]);
    MDSResultsAppendRow(csv, @[ @"Configured primary angle (deg from vertical)",
        MDSResultsFormatNumber(configuration.primaryAngleFromVertical, 3) ]);
    MDSResultsAppendRow(csv, @[ @"Configured primary azimuth (deg)",
        MDSResultsFormatNumber(configuration.primaryAzimuth, 3) ]);
    MDSResultsAppendRow(csv, @[ @"Shower multiplicity",
        [NSString stringWithFormat:@"%ld", (long)configuration.showerMultiplicity] ]);
    MDSResultsAppendRow(csv, @[ @"Shower angular spread (deg)",
        MDSResultsFormatNumber(configuration.showerAngularSpread, 3) ]);
    MDSResultsAppendRow(csv, @[ @"Tube spacing (cm)",
        MDSResultsFormatNumber(configuration.tubeSpacing, 3) ]);
    MDSResultsAppendRow(csv, @[ @"Top/bottom alignment offset (cm)",
        MDSResultsFormatNumber(configuration.alignmentOffset, 3) ]);
    MDSResultsAppendRow(csv, @[ @"Active length (cm)",
        MDSResultsFormatNumber(configuration.activeLength, 3) ]);
    MDSResultsAppendRow(csv, @[ @"Active diameter (cm)",
        MDSResultsFormatNumber(configuration.activeDiameter, 3) ]);
    MDSResultsAppendRow(csv, @[ @"Background rate per tube (pulses/s)",
        MDSResultsFormatNumber(configuration.backgroundRatePerTube, 3) ]);
    MDSResultsAppendRow(csv, @[ @"Cosmic event rate (events/min)",
        MDSResultsFormatNumber(configuration.cosmicEventRatePerMinute, 3) ]);
    MDSResultsAppendRow(csv, @[ @"Coincidence window (microseconds)",
        MDSResultsFormatNumber(configuration.coincidenceWindowMicroseconds, 3) ]);
    MDSResultsAppendRow(csv, @[ @"Required tube mask",
        [NSString stringWithFormat:@"0x%lX",
         (unsigned long)configuration.requiredTubeMask] ]);
    MDSResultsAppendRow(csv, @[ @"Required coincidence",
        [configuration coincidenceDescription] ]);
    MDSResultsAppendBlankRow(csv);

    MDSResultsAppendRow(csv, @[ @"SUMMARY" ]);
    MDSResultsAppendRow(csv, @[ @"Metric", @"Value" ]);
    MDSResultsAppendRow(csv, @[ @"Simulated time (s)",
        MDSResultsFormatNumber(engine.currentTime, 6) ]);
    MDSResultsAppendRow(csv, @[ @"Configured duration (s)",
        MDSResultsFormatNumber(engine.simulationDuration, 3) ]);
    MDSResultsAppendRow(csv, @[ @"Complete",
        MDSResultsBoolString(engine.isFinished) ]);
    MDSResultsAppendRow(csv, @[ @"Total tube hits",
        [NSString stringWithFormat:@"%lu", (unsigned long)engine.totalHitCount] ]);
    MDSResultsAppendRow(csv, @[ @"Candidate cosmic events",
        [NSString stringWithFormat:@"%lu",
         (unsigned long)engine.cosmicCandidateCount] ]);
    MDSResultsAppendRow(csv, @[ @"Shower events",
        [NSString stringWithFormat:@"%lu", (unsigned long)engine.showerEventCount] ]);
    MDSResultsAppendRow(csv, @[ @"Background events",
        [NSString stringWithFormat:@"%lu",
         (unsigned long)engine.backgroundEventCount] ]);
    MDSResultsAppendRow(csv, @[ @"Total simulated particles",
        [NSString stringWithFormat:@"%lu", (unsigned long)engine.totalParticleCount] ]);
    MDSResultsAppendRow(csv, @[ @"Accepted coincidences",
        [NSString stringWithFormat:@"%lu",
         (unsigned long)engine.acceptedCoincidenceCount] ]);
    MDSResultsAppendRow(csv, @[ @"2-fold coincidences",
        [NSString stringWithFormat:@"%lu",
         (unsigned long)engine.twoFoldCoincidenceCount] ]);
    MDSResultsAppendRow(csv, @[ @"3-fold coincidences",
        [NSString stringWithFormat:@"%lu",
         (unsigned long)engine.threeFoldCoincidenceCount] ]);
    MDSResultsAppendRow(csv, @[ @"Accidental coincidences",
        [NSString stringWithFormat:@"%lu",
         (unsigned long)engine.accidentalCoincidenceCount] ]);
    MDSResultsAppendRow(csv, @[ @"Coincidence rate (accepted/simulated min)",
        MDSResultsFormatNumber(engine.acceptedCoincidenceRatePerMinute, 3) ]);
    MDSResultsAppendRow(csv, @[ @"Event log rows exported",
        [NSString stringWithFormat:@"%lu", (unsigned long)logEntries.count] ]);
    MDSResultsAppendRow(csv, @[ @"Event log truncated at source",
        MDSResultsBoolString(logWasTruncated) ]);
    MDSResultsAppendBlankRow(csv);

    MDSResultsAppendRow(csv, @[ @"TUBE TOTALS" ]);
    MDSResultsAppendRow(csv, @[ @"Tube", @"Hits", @"Detection efficiency (%)" ]);
    NSArray<NSNumber *> *hitCounts = engine.hitCountsPerTube;
    for (NSInteger index = 0; index < 3; index++) {
        NSNumber *count = index < (NSInteger)hitCounts.count
            ? hitCounts[(NSUInteger)index] : @0;
        NSNumber *efficiency = index < (NSInteger)configuration.tubeEfficiencies.count
            ? configuration.tubeEfficiencies[(NSUInteger)index] : @0;
        MDSResultsAppendRow(csv, @[
            [NSString stringWithFormat:@"Tube %ld", (long)index + 1],
            [NSString stringWithFormat:@"%lu",
             (unsigned long)count.unsignedIntegerValue],
            MDSResultsFormatNumber(efficiency.doubleValue * 100.0, 1),
        ]);
    }
    MDSResultsAppendBlankRow(csv);

    MDSResultsAppendRow(csv, @[ @"HISTOGRAM" ]);
    MDSResultsAppendRow(csv, @[
        @"Bin start (s)", @"Bin end (s)", @"Tube hits", @"Accepted coincidences"
    ]);
    NSArray<NSNumber *> *hitHistogram = engine.histogramHitCounts;
    NSArray<NSNumber *> *coincidenceHistogram = engine.histogramCoincidenceCounts;
    const NSUInteger binCount = engine.histogramBinCount;
    const double binWidth = binCount > 0
        ? engine.simulationDuration / (double)binCount : 0.0;
    for (NSUInteger index = 0; index < binCount; index++) {
        const double start = (double)index * binWidth;
        const double end = MIN(engine.simulationDuration,
                               (double)(index + 1) * binWidth);
        const NSUInteger hits = index < hitHistogram.count
            ? hitHistogram[index].unsignedIntegerValue : 0;
        const NSUInteger coincidences = index < coincidenceHistogram.count
            ? coincidenceHistogram[index].unsignedIntegerValue : 0;
        MDSResultsAppendRow(csv, @[
            MDSResultsFormatNumber(start, 6),
            MDSResultsFormatNumber(end, 6),
            [NSString stringWithFormat:@"%lu", (unsigned long)hits],
            [NSString stringWithFormat:@"%lu", (unsigned long)coincidences],
        ]);
    }
    MDSResultsAppendBlankRow(csv);

    MDSResultsAppendRow(csv, @[ @"EVENT LOG" ]);
    MDSResultsAppendRow(csv, @[
        @"Simulated time (s)", @"Display time", @"Source", @"Details", @"Result"
    ]);
    for (MDSLogEntry *entry in logEntries) {
        MDSResultsAppendRow(csv, @[
            MDSResultsFormatNumber(entry.timestamp, 6),
            entry.timeText,
            entry.sourceText,
            entry.detailsText,
            entry.resultText,
        ]);
    }
    MDSResultsAppendBlankRow(csv);

    MDSResultsAppendRow(csv, @[ @"NOTES" ]);
    MDSResultsAppendRow(csv, @[
        @"Log retention",
        logWasTruncated
            ? @"Only the latest 3,000 event-log rows are included; summary counts and histogram bins are complete."
            : @"All retained event-log rows are included."
    ]);
    MDSResultsAppendRow(csv, @[
        @"Modeling limits",
        @"Poisson arrivals, a simplified aperture, independent background pulses, and fixed 0.025 microsecond timing jitter are modeled assumptions."
    ]);

    return [csv copy];
}

+ (NSDictionary<NSString *, id> *)JSONReportObjectForEngine:(MDSSimulationEngine *)engine
                                                 logEntries:(NSArray<MDSLogEntry *> *)logEntries
                                            logWasTruncated:(BOOL)logWasTruncated {
    NSParameterAssert(engine != nil);

    MDSDetectorConfiguration *configuration = engine.configuration;
    NSArray<NSNumber *> *requiredTubeIndices = [configuration requiredTubeIndices];
    NSArray<NSNumber *> *efficiencies = configuration.tubeEfficiencies;

    NSMutableArray<NSNumber *> *requiredTubes =
        [NSMutableArray arrayWithCapacity:requiredTubeIndices.count];
    for (NSNumber *index in requiredTubeIndices) {
        [requiredTubes addObject:@(index.integerValue + 1)];
    }

    NSArray<NSNumber *> *hitCounts = engine.hitCountsPerTube;
    NSMutableArray<NSDictionary<NSString *, id> *> *tubeTotals =
        [NSMutableArray arrayWithCapacity:3];
    for (NSInteger index = 0; index < 3; index++) {
        NSNumber *hits = index < (NSInteger)hitCounts.count
            ? hitCounts[(NSUInteger)index] : @0;
        NSNumber *efficiency = index < (NSInteger)efficiencies.count
            ? efficiencies[(NSUInteger)index] : @0;
        [tubeTotals addObject:@{
            @"tube": @(index + 1),
            @"hits": hits,
            @"detection_efficiency": efficiency,
            @"required": @([requiredTubeIndices containsObject:@(index)]),
        }];
    }

    NSArray<NSNumber *> *hitHistogram = engine.histogramHitCounts;
    NSArray<NSNumber *> *coincidenceHistogram = engine.histogramCoincidenceCounts;
    const NSUInteger binCount = engine.histogramBinCount;
    const double binWidth = binCount > 0
        ? engine.simulationDuration / (double)binCount : 0.0;
    NSMutableArray<NSDictionary<NSString *, id> *> *bins =
        [NSMutableArray arrayWithCapacity:binCount];
    for (NSUInteger index = 0; index < binCount; index++) {
        const double start = (double)index * binWidth;
        const double end = MIN(engine.simulationDuration,
                               (double)(index + 1) * binWidth);
        const NSUInteger hits = index < hitHistogram.count
            ? hitHistogram[index].unsignedIntegerValue : 0;
        const NSUInteger coincidences = index < coincidenceHistogram.count
            ? coincidenceHistogram[index].unsignedIntegerValue : 0;
        [bins addObject:@{
            @"index": @(index),
            @"start_seconds": @(start),
            @"end_seconds": @(end),
            @"tube_hits": @(hits),
            @"accepted_coincidences": @(coincidences),
        }];
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *logRows =
        [NSMutableArray arrayWithCapacity:logEntries.count];
    for (MDSLogEntry *entry in logEntries) {
        [logRows addObject:@{
            @"timestamp_seconds": @(entry.timestamp),
            @"display_time": entry.timeText,
            @"source": entry.sourceText,
            @"details": entry.detailsText,
            @"result": entry.resultText,
            @"style": MDSResultsLogStyleName(entry.style),
        }];
    }

    NSString *retentionDescription = logWasTruncated
        ? @"Only the latest 3,000 event-log rows are included; summary counts and histogram bins are complete."
        : @"All retained event-log rows are included.";

    return @{
        @"application": @"Muon Detector Simulator",
        @"report_type": @"simulated_detector_results",
        @"report_version": @1,
        @"generated_at": MDSResultsISO8601Timestamp(),
        @"simulation_only": @YES,
        @"disclaimer": @"Simulation only. No detector hardware was contacted and this is not a radiation measurement. The model does not identify a particle or measure its mass or energy.",
        @"configuration": @{
            @"random_seed": @(configuration.randomSeed),
            @"simulation_duration_seconds": @(configuration.simulationDuration),
            @"arrival_direction": @{
                @"mode": MDSResultsArrivalDirectionName(configuration.arrivalDirectionMode),
                @"description": MDSResultsArrivalDirectionDescription(configuration.arrivalDirectionMode),
            },
            @"shower": @{
                @"enabled": @(configuration.isShowerModeEnabled),
                @"primary_angle_degrees_from_vertical": @(configuration.primaryAngleFromVertical),
                @"primary_azimuth_degrees": @(configuration.primaryAzimuth),
                @"multiplicity": @(configuration.showerMultiplicity),
                @"angular_spread_degrees": @(configuration.showerAngularSpread),
            },
            @"geometry": @{
                @"tube_spacing_cm": @(configuration.tubeSpacing),
                @"alignment_offset_cm": @(configuration.alignmentOffset),
                @"active_length_cm": @(configuration.activeLength),
                @"active_diameter_cm": @(configuration.activeDiameter),
            },
            @"detection": @{
                @"tube_efficiencies": efficiencies,
                @"background_rate_per_tube_per_second": @(configuration.backgroundRatePerTube),
                @"cosmic_event_rate_per_minute": @(configuration.cosmicEventRatePerMinute),
                @"coincidence_window_microseconds": @(configuration.coincidenceWindowMicroseconds),
            },
            @"coincidence_requirement": @{
                @"required_tube_mask": @(configuration.requiredTubeMask),
                @"required_tubes": requiredTubes,
                @"fold": @(requiredTubes.count),
                @"description": [configuration coincidenceDescription],
            },
        },
        @"simulation": @{
            @"current_time_seconds": @(engine.currentTime),
            @"duration_seconds": @(engine.simulationDuration),
            @"complete": @(engine.isFinished),
        },
        @"summary": @{
            @"total_tube_hits": @(engine.totalHitCount),
            @"candidate_cosmic_events": @(engine.cosmicCandidateCount),
            @"shower_events": @(engine.showerEventCount),
            @"background_events": @(engine.backgroundEventCount),
            @"total_simulated_particles": @(engine.totalParticleCount),
            @"accepted_coincidences": @(engine.acceptedCoincidenceCount),
            @"two_fold_coincidences": @(engine.twoFoldCoincidenceCount),
            @"three_fold_coincidences": @(engine.threeFoldCoincidenceCount),
            @"accidental_coincidences": @(engine.accidentalCoincidenceCount),
            @"coincidence_rate_per_simulated_minute": @(engine.acceptedCoincidenceRatePerMinute),
            @"event_log_rows": @(logEntries.count),
        },
        @"tube_totals": tubeTotals,
        @"histogram": @{
            @"bin_count": @(binCount),
            @"bin_width_seconds": @(binWidth),
            @"bins": bins,
        },
        @"event_log": logRows,
        @"log_retention": @{
            @"retained_rows": @(logEntries.count),
            @"truncated": @(logWasTruncated),
            @"description": retentionDescription,
        },
        @"modeling_notes": @[
            @"Poisson arrivals, a simplified aperture, independent background pulses, and fixed 0.025 microsecond timing jitter are modeled assumptions.",
            @"The candidate cosmic rate is not a calibrated muon flux.",
            @"Detection efficiencies, geometry, background, timing, and shower parameters are adjustable assumptions, not calibrations.",
        ],
    };
}

+ (nullable NSData *)JSONDataForEngine:(MDSSimulationEngine *)engine
                            logEntries:(NSArray<MDSLogEntry *> *)logEntries
                       logWasTruncated:(BOOL)logWasTruncated
                                 error:(NSError **)error {
    NSDictionary<NSString *, id> *object =
        [self JSONReportObjectForEngine:engine
                             logEntries:logEntries
                        logWasTruncated:logWasTruncated];
    return [NSJSONSerialization dataWithJSONObject:object
                                           options:(NSJSONWritingPrettyPrinted |
                                                    NSJSONWritingSortedKeys)
                                             error:error];
}

+ (NSString *)suggestedFileNameForDate:(NSDate *)date {
    return [NSString stringWithFormat:@"Muon Detector Results %@.csv",
            MDSResultsFormattedDateStamp(date)];
}

+ (NSString *)suggestedJSONFileNameForDate:(NSDate *)date {
    return [NSString stringWithFormat:@"Muon Detector Results %@.json",
            MDSResultsFormattedDateStamp(date)];
}

@end
​​​​​​​​​​​​​​​​​​​​​​​​​​