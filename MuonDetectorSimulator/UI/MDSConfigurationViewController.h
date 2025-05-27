#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class MDSConfigurationViewController;
@class MDSDetectorConfiguration;

@protocol MDSConfigurationViewControllerDelegate <NSObject>
- (void)configurationViewController:(MDSConfigurationViewController *)controller
            didChangeConfiguration:(MDSDetectorConfiguration *)configuration
                    validationError:(nullable NSError *)validationError
                      playbackSpeed:(double)playbackSpeed;
- (void)configurationViewControllerDidRequestHelp:
    (MDSConfigurationViewController *)controller;
@end

/// Scrollable inspector for all user-adjustable model assumptions. The controller
/// validates cross-field constraints and disables editing while a run is active.
@interface MDSConfigurationViewController : NSViewController

@property (nonatomic, weak) id<MDSConfigurationViewControllerDelegate> delegate;
@property (nonatomic, copy, readonly) MDSDetectorConfiguration *configuration;
@property (nonatomic, assign, readonly) double playbackSpeed;
@property (nonatomic, assign, readonly, getter=isConfigurationValid) BOOL configurationValid;
@property (nonatomic, assign, readonly, getter=areControlsEnabled) BOOL controlsEnabled;

- (instancetype)initWithConfiguration:(MDSDetectorConfiguration *)configuration;

- (void)setControlsEnabled:(BOOL)enabled;
- (void)setConfiguration:(MDSDetectorConfiguration *)configuration;

@end

NS_ASSUME_NONNULL_END








