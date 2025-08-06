#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class MDSDetectorConfiguration;
@class MDSHit;
@class MDSSimulationEvent;

/// Presentation-only filter for the recent particle tracks. It never changes
/// which events the simulation generates or how tube hits are processed.
typedef NS_ENUM(NSInteger, MDSTrackDisplayFilter) {
    MDSTrackDisplayFilterAll = 0,
    MDSTrackDisplayFilterMuons,
    MDSTrackDisplayFilterShowers,
};

/// Owns the SceneKit world. This controller deliberately contains no simulation
/// decisions: it renders geometry and events supplied by the Foundation-only engine.
@interface MDSDetectorSceneController : NSViewController

@property (nonatomic, assign, getter=areLabelsVisible) BOOL labelsVisible;

/// Hides or shows the transparent display case around the tubes. The plinth,
/// tube mounts, labels, and particle tracks remain visible.
@property (nonatomic, assign, getter=isShieldVisible) BOOL shieldVisible;

/// Selects which recent particle-track categories are drawn. Hit flashes,
/// statistics, the histogram, and the event log are unaffected.
@property (nonatomic, assign) MDSTrackDisplayFilter trackDisplayFilter;

/// Fades all recent particle tracks after a viewing delay. Single candidate
/// tracks use a short hold; shower trajectories are held longer so the full
/// fan can be inspected. Accepted tracks keep their green accepted styling
/// during the hold. Defaults to YES.
/// This is presentation-only and never changes acceptance.
@property (nonatomic, assign) BOOL fadesTracks;

/// Applies geometry and camera framing. Clears transient tracks because their
/// coordinates refer to the previous detector geometry.
- (void)applyConfiguration:(MDSDetectorConfiguration *)configuration;

/// Adds tracks for newly generated particle events. Background events are ignored.
- (void)presentEvents:(NSArray<MDSSimulationEvent *> *)events
    acceptedEventIDs:(NSSet<NSNumber *> *)acceptedEventIDs;

/// Updates an existing track bundle if a coincidence is discovered by a later pulse.
- (void)markEventIDsAccepted:(NSSet<NSNumber *> *)eventIDs;

- (void)flashHits:(NSArray<MDSHit *> *)hits;
- (void)clearTracks;
- (void)resetCamera;

#if DEBUG
/// Renders the current SceneKit frame for the local layout-verification harness.
- (nullable NSImage *)debugSnapshotImage;
#endif

@end

NS_ASSUME_NONNULL_END








