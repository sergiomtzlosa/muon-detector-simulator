#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class MDSCoincidence;
@class MDSSimulationEvent;

/// The ordered output of one simulation advance.
@interface MDSBatch : NSObject

@property (nonatomic, copy, readonly) NSArray<MDSSimulationEvent *> *events;
@property (nonatomic, copy, readonly) NSArray<MDSCoincidence *> *coincidences;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithEvents:(NSArray<MDSSimulationEvent *> *)events
                  coincidences:(NSArray<MDSCoincidence *> *)coincidences
    NS_DESIGNATED_INITIALIZER;

@property (nonatomic, assign, readonly) BOOL isEmpty;

@end

NS_ASSUME_NONNULL_END
​​​​​​