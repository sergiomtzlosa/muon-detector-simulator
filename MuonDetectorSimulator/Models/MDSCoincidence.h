#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class MDSHit;

/// An accepted coincidence formed from one pulse in every required tube.
@interface MDSCoincidence : NSObject

@property (nonatomic, assign, readonly) NSTimeInterval timestamp;
@property (nonatomic, copy, readonly) NSArray<NSNumber *> *tubeIndices;
@property (nonatomic, copy, readonly) NSArray<MDSHit *> *hits;
@property (nonatomic, copy, readonly) NSArray<NSNumber *> *sourceEventIDs;
@property (nonatomic, assign, readonly) NSInteger fold;

/// True when contributing pulses came from more than one candidate event or
/// included independent background pulses.
@property (nonatomic, assign, readonly, getter=isAccidental) BOOL accidental;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithTimestamp:(NSTimeInterval)timestamp
                      tubeIndices:(NSArray<NSNumber *> *)tubeIndices
                             hits:(NSArray<MDSHit *> *)hits
                  sourceEventIDs:(NSArray<NSNumber *> *)sourceEventIDs
                      accidental:(BOOL)accidental NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
