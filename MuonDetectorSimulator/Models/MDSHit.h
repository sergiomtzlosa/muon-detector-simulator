#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// One recorded electrical pulse from a simulated tube. The timestamp is the
/// simulated pulse time in seconds, not wall-clock time.
@interface MDSHit : NSObject

@property (nonatomic, assign, readonly) uint64_t hitID;
@property (nonatomic, assign, readonly) NSInteger tubeIndex;
@property (nonatomic, assign, readonly) NSTimeInterval timestamp;
@property (nonatomic, assign, readonly) uint64_t sourceEventID;
@property (nonatomic, assign, readonly, getter=isBackground) BOOL background;

/// Used by the coincidence finder. A pulse can participate in at most one
/// accepted coincidence.
@property (nonatomic, assign, getter=isConsumed) BOOL consumed;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithHitID:(uint64_t)hitID
                    tubeIndex:(NSInteger)tubeIndex
                    timestamp:(NSTimeInterval)timestamp
                sourceEventID:(uint64_t)sourceEventID
                   background:(BOOL)background NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
​​​​​​​