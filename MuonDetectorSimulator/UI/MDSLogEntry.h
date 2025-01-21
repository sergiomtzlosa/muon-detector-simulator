#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class MDSHit;
@class MDSCoincidence;
@class MDSSimulationEvent;

typedef NS_ENUM(NSInteger, MDSLogEntryStyle) {
    MDSLogEntryStyleNeutral = 0,
    MDSLogEntryStyleParticle,
    MDSLogEntryStyleBackground,
    MDSLogEntryStyleCoincidence,
};

FOUNDATION_EXPORT NSString *MDSFormatSimulatedTime(NSTimeInterval seconds);
FOUNDATION_EXPORT NSString *MDSFormatHitList(NSArray<MDSHit *> *hits);

/// View model for one row in the scrolling event log.
@interface MDSLogEntry : NSObject

@property (nonatomic, assign, readonly) NSTimeInterval timestamp;
@property (nonatomic, copy, readonly) NSString *timeText;
@property (nonatomic, copy, readonly) NSString *sourceText;
@property (nonatomic, copy, readonly) NSString *detailsText;
@property (nonatomic, copy, readonly) NSString *resultText;
@property (nonatomic, assign, readonly) MDSLogEntryStyle style;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithTimestamp:(NSTimeInterval)timestamp
                         timeText:(NSString *)timeText
                       sourceText:(NSString *)sourceText
                      detailsText:(NSString *)detailsText
                       resultText:(NSString *)resultText
                            style:(MDSLogEntryStyle)style NS_DESIGNATED_INITIALIZER;

+ (instancetype)entryForEvent:(MDSSimulationEvent *)event;
+ (instancetype)entryForCoincidence:(MDSCoincidence *)coincidence;

@end

NS_ASSUME_NONNULL_END


