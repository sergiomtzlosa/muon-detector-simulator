#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class MDSConfigurationViewController;

typedef NS_ENUM(NSInteger, MDSPlaybackState) {
    MDSPlaybackStateIdle = 0,
    MDSPlaybackStateRunning,
    MDSPlaybackStatePaused,
    MDSPlaybackStateFinished,
};

/// Coordinates transport state, the simulation clock, results, the event log and
/// the SceneKit presentation. The window controller and application menu route
/// their simulation actions through this object.
@interface MDSMainViewController : NSViewController

@property (nonatomic, assign, readonly) MDSPlaybackState playbackState;
@property (nonatomic, strong, readonly) MDSConfigurationViewController *configurationViewController;

- (instancetype)init;

- (void)startSimulation:(nullable id)sender;
- (void)pauseSimulation:(nullable id)sender;
- (void)resumeSimulation:(nullable id)sender;
- (void)stepSimulation:(nullable id)sender;
- (void)resetSimulation:(nullable id)sender;

- (void)resetDetectorView:(nullable id)sender;
- (void)toggleLabels:(nullable id)sender;
- (void)showHowItWorks:(nullable id)sender;
- (void)exportJSONResults:(nullable id)sender;
- (void)exportCSVResults:(nullable id)sender;

- (BOOL)canStartSimulation;
- (BOOL)canExportResults;
- (BOOL)canPauseSimulation;
- (BOOL)canResumeSimulation;
- (BOOL)canStepSimulation;
- (BOOL)canResetSimulation;
- (BOOL)areSceneLabelsVisible;
- (void)setSceneLabelsVisible:(BOOL)visible;
- (BOOL)areTracksFading;
- (void)setTracksFading:(BOOL)fading;

#if DEBUG
/// Used only by the local, debug-build snapshot harness for layout verification.
- (nullable NSImage *)debugSnapshotImage;
- (nullable NSImage *)debugInspectorSnapshotImage;
#endif

@end

NS_ASSUME_NONNULL_END









