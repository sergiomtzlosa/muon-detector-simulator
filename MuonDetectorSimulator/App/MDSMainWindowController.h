#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class MDSMainViewController;

/// Creates and owns the standard titled application window.
@interface MDSMainWindowController : NSWindowController

@property (nonatomic, strong, readonly) MDSMainViewController *mainViewController;

@end

NS_ASSUME_NONNULL_END





