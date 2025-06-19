#import <XCTest/XCTest.h>

#import "MDSBatch.h"
#import "MDSCoincidence.h"
#import "MDSDetectorConfiguration.h"
#import "MDSLogEntry.h"
#import "MDSResultsExporter.h"
#import "MDSSimulationEngine.h"
#import "MDSSimulationEvent.h"

@interface MDSResultsExporterTests : XCTestCase
@end

@implementation MDSResultsExporterTests

- (void)testCSVReportIncludesConfigurationSummaryHistogramAndLog {
    MDSDetectorConfiguration *configuration =
        [MDSDetectorConfiguration defaultConfiguration];
    configuration.simulationDuration = 20.0;
    configuration.randomSeed = 424242;
    configuration.backgroundRatePerTube = 1.0;
    configuration.cosmicEventRatePerMinute = 120.0;
    configuration.arrivalDirectionMode =
        MDSArrivalDirectionModeRandomRealistic;

    NSError *error = nil;
    MDSSimulationEngine *engine =
        [[MDSSimulationEngine alloc] initWithConfiguration:configuration
                                                     error:&error];
    XCTAssertNotNil(engine);
    XCTAssertNil(error);

    MDSBatch *batch = [engine advanceToTime:20.0];
    NSMutableArray<MDSLogEntry *> *entries = [NSMutableArray array];
    for (MDSSimulationEvent *event in batch.events) {
        [entries addObject:[MDSLogEntry entryForEvent:event]];
    }
    for (MDSCoincidence *coincidence in batch.coincidences) {
        [entries addObject:[MDSLogEntry entryForCoincidence:coincidence]];
    }
    [entries addObject:[[MDSLogEntry alloc]
        initWithTimestamp:1.25
                 timeText:@"00:01.250"
               sourceText:@"Custom, source"
              detailsText:@"A value with \"quotes\""
               resultText:@"No tube hits"
                    style:MDSLogEntryStyleNeutral]];

    NSString *csv = [MDSResultsExporter CSVReportForEngine:engine
                                                logEntries:entries
                                           logWasTruncated:NO];
    XCTAssertTrue([csv containsString:@"Simulation only"]);
    XCTAssertTrue([csv containsString:@"not a radiation measurement"]);
    XCTAssertTrue([csv containsString:@"CONFIGURATION"]);
    XCTAssertTrue([csv containsString:@"\"Random seed\",\"424242\""]);
    XCTAssertTrue([csv containsString:@"Random realistic"]);
    XCTAssertTrue([csv containsString:@"Primary axis source"]);
    XCTAssertTrue([csv containsString:@"Sampled per event"]);
    XCTAssertTrue([csv containsString:@"\"Complete\",\"Yes\""]);
    XCTAssertTrue([csv containsString:@"\"Total tube hits\""]);
    XCTAssertTrue([csv containsString:@"\"TUBE TOTALS\""]);
    XCTAssertTrue([csv containsString:@"\"Tube 1\""]);
    XCTAssertTrue([csv containsString:@"\"HISTOGRAM\""]);
    XCTAssertTrue([csv containsString:@"\"EVENT LOG\""]);
    XCTAssertTrue([csv containsString:@"\"Custom, source\""]);
    XCTAssertTrue([csv containsString:@"\"A value with \"\"quotes\"\"\""]);
    XCTAssertTrue([csv containsString:@"All retained event-log rows are included."]);
}

- (void)testCSVReportMarksTruncatedLog {
    MDSDetectorConfiguration *configuration =
        [MDSDetectorConfiguration defaultConfiguration];
    NSError *error = nil;
    MDSSimulationEngine *engine =
        [[MDSSimulationEngine alloc] initWithConfiguration:configuration
                                                     error:&error];
    XCTAssertNotNil(engine);

    NSString *csv = [MDSResultsExporter CSVReportForEngine:engine
                                                logEntries:@[]
                                           logWasTruncated:YES];
    XCTAssertTrue([csv containsString:
        @"Only the latest 3,000 event-log rows are included"]);
    XCTAssertTrue([csv containsString:@"\"Event log truncated at source\",\"Yes\""]);
}

