#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class MDSMainWindowController;

/// Owns the application lifecycle, menu bar, About panel and the single main
/// window. All simulation logic is delegated to the main view controller.
@interface MDSAppDelegate : NSObject <NSApplicationDelegate, NSMenuItemValidation>

@property (nonatomic, strong, readonly) MDSMainWindowController *mainWindowController;

- (void)exportJSONResults:(nullable id)sender;
- (void)exportCSVResults:(nullable id)sender;
- (void)toggleFadeTracks:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
