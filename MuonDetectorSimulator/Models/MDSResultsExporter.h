#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class MDSLogEntry;
@class MDSSimulationEngine;

/// Builds self-contained CSV and JSON snapshots of a completed or in-progress
/// simulated run. The reports contain model settings, summary statistics,
/// per-tube totals, the histogram, and the retained event log. The formatters
/// are Foundation-only so they can be tested without AppKit.
@interface MDSResultsExporter : NSObject

+ (NSString *)CSVReportForEngine:(MDSSimulationEngine *)engine
                      logEntries:(NSArray<MDSLogEntry *> *)logEntries
                 logWasTruncated:(BOOL)logWasTruncated;

/// A structured, Foundation-only JSON snapshot of the same run data as the CSV
/// report. The object is suitable for NSJSONSerialization and scripted analysis.
+ (NSDictionary<NSString *, id> *)JSONReportObjectForEngine:(MDSSimulationEngine *)engine
                                                 logEntries:(NSArray<MDSLogEntry *> *)logEntries
                                            logWasTruncated:(BOOL)logWasTruncated;

+ (nullable NSData *)JSONDataForEngine:(MDSSimulationEngine *)engine
                            logEntries:(NSArray<MDSLogEntry *> *)logEntries
                       logWasTruncated:(BOOL)logWasTruncated
                                 error:(NSError **)error;

+ (NSString *)suggestedFileNameForDate:(NSDate *)date;
+ (NSString *)suggestedJSONFileNameForDate:(NSDate *)date;

@end

NS_ASSUME_NONNULL_END
​​​​​​​