- (void)testJSONReportContainsStructuredConfigurationSummaryHistogramAndLog {
    MDSDetectorConfiguration *configuration =
        [MDSDetectorConfiguration defaultConfiguration];
    configuration.simulationDuration = 20.0;
    configuration.randomSeed = 424242;
    configuration.backgroundRatePerTube = 1.0;
    configuration.cosmicEventRatePerMinute = 120.0;
    configuration.arrivalDirectionMode =
        MDSArrivalDirectionModeRandomRealistic;

    NSError *error = nil;
    MDSSimulationEngine *engine =
        [[MDSSimulationEngine alloc] initWithConfiguration:configuration
                                                     error:&error];
    XCTAssertNotNil(engine);
    XCTAssertNil(error);

    MDSBatch *batch = [engine advanceToTime:20.0];
    NSMutableArray<MDSLogEntry *> *entries = [NSMutableArray array];
    for (MDSSimulationEvent *event in batch.events) {
        [entries addObject:[MDSLogEntry entryForEvent:event]];
    }
    for (MDSCoincidence *coincidence in batch.coincidences) {
        [entries addObject:[MDSLogEntry entryForCoincidence:coincidence]];
    }
    [entries addObject:[[MDSLogEntry alloc]
        initWithTimestamp:1.25
                 timeText:@"00:01.250"
               sourceText:@"Custom, source"
              detailsText:@"A value with \"quotes\""
               resultText:@"No tube hits"
                    style:MDSLogEntryStyleNeutral]];

    NSDictionary<NSString *, id> *object =
        [MDSResultsExporter JSONReportObjectForEngine:engine
                                          logEntries:entries
                                     logWasTruncated:NO];
    XCTAssertEqualObjects(object[@"application"], @"Muon Detector Simulator");
    XCTAssertEqualObjects(object[@"report_type"], @"simulated_detector_results");
    XCTAssertEqualObjects(object[@"simulation_only"], @YES);
    XCTAssertTrue([object[@"generated_at"] length] > 0);

    NSDictionary<NSString *, id> *config = object[@"configuration"];
    XCTAssertEqualObjects(config[@"random_seed"], @424242);
    NSDictionary<NSString *, id> *arrival = config[@"arrival_direction"];
    XCTAssertEqualObjects(arrival[@"mode"], @"random_realistic");
    NSDictionary<NSString *, id> *requirement =
        config[@"coincidence_requirement"];
    XCTAssertEqualObjects(requirement[@"required_tubes"], (@[ @1, @2, @3 ]));
    XCTAssertEqualObjects(requirement[@"fold"], @3);

    NSDictionary<NSString *, id> *summary = object[@"summary"];
    XCTAssertEqualObjects(summary[@"event_log_rows"], @(entries.count));
    XCTAssertEqual([object[@"tube_totals"] count], (NSUInteger)3);
    XCTAssertEqual([object[@"histogram"][@"bins"] count], (NSUInteger)120);

    NSArray<NSDictionary<NSString *, id> *> *eventRows = object[@"event_log"];
    XCTAssertEqual(eventRows.count, entries.count);
    XCTAssertEqualObjects(eventRows.lastObject[@"source"], @"Custom, source");
    XCTAssertEqualObjects(eventRows.lastObject[@"style"], @"neutral");

    NSDictionary<NSString *, id> *retention = object[@"log_retention"];
    XCTAssertEqualObjects(retention[@"truncated"], @NO);

    error = nil;
    NSData *data = [MDSResultsExporter JSONDataForEngine:engine
                                              logEntries:entries
                                         logWasTruncated:NO
                                                   error:&error];
    XCTAssertNotNil(data);
    XCTAssertNil(error);
    NSDictionary<NSString *, id> *roundTrip =
        [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    XCTAssertNotNil(roundTrip);
    XCTAssertNil(error);
    XCTAssertEqualObjects(roundTrip[@"report_type"],
                          @"simulated_detector_results");
}

- (void)testJSONReportMarksTruncatedLog {
    MDSDetectorConfiguration *configuration =
        [MDSDetectorConfiguration defaultConfiguration];
    NSError *error = nil;
    MDSSimulationEngine *engine =
        [[MDSSimulationEngine alloc] initWithConfiguration:configuration
                                                     error:&error];
    XCTAssertNotNil(engine);

    NSDictionary<NSString *, id> *object =
        [MDSResultsExporter JSONReportObjectForEngine:engine
                                          logEntries:@[]
                                     logWasTruncated:YES];
    NSDictionary<NSString *, id> *retention = object[@"log_retention"];
    XCTAssertEqualObjects(retention[@"truncated"], @YES);
    XCTAssertTrue([retention[@"description"]
        containsString:@"Only the latest 3,000 event-log rows"]);
}

- (void)testSuggestedJSONFileNameHasStablePrefixAndExtension {
    NSString *name = [MDSResultsExporter
        suggestedJSONFileNameForDate:[NSDate dateWithTimeIntervalSince1970:0]];
    XCTAssertTrue([name hasPrefix:@"Muon Detector Results "]);
    XCTAssertTrue([name hasSuffix:@".json"]);
}

- (void)testSuggestedFileNameHasStablePrefixAndCSVExtension {
    NSString *name = [MDSResultsExporter
        suggestedFileNameForDate:[NSDate dateWithTimeIntervalSince1970:0]];
    XCTAssertTrue([name hasPrefix:@"Muon Detector Results "]);
    XCTAssertTrue([name hasSuffix:@".csv"]);
}

@end













