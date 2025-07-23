#import "MDSDetectorSceneController.h"

#import <SceneKit/SceneKit.h>
#import <simd/simd.h>

#import "MDSDetectorConfiguration.h"
#import "MDSGeometry.h"
#import "MDSHit.h"
#import "MDSSimulationEvent.h"
#import "MDSTrack.h"
#import "MDSTube.h"

static const CGFloat MDSCaseDepth = 6.4;
static const CGFloat MDSCaseWidthPadding = 4.4;
static const CGFloat MDSCaseBottomGap = 0.62;
static const CGFloat MDSCaseTopPadding = 2.6;
static const NSTimeInterval MDSTrackFadeHoldDuration = 0.80;
static const NSTimeInterval MDSTrackFadeDuration = 0.90;
// A shower is a group of particles and is much rarer per event than a single
// candidate track. Keep its trajectories on screen long enough to inspect the
// fan and the individual tube crossings instead of letting them vanish before
// the next shower arrives.
static const NSTimeInterval MDSShowerTrackFadeHoldDuration = 6.00;
static const NSTimeInterval MDSShowerTrackFadeDuration = 2.00;
static NSString *const MDSTrackAppearanceActionKey = @"trackAppearance";

static uint64_t MDSSparkMix64(uint64_t value) {
    value += 0x9E3779B97F4A7C15ULL;
    value = (value ^ (value >> 30)) * 0xBF58476D1CE4E5B9ULL;
    value = (value ^ (value >> 27)) * 0x94D049BB133111EBULL;
    return value ^ (value >> 31);
}

static double MDSSparkUnit(uint64_t *state) {
    *state = MDSSparkMix64(*state);
    return (double)(*state >> 11) / 9007199254740992.0;
}

static double MDSSparkSigned(uint64_t *state) {
    return MDSSparkUnit(state) * 2.0 - 1.0;
}

#pragma mark - Presentation helpers

@interface MDSTubeVisual : NSObject
@property (nonatomic, strong) MDSTube *tube;
@property (nonatomic, strong) SCNNode *node;
@end

@implementation MDSTubeVisual
@end

@interface MDSTrackGroup : NSObject
@property (nonatomic, assign) uint64_t eventID;
@property (nonatomic, assign, getter=isShower) BOOL shower;
@property (nonatomic, assign, getter=isAccepted) BOOL accepted;
@property (nonatomic, strong) SCNNode *container;
@property (nonatomic, strong) SCNMaterial *coreMaterial;
@property (nonatomic, strong) SCNMaterial *haloMaterial;
@property (nonatomic, assign) NSTimeInterval fadeStartTime;
@end

@implementation MDSTrackGroup
@end

#pragma mark - Orbit camera view

@interface MDSOrbitSCNView : SCNView
@property (nonatomic, strong) SCNNode *orbitCameraNode;
- (void)setHomeTarget:(SCNVector3)target eye:(SCNVector3)eye;
- (void)resetCameraAnimated:(BOOL)animated;
@end

@implementation MDSOrbitSCNView {
    SCNVector3 _target;
    SCNVector3 _homeTarget;
    SCNVector3 _homeEye;
    double _yaw;
    double _pitch;
    double _distance;
    double _homeYaw;
    double _homePitch;
    double _homeDistance;
    double _minimumDistance;
    double _maximumDistance;
    BOOL _hasHome;
    NSPoint _lastDragPoint;
}

- (instancetype)initWithFrame:(NSRect)frameRect options:(NSDictionary<NSString *,id> *)options {
    self = [super initWithFrame:frameRect options:options];
    if (self) {
        self.allowsCameraControl = NO;
        // Sparks, track fades, and hit glows are short-lived animations, so the
        // view must advance scene time and redraw between explicit scene-graph changes.
        self.playing = YES;
        self.rendersContinuously = YES;
        self.preferredFramesPerSecond = 60;
        self.antialiasingMode = SCNAntialiasingModeMultisampling4X;
        self.backgroundColor = [NSColor colorWithSRGBRed:0.965 green:0.975 blue:0.985 alpha:1.0];
        [self setAccessibilityElement:YES];
        [self setAccessibilityRole:NSAccessibilityGroupRole];
        [self setAccessibilityLabel:
            @"Three crystal Geiger tubes in a transparent display case"];
        [self setAccessibilityHelp:
            @"Drag to rotate the detector. Scroll or pinch to zoom. A spark appears inside a tube when it records a simulated pulse. Use the shield button in the 3D view to remove or replace the clear display cover, and Reset View to restore the camera."];
        self.toolTip = @"Drag to rotate · Scroll or pinch to zoom";
    }
    return self;
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)resetCursorRects {
    [super resetCursorRects];
    [self addCursorRect:self.bounds cursor:NSCursor.openHandCursor];
}

- (void)setHomeTarget:(SCNVector3)target eye:(SCNVector3)eye {
    _homeTarget = target;
    _homeEye = eye;
    _target = target;
    const double dx = eye.x - target.x;
    const double dy = eye.y - target.y;
    const double dz = eye.z - target.z;
    _distance = sqrt(dx * dx + dy * dy + dz * dz);
    _homeDistance = MAX(1.0, _distance);
    _yaw = atan2(dx, dz);
    _pitch = asin(MAX(-1.0, MIN(1.0, dy / _homeDistance)));
    _homeYaw = _yaw;
    _homePitch = _pitch;
    _minimumDistance = _homeDistance * 0.35;
    _maximumDistance = _homeDistance * 2.8;
    _hasHome = YES;
    [self applyCameraAnimated:NO];
}

- (void)resetCameraAnimated:(BOOL)animated {
    if (!_hasHome) {
        return;
    }
    _target = _homeTarget;
    _yaw = _homeYaw;
    _pitch = _homePitch;
    _distance = _homeDistance;
    [self applyCameraAnimated:animated];
}

- (void)applyCameraAnimated:(BOOL)animated {
    if (self.orbitCameraNode == nil || !_hasHome) {
        return;
    }
    const double horizontalDistance = cos(_pitch) * _distance;
    const SCNVector3 eye = SCNVector3Make(
        _target.x + sin(_yaw) * horizontalDistance,
        _target.y + sin(_pitch) * _distance,
        _target.z + cos(_yaw) * horizontalDistance);
    [SCNTransaction begin];
    [SCNTransaction setAnimationDuration:animated ? 0.30 : 0.0];
    self.orbitCameraNode.position = eye;
    [SCNTransaction commit];
    self.needsDisplay = YES;
}

- (void)mouseDown:(NSEvent *)event {
    _lastDragPoint = [self convertPoint:event.locationInWindow fromView:nil];
    [[self window] makeFirstResponder:self];
}

- (void)mouseDragged:(NSEvent *)event {
    if (!_hasHome) {
        return;
    }
    const NSPoint current = [self convertPoint:event.locationInWindow fromView:nil];
    const CGFloat deltaX = current.x - _lastDragPoint.x;
    const CGFloat deltaY = current.y - _lastDragPoint.y;
    _lastDragPoint = current;
    _yaw -= deltaX * 0.008;
    _pitch += deltaY * 0.008;
    _pitch = MAX(-0.06, MIN(1.38, _pitch));
    [self applyCameraAnimated:NO];
}

- (void)scrollWheel:(NSEvent *)event {
    if (!_hasHome) {
        [super scrollWheel:event];
        return;
    }
    const double sensitivity = event.hasPreciseScrollingDeltas ? 0.011 : 0.10;
    _distance *= exp(-event.scrollingDeltaY * sensitivity);
    _distance = MAX(_minimumDistance, MIN(_maximumDistance, _distance));
    [self applyCameraAnimated:NO];
}

- (void)magnifyWithEvent:(NSEvent *)event {
    if (!_hasHome) {
        [super magnifyWithEvent:event];
        return;
    }
    const double magnification = MAX(-0.9, event.magnification);
    _distance /= 1.0 + magnification;
    _distance = MAX(_minimumDistance, MIN(_maximumDistance, _distance));
    [self applyCameraAnimated:NO];
}

- (void)smartMagnifyWithEvent:(NSEvent *)event {
    [self resetCameraAnimated:YES];
}

@end

#pragma mark - Detector scene controller

/// Timer-driven presentation effect. SceneKit actions are not used for the
/// discharge lifetime because scene time can pause while the app is inactive;
/// timer ownership keeps the number of transient nodes bounded.
@interface MDSSparkEffect : NSObject
@property (nonatomic, strong) SCNNode *node;
@property (nonatomic, strong, nullable) SCNLight *light;
@property (nonatomic, assign) NSTimeInterval startTime;
@property (nonatomic, assign) NSTimeInterval holdDuration;
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, assign) CGFloat baseLightIntensity;
@property (nonatomic, assign) BOOL flickers;
@end

@implementation MDSSparkEffect
@end

@interface MDSDetectorSceneController ()
@property (nonatomic, strong) MDSOrbitSCNView *sceneView;
@property (nonatomic, strong) SCNScene *scene;
@property (nonatomic, strong) SCNNode *cameraNode;
@property (nonatomic, strong) SCNNode *cameraTargetNode;
@property (nonatomic, strong) SCNNode *equipmentRoot;
@property (nonatomic, strong, nullable) SCNNode *shieldRoot;
@property (nonatomic, strong) SCNNode *labelRoot;
@property (nonatomic, strong) SCNNode *trackRoot;
@property (nonatomic, strong) NSMutableArray<MDSTubeVisual *> *tubeVisuals;
@property (nonatomic, strong) NSMutableArray<MDSTrackGroup *> *trackGroups;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, MDSTrackGroup *> *trackGroupsByEventID;

- (void)buildScene;
- (void)addLights;
- (void)addSceneEnvironmentRoots;
- (void)applyShieldVisibility;
- (void)updateTrackVisibility;
- (BOOL)trackGroupMatchesDisplayFilter:(MDSTrackGroup *)group;
- (void)rebuildDetectorForConfiguration:(MDSDetectorConfiguration *)configuration
                           updateCamera:(BOOL)updateCamera;
- (void)buildFloorAtY:(double)y;
- (void)buildDisplayCaseAtBaseY:(double)baseY
                       highestY:(double)highestY
                         length:(double)length
                         radius:(double)radius;
- (void)buildTubeMountsForTubes:(NSArray<MDSTube *> *)tubes
                          baseY:(double)baseY
                         length:(double)length;
- (void)addTube:(MDSTube *)tube
  configuration:(MDSDetectorConfiguration *)configuration
     isRequired:(BOOL)isRequired;
- (void)buildDirectionLabelForConfiguration:(MDSDetectorConfiguration *)configuration
                                   highestY:(double)highestY;
- (SCNNode *)makeLabelWithTitle:(NSString *)title
                         detail:(NSString *)detail
                       position:(SCNVector3)position;
- (SCNNode *)textNodeWithString:(NSString *)string
                           font:(NSFont *)font
                          color:(NSColor *)color;
- (void)frameCameraForConfiguration:(MDSDetectorConfiguration *)configuration;
- (void)addTrackGroupForEvent:(MDSSimulationEvent *)event accepted:(BOOL)accepted;
- (void)applyStyleToGroup:(MDSTrackGroup *)group;
- (void)addSparkForHit:(MDSHit *)hit toTubeVisual:(MDSTubeVisual *)visual;
- (void)beginSparkEffectForNode:(SCNNode *)node
                          light:(nullable SCNLight *)light
                   holdDuration:(NSTimeInterval)holdDuration
                       duration:(NSTimeInterval)duration
                       flickers:(BOOL)flickers;
- (void)updateSparkEffects:(NSTimer *)timer;
- (void)clearSparkEffects;
- (SCNNode *)lineNodeFromPoint:(MDSVector3)start
                       toPoint:(MDSVector3)end
                        radius:(double)radius
                      material:(SCNMaterial *)material;
- (void)trimOldTrackGroupsIfNeeded;
@end

@implementation MDSDetectorSceneController {
    MDSDetectorConfiguration *_configuration;
    NSUInteger _trackSequence;
    NSMutableArray<MDSSparkEffect *> *_sparkEffects;
    NSTimer *_sparkTimer;
    NSTimer *_trackFadeTimer;
}

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _labelsVisible = YES;
        _shieldVisible = YES;
        _trackDisplayFilter = MDSTrackDisplayFilterAll;
        _fadesTracks = YES;
        _tubeVisuals = [NSMutableArray array];
        _trackGroups = [NSMutableArray array];
        _trackGroupsByEventID = [NSMutableDictionary dictionary];
        _sparkEffects = [NSMutableArray array];
    }
    return self;
}

- (void)loadView {
    MDSOrbitSCNView *sceneView =
        [[MDSOrbitSCNView alloc] initWithFrame:NSMakeRect(0, 0, 800, 500)
                                       options:nil];
    self.sceneView = sceneView;
    self.view = sceneView;
    [self buildScene];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.labelRoot.hidden = !self.labelsVisible;
    [self applyShieldVisibility];
}

- (void)buildScene {
    self.scene = [SCNScene scene];
    self.scene.background.contents =
        [NSColor colorWithSRGBRed:0.965 green:0.975 blue:0.985 alpha:1.0];
    self.sceneView.scene = self.scene;
    self.sceneView.playing = YES;
    [self.sceneView play:nil];

    SCNCamera *camera = [SCNCamera camera];
    camera.fieldOfView = 38.0;
    camera.zNear = 0.1;
    camera.zFar = 1000.0;
    self.cameraNode = [SCNNode node];
    self.cameraNode.camera = camera;
    self.cameraNode.name = @"Camera";
    [self.scene.rootNode addChildNode:self.cameraNode];

    self.cameraTargetNode = [SCNNode node];
    self.cameraTargetNode.name = @"Camera target";
    self.cameraTargetNode.position = SCNVector3Make(0.0, 0.0, 0.0);
    [self.scene.rootNode addChildNode:self.cameraTargetNode];

    SCNLookAtConstraint *lookAt =
        [SCNLookAtConstraint lookAtConstraintWithTarget:self.cameraTargetNode];
    lookAt.gimbalLockEnabled = YES;
    self.cameraNode.constraints = @[ lookAt ];
    self.sceneView.pointOfView = self.cameraNode;
    self.sceneView.orbitCameraNode = self.cameraNode;

    [self addLights];
    [self addSceneEnvironmentRoots];
    [self.sceneView setHomeTarget:SCNVector3Make(0.0, 0.0, 0.0)
                              eye:SCNVector3Make(24.0, 16.0, 32.0)];
    if (_configuration != nil) {
        [self rebuildDetectorForConfiguration:_configuration updateCamera:YES];
    }
}

- (void)addLights {
    SCNNode *ambientNode = [SCNNode node];
    SCNLight *ambient = [SCNLight light];
    ambient.type = SCNLightTypeAmbient;
    ambient.color = [NSColor colorWithSRGBRed:0.80 green:0.84 blue:0.90 alpha:1.0];
    ambient.intensity = 430.0;
    ambientNode.light = ambient;
    [self.scene.rootNode addChildNode:ambientNode];

    SCNNode *keyNode = [SCNNode node];
    keyNode.position = SCNVector3Make(14.0, 26.0, 18.0);
    SCNLight *key = [SCNLight light];
    key.type = SCNLightTypeDirectional;
    key.color = [NSColor colorWithSRGBRed:1.0 green:0.97 blue:0.92 alpha:1.0];
    key.intensity = 1050.0;
    key.castsShadow = YES;
    key.shadowRadius = 5.0;
    key.shadowSampleCount = 16;
    key.shadowColor = [NSColor colorWithWhite:0.0 alpha:0.16];
    keyNode.light = key;
    SCNLookAtConstraint *keyLookAt =
        [SCNLookAtConstraint lookAtConstraintWithTarget:self.cameraTargetNode];
    keyLookAt.gimbalLockEnabled = YES;
    keyNode.constraints = @[ keyLookAt ];
    [self.scene.rootNode addChildNode:keyNode];

    SCNNode *fillNode = [SCNNode node];
    fillNode.position = SCNVector3Make(-18.0, 8.0, 16.0);
    SCNLight *fill = [SCNLight light];
    fill.type = SCNLightTypeDirectional;
    fill.color = [NSColor colorWithSRGBRed:0.75 green:0.86 blue:1.0 alpha:1.0];
    fill.intensity = 420.0;
    fill.castsShadow = NO;
    fillNode.light = fill;
    SCNLookAtConstraint *fillLookAt =
        [SCNLookAtConstraint lookAtConstraintWithTarget:self.cameraTargetNode];
    fillLookAt.gimbalLockEnabled = YES;
    fillNode.constraints = @[ fillLookAt ];
    [self.scene.rootNode addChildNode:fillNode];
}

- (void)addSceneEnvironmentRoots {
    self.equipmentRoot = [SCNNode node];
    self.equipmentRoot.name = @"Detector";
    [self.scene.rootNode addChildNode:self.equipmentRoot];

    self.labelRoot = [SCNNode node];
    self.labelRoot.name = @"Labels";
    self.labelRoot.hidden = !self.labelsVisible;
    [self.scene.rootNode addChildNode:self.labelRoot];

    self.trackRoot = [SCNNode node];
    self.trackRoot.name = @"Tracks";
    [self.scene.rootNode addChildNode:self.trackRoot];
}

- (void)applyConfiguration:(MDSDetectorConfiguration *)configuration {
    (void)self.view;
    _configuration = [configuration copy];
    [self clearTracks];
    [self rebuildDetectorForConfiguration:_configuration updateCamera:YES];
}

- (void)setLabelsVisible:(BOOL)labelsVisible {
    _labelsVisible = labelsVisible;
    if (self.isViewLoaded) {
        self.labelRoot.hidden = !labelsVisible;
    }
}

- (void)setShieldVisible:(BOOL)shieldVisible {
    _shieldVisible = shieldVisible;
    if (self.isViewLoaded) {
        [self applyShieldVisibility];
    }
}

- (void)setTrackDisplayFilter:(MDSTrackDisplayFilter)trackDisplayFilter {
    if (_trackDisplayFilter == trackDisplayFilter) {
        return;
    }
    _trackDisplayFilter = trackDisplayFilter;
    if (self.isViewLoaded) {
        [self updateTrackVisibility];
    }
}

- (BOOL)trackGroupMatchesDisplayFilter:(MDSTrackGroup *)group {
    switch (self.trackDisplayFilter) {
        case MDSTrackDisplayFilterAll:
            return YES;
        case MDSTrackDisplayFilterMuons:
            return !group.isShower;
        case MDSTrackDisplayFilterShowers:
            return group.isShower;
    }
    return YES;
}

- (void)updateTrackVisibility {
    for (MDSTrackGroup *group in self.trackGroups) {
        group.container.hidden = ![self trackGroupMatchesDisplayFilter:group];
    }
}

- (void)setFadesTracks:(BOOL)fadesTracks {
    if (_fadesTracks == fadesTracks) {
        return;
    }
    _fadesTracks = fadesTracks;
    if (!self.isViewLoaded) {
        return;
    }
    if (fadesTracks) {
        for (MDSTrackGroup *group in self.trackGroups) {
            [self scheduleTrackFadeForGroup:group
                                     delay:[self holdDurationForTrackGroup:group]];
        }
    } else {
        [self stopTrackFadeTimer];
        for (MDSTrackGroup *group in self.trackGroups) {
            [group.container removeActionForKey:MDSTrackAppearanceActionKey];
            group.fadeStartTime = 0.0;
            group.container.opacity = 1.0;
        }
        [self updateTrackVisibility];
    }
}

- (void)applyShieldVisibility {
    SCNNode *shield = self.shieldRoot;
    if (shield == nil) {
        return;
    }
    // Keep the scene-graph edit atomic. The shield light lives outside this
    // subtree so hiding the cover never removes an active light from rendering.
    // Use opacity rather than SCNNode.hidden: toggling isHidden on a live,
    // transparent SceneKit subtree can crash the renderer on macOS. Keeping the
    // cover in the graph and making it fully transparent avoids that path.
    [SCNTransaction begin];
    [SCNTransaction setAnimationDuration:0.0];
    shield.hidden = NO;
    shield.opacity = self.shieldVisible ? 1.0 : 0.0;
    [SCNTransaction commit];
}

- (void)rebuildDetectorForConfiguration:(MDSDetectorConfiguration *)configuration
                          updateCamera:(BOOL)updateCamera {
    [self clearSparkEffects];
    for (SCNNode *child in [self.equipmentRoot childNodes]) {
        [child removeFromParentNode];
    }
    for (SCNNode *child in [self.labelRoot childNodes]) {
        [child removeFromParentNode];
    }
    [self.tubeVisuals removeAllObjects];

    NSArray<MDSTube *> *tubes = [configuration detectorTubes];
    const double lowestY = tubes.lastObject.center.y;
    const double highestY = tubes.firstObject.center.y;
    const double radius = configuration.tubeRadius;
    const double baseY = lowestY - radius - 2.15;

    [self buildFloorAtY:baseY - 0.04];
    [self buildDisplayCaseAtBaseY:baseY
                        highestY:highestY
                          length:configuration.activeLength
                          radius:radius];

    NSSet<NSNumber *> *requiredTubes =
        [NSSet setWithArray:[configuration requiredTubeIndices]];

    for (MDSTube *tube in tubes) {
        [self addTube:tube
          configuration:configuration
            isRequired:[requiredTubes containsObject:@(tube.tubeIndex)]];
    }

    [self buildTubeMountsForTubes:tubes baseY:baseY
                          length:configuration.activeLength];

    [self buildDirectionLabelForConfiguration:configuration
                                      highestY:highestY];

    if (updateCamera) {
        [self frameCameraForConfiguration:configuration];
    }
}

- (void)buildFloorAtY:(double)y {
    SCNFloor *floor = [SCNFloor floor];
    floor.reflectivity = 0.0;
    SCNMaterial *material = [SCNMaterial material];
    material.lightingModelName = SCNLightingModelPhysicallyBased;
    material.diffuse.contents = [NSColor colorWithSRGBRed:0.925 green:0.935 blue:0.945 alpha:1.0];
    material.roughness.contents = @0.95;
    material.metalness.contents = @0.0;
    floor.materials = @[ material ];
    SCNNode *floorNode = [SCNNode nodeWithGeometry:floor];
    floorNode.position = SCNVector3Make(0.0, y, 0.0);
    floorNode.name = @"Floor";
    [self.equipmentRoot addChildNode:floorNode];
}

- (void)buildDisplayCaseAtBaseY:(double)baseY
                       highestY:(double)highestY
                         length:(double)length
                         radius:(double)radius {
    const double caseWidth = length + MDSCaseWidthPadding;
    const double caseDepth = MDSCaseDepth;
    const double caseBottom = baseY + MDSCaseBottomGap;
    const double caseTop = highestY + radius + MDSCaseTopPadding;
    const double caseHeight = caseTop - caseBottom;

    SCNMaterial *darkMetal = [SCNMaterial material];
    darkMetal.lightingModelName = SCNLightingModelPhysicallyBased;
    darkMetal.diffuse.contents =
        [NSColor colorWithSRGBRed:0.16 green:0.18 blue:0.21 alpha:1.0];
    darkMetal.metalness.contents = @0.82;
    darkMetal.roughness.contents = @0.30;

    SCNMaterial *trimMetal = [SCNMaterial material];
    trimMetal.lightingModelName = SCNLightingModelPhysicallyBased;
    trimMetal.diffuse.contents =
        [NSColor colorWithSRGBRed:0.49 green:0.53 blue:0.57 alpha:1.0];
    trimMetal.metalness.contents = @0.90;
    trimMetal.roughness.contents = @0.24;

    SCNMaterial *caseGlass = [SCNMaterial material];
    caseGlass.lightingModelName = SCNLightingModelPhysicallyBased;
    caseGlass.diffuse.contents =
        [NSColor colorWithSRGBRed:0.76 green:0.90 blue:1.0 alpha:0.115];
    caseGlass.metalness.contents = @0.0;
    caseGlass.roughness.contents = @0.025;
    caseGlass.transparency = 0.16;
    caseGlass.transparencyMode = SCNTransparencyModeDualLayer;
    caseGlass.blendMode = SCNBlendModeAlpha;
    caseGlass.doubleSided = YES;
    caseGlass.writesToDepthBuffer = NO;
    caseGlass.fresnelExponent = 3.6;
    caseGlass.clearCoat.contents = @1.0;
    caseGlass.clearCoatRoughness.contents = @0.018;

    SCNBox *plinth =
        [SCNBox boxWithWidth:caseWidth + 0.9
                      height:0.54
                      length:caseDepth + 0.9
               chamferRadius:0.12];
    plinth.firstMaterial = darkMetal;
    SCNNode *plinthNode = [SCNNode nodeWithGeometry:plinth];
    plinthNode.position = SCNVector3Make(0.0, baseY + 0.27, 0.0);
    plinthNode.name = @"Display case plinth";
    [self.equipmentRoot addChildNode:plinthNode];

    SCNBox *plinthTrim =
        [SCNBox boxWithWidth:caseWidth + 0.94
                      height:0.035
                      length:caseDepth + 0.94
               chamferRadius:0.015];
    plinthTrim.firstMaterial = trimMetal;
    SCNNode *plinthTrimNode = [SCNNode nodeWithGeometry:plinthTrim];
    plinthTrimNode.position = SCNVector3Make(0.0, baseY + 0.075, 0.0);
    [self.equipmentRoot addChildNode:plinthTrimNode];

    SCNNode *shieldRoot = [SCNNode node];
    shieldRoot.name = @"Crystal shield";
    [self.equipmentRoot addChildNode:shieldRoot];
    self.shieldRoot = shieldRoot;

    // The clear acrylic enclosure is assembled from thin panels so the tubes
    // remain visible from every camera angle while still reading as a case.
    void (^addPanel)(double, double, double, SCNVector3) =
        ^(double width, double height, double depth, SCNVector3 position) {
            SCNBox *panel = [SCNBox boxWithWidth:width
                                           height:height
                                           length:depth
                                    chamferRadius:0.015];
            panel.firstMaterial = caseGlass;
            SCNNode *panelNode = [SCNNode nodeWithGeometry:panel];
            panelNode.position = position;
            panelNode.name = @"Transparent enclosure";
            panelNode.castsShadow = NO;
            panelNode.renderingOrder = 5;
            [shieldRoot addChildNode:panelNode];
        };

    addPanel(0.045, caseHeight, caseDepth - 0.08,
             SCNVector3Make(-caseWidth * 0.5, (caseBottom + caseTop) * 0.5, 0.0));
    addPanel(0.045, caseHeight, caseDepth - 0.08,
             SCNVector3Make(caseWidth * 0.5, (caseBottom + caseTop) * 0.5, 0.0));
    addPanel(caseWidth - 0.08, caseHeight, 0.045,
             SCNVector3Make(0.0, (caseBottom + caseTop) * 0.5, -caseDepth * 0.5));
    addPanel(caseWidth - 0.08, caseHeight, 0.045,
             SCNVector3Make(0.0, (caseBottom + caseTop) * 0.5, caseDepth * 0.5));
    addPanel(caseWidth - 0.08, 0.045, caseDepth - 0.08,
             SCNVector3Make(0.0, caseTop, 0.0));
    addPanel(caseWidth - 0.08, 0.045, caseDepth - 0.08,
             SCNVector3Make(0.0, caseBottom, 0.0));

    for (NSInteger xSide = -1; xSide <= 1; xSide += 2) {
        for (NSInteger zSide = -1; zSide <= 1; zSide += 2) {
            SCNBox *post =
                [SCNBox boxWithWidth:0.12
                              height:caseHeight + 0.06
                              length:0.12
                       chamferRadius:0.022];
            post.firstMaterial = trimMetal;
            SCNNode *postNode = [SCNNode nodeWithGeometry:post];
            postNode.position = SCNVector3Make(xSide * caseWidth * 0.5,
                                               (caseBottom + caseTop) * 0.5,
                                               zSide * caseDepth * 0.5);
            postNode.name = @"Enclosure frame";
            [shieldRoot addChildNode:postNode];
        }
    }

    for (NSInteger xSide = -1; xSide <= 1; xSide += 2) {
        SCNBox *sideRail = [SCNBox boxWithWidth:0.10
                                         height:0.10
                                         length:caseDepth
                                  chamferRadius:0.02];
        sideRail.firstMaterial = trimMetal;
        for (NSInteger end = -1; end <= 1; end += 2) {
            SCNNode *railNode = [SCNNode nodeWithGeometry:sideRail];
            railNode.position = SCNVector3Make(
                xSide * caseWidth * 0.5,
                end < 0 ? caseTop : caseBottom,
                0.0);
            [shieldRoot addChildNode:railNode];
        }
    }

    for (NSInteger zSide = -1; zSide <= 1; zSide += 2) {
        SCNBox *frontRail = [SCNBox boxWithWidth:caseWidth
                                          height:0.10
                                          length:0.10
                                   chamferRadius:0.02];
        frontRail.firstMaterial = trimMetal;
        for (NSInteger end = -1; end <= 1; end += 2) {
            SCNNode *railNode = [SCNNode nodeWithGeometry:frontRail];
            railNode.position = SCNVector3Make(
                0.0,
                end < 0 ? caseTop : caseBottom,
                zSide * caseDepth * 0.5);
            [shieldRoot addChildNode:railNode];
        }
    }

    SCNBox *gasket =
        [SCNBox boxWithWidth:caseWidth - 0.18
                      height:0.12
                      length:caseDepth - 0.18
               chamferRadius:0.02];
    gasket.firstMaterial = darkMetal;
    SCNNode *gasketNode = [SCNNode nodeWithGeometry:gasket];
    gasketNode.position = SCNVector3Make(0.0, caseBottom + 0.04, 0.0);
    [shieldRoot addChildNode:gasketNode];

    SCNBox *drawerPull =
        [SCNBox boxWithWidth:1.55
                      height:0.085
                      length:0.085
               chamferRadius:0.04];
    SCNMaterial *pullMaterial = [trimMetal copy];
    pullMaterial.emission.contents =
        [NSColor colorWithSRGBRed:0.25 green:0.28 blue:0.30 alpha:1.0];
    drawerPull.firstMaterial = pullMaterial;
    SCNNode *pullNode = [SCNNode nodeWithGeometry:drawerPull];
    pullNode.position = SCNVector3Make(0.0, caseBottom + 0.72,
                                       caseDepth * 0.5 + 0.08);
    [shieldRoot addChildNode:pullNode];

    // A discreet cool-white strip along the top makes the crystal envelopes and
    // acrylic edges read clearly without brightening the whole scene.
    SCNBox *lightBar =
        [SCNBox boxWithWidth:MIN(7.0, caseWidth * 0.55)
                      height:0.055
                      length:0.055
               chamferRadius:0.02];
    SCNMaterial *barMaterial = [SCNMaterial material];
    barMaterial.lightingModelName = SCNLightingModelConstant;
    barMaterial.diffuse.contents =
        [NSColor colorWithSRGBRed:0.80 green:0.91 blue:1.0 alpha:1.0];
    barMaterial.emission.contents =
        [NSColor colorWithSRGBRed:0.72 green:0.88 blue:1.0 alpha:1.0];
    lightBar.firstMaterial = barMaterial;
    SCNNode *lightBarNode = [SCNNode nodeWithGeometry:lightBar];
    lightBarNode.position = SCNVector3Make(0.0, caseTop - 0.32, -caseDepth * 0.24);
    lightBarNode.name = @"Enclosure light";
    [shieldRoot addChildNode:lightBarNode];

    SCNLight *caseLight = [SCNLight light];
    caseLight.type = SCNLightTypeOmni;
    caseLight.color = [NSColor colorWithSRGBRed:0.76 green:0.89 blue:1.0 alpha:1.0];
    caseLight.intensity = 240.0;
    caseLight.attenuationStartDistance = 1.0;
    caseLight.attenuationEndDistance = 22.0;
    caseLight.castsShadow = NO;
    SCNNode *caseLightNode = [SCNNode node];
    caseLightNode.light = caseLight;
    caseLightNode.position = SCNVector3Make(0.0, caseTop - 0.55, 0.0);
    caseLightNode.name = @"Display light";
    // The illumination is deliberately outside the removable cover so the tubes
    // stay evenly lit when the shield is hidden.
    [self.equipmentRoot addChildNode:caseLightNode];

    [self applyShieldVisibility];
}

- (void)buildTubeMountsForTubes:(NSArray<MDSTube *> *)tubes
                          baseY:(double)baseY
                         length:(double)length {
    if (tubes.count == 0) {
        return;
    }

    SCNMaterial *mountMetal = [SCNMaterial material];
    mountMetal.lightingModelName = SCNLightingModelPhysicallyBased;
    mountMetal.diffuse.contents =
        [NSColor colorWithSRGBRed:0.30 green:0.33 blue:0.37 alpha:1.0];
    mountMetal.metalness.contents = @0.86;
    mountMetal.roughness.contents = @0.28;

    SCNMaterial *insulatorMaterial = [SCNMaterial material];
    insulatorMaterial.lightingModelName = SCNLightingModelPhysicallyBased;
    insulatorMaterial.diffuse.contents =
        [NSColor colorWithSRGBRed:0.90 green:0.88 blue:0.81 alpha:1.0];
    insulatorMaterial.roughness.contents = @0.74;
    insulatorMaterial.metalness.contents = @0.0;

    const double railX = length * 0.5 + 1.22;
    const double caseBottom = baseY + MDSCaseBottomGap;
    const double railBottom = caseBottom + 0.10;
    const double railTop = tubes.firstObject.center.y + 1.28;

    for (NSInteger side = -1; side <= 1; side += 2) {
        SCNBox *rail = [SCNBox boxWithWidth:0.11
                                     height:MAX(0.5, railTop - railBottom)
                                     length:0.11
                              chamferRadius:0.025];
        rail.firstMaterial = mountMetal;
        SCNNode *railNode = [SCNNode nodeWithGeometry:rail];
        railNode.position = SCNVector3Make(
            side * railX,
            (railBottom + railTop) * 0.5,
            0.0);
        railNode.name = @"Tube mounting rail";
        [self.equipmentRoot addChildNode:railNode];

        SCNBox *foot = [SCNBox boxWithWidth:0.82
                                     height:0.10
                                     length:0.50
                              chamferRadius:0.04];
        foot.firstMaterial = mountMetal;
        SCNNode *footNode = [SCNNode nodeWithGeometry:foot];
        footNode.position = SCNVector3Make(side * railX, caseBottom + 0.11, -0.06);
        [self.equipmentRoot addChildNode:footNode];
    }

    for (MDSTube *tube in tubes) {
        for (NSInteger side = -1; side <= 1; side += 2) {
            const double connectorTip = length * 0.5 + 0.41;
            const double armLength = MAX(0.05, railX - connectorTip);
            SCNCylinder *arm =
                [SCNCylinder cylinderWithRadius:0.048 height:armLength];
            arm.radialSegmentCount = 16;
            arm.firstMaterial = mountMetal;
            SCNNode *armNode = [SCNNode nodeWithGeometry:arm];
            armNode.eulerAngles = SCNVector3Make(0.0, 0.0, M_PI_2);
            armNode.position = SCNVector3Make(
                side * (connectorTip + armLength * 0.5),
                tube.center.y,
                tube.center.z);
            armNode.name = @"Tube end mount";
            [self.equipmentRoot addChildNode:armNode];

            SCNCylinder *collar =
                [SCNCylinder cylinderWithRadius:0.105 height:0.075];
            collar.radialSegmentCount = 20;
            collar.firstMaterial = insulatorMaterial;
            SCNNode *collarNode = [SCNNode nodeWithGeometry:collar];
            collarNode.eulerAngles = SCNVector3Make(0.0, 0.0, M_PI_2);
            collarNode.position = SCNVector3Make(
                side * (connectorTip + 0.04),
                tube.center.y,
                tube.center.z);
            [self.equipmentRoot addChildNode:collarNode];
        }
    }
}

- (void)addTube:(MDSTube *)tube
  configuration:(MDSDetectorConfiguration *)configuration
     isRequired:(BOOL)isRequired {
    const double radius = tube.radius;
    const double length = tube.length;
    SCNNode *tubeNode = [SCNNode node];
    tubeNode.position = SCNVector3Make(tube.center.x, tube.center.y, tube.center.z);
    tubeNode.name = [NSString stringWithFormat:@"Crystal tube %ld",
                     (long)tube.displayNumber];

    SCNMaterial *shellMaterial = [SCNMaterial material];
    shellMaterial.lightingModelName = SCNLightingModelPhysicallyBased;
    shellMaterial.diffuse.contents =
        [NSColor colorWithSRGBRed:0.66 green:0.84 blue:0.98 alpha:0.22];
    shellMaterial.metalness.contents = @0.01;
    shellMaterial.roughness.contents = @0.025;
    shellMaterial.specular.contents = [NSColor colorWithWhite:1.0 alpha:0.95];
    shellMaterial.transparency = 0.12;
    shellMaterial.transparencyMode = SCNTransparencyModeDualLayer;
    shellMaterial.blendMode = SCNBlendModeAlpha;
    shellMaterial.doubleSided = YES;
    shellMaterial.writesToDepthBuffer = NO;
    shellMaterial.fresnelExponent = 3.4;
    shellMaterial.clearCoat.contents = @1.0;
    shellMaterial.clearCoatRoughness.contents = @0.02;

    SCNTube *shell = [SCNTube tubeWithInnerRadius:radius * 0.85
                                      outerRadius:radius
                                           height:length];
    shell.radialSegmentCount = 80;
    shell.firstMaterial = shellMaterial;
    SCNNode *shellNode = [SCNNode nodeWithGeometry:shell];
    shellNode.eulerAngles = SCNVector3Make(0.0, 0.0, M_PI_2);
    shellNode.renderingOrder = 22;
    shellNode.castsShadow = NO;
    [tubeNode addChildNode:shellNode];

    const NSColor *gasColor = isRequired
        ? [NSColor colorWithSRGBRed:0.22 green:0.72 blue:0.86 alpha:1.0]
        : [NSColor colorWithSRGBRed:0.42 green:0.58 blue:0.68 alpha:1.0];
    SCNMaterial *gasMaterial = [SCNMaterial material];
    gasMaterial.lightingModelName = SCNLightingModelConstant;
    gasMaterial.diffuse.contents = [gasColor colorWithAlphaComponent:0.30];
    gasMaterial.emission.contents = [gasColor colorWithAlphaComponent:0.050];
    gasMaterial.transparency = 0.040;
    gasMaterial.blendMode = SCNBlendModeAlpha;
    gasMaterial.doubleSided = YES;
    gasMaterial.writesToDepthBuffer = NO;

    SCNCylinder *activeVolume =
        [SCNCylinder cylinderWithRadius:radius * 0.79 height:length * 0.96];
    activeVolume.radialSegmentCount = 48;
    activeVolume.firstMaterial = gasMaterial;
    SCNNode *activeNode = [SCNNode nodeWithGeometry:activeVolume];
    activeNode.eulerAngles = SCNVector3Make(0.0, 0.0, M_PI_2);
    activeNode.renderingOrder = 20;
    activeNode.castsShadow = NO;
    activeNode.name = @"Active gas volume";
    [tubeNode addChildNode:activeNode];

    SCNMaterial *wireMaterial = [SCNMaterial material];
    wireMaterial.lightingModelName = SCNLightingModelPhysicallyBased;
    wireMaterial.diffuse.contents =
        [NSColor colorWithSRGBRed:0.20 green:0.23 blue:0.26 alpha:1.0];
    wireMaterial.metalness.contents = @0.78;
    wireMaterial.roughness.contents = @0.34;
    SCNCylinder *wire =
        [SCNCylinder cylinderWithRadius:MAX(0.018, radius * 0.036)
                                 height:length * 1.005];
    wire.radialSegmentCount = 16;
    wire.firstMaterial = wireMaterial;
    SCNNode *wireNode = [SCNNode nodeWithGeometry:wire];
    wireNode.eulerAngles = SCNVector3Make(0.0, 0.0, M_PI_2);
    wireNode.name = @"Anode wire";
    [tubeNode addChildNode:wireNode];

    // Two narrow, static highlights suggest reflections on a polished crystal
    // surface without obstructing the anode and discharge detail.
    for (NSInteger highlightIndex = 0; highlightIndex < 2; highlightIndex++) {
        SCNMaterial *highlightMaterial = [SCNMaterial material];
        highlightMaterial.lightingModelName = SCNLightingModelConstant;
        highlightMaterial.diffuse.contents =
            [NSColor colorWithSRGBRed:0.92 green:0.98 blue:1.0 alpha:1.0];
        highlightMaterial.emission.contents =
            [NSColor colorWithSRGBRed:0.86 green:0.96 blue:1.0 alpha:1.0];
        highlightMaterial.transparency = highlightIndex == 0 ? 0.25 : 0.10;
        highlightMaterial.blendMode = SCNBlendModeAdd;
        highlightMaterial.writesToDepthBuffer = NO;
        highlightMaterial.readsFromDepthBuffer = NO;
        SCNCylinder *highlight =
            [SCNCylinder cylinderWithRadius:0.0075 height:length * 0.78];
        highlight.radialSegmentCount = 8;
        highlight.firstMaterial = highlightMaterial;
        SCNNode *highlightNode = [SCNNode nodeWithGeometry:highlight];
        highlightNode.eulerAngles = SCNVector3Make(0.0, 0.0, M_PI_2);
        highlightNode.position = SCNVector3Make(
            highlightIndex == 0 ? -length * 0.03 : length * 0.02,
            radius * (highlightIndex == 0 ? 0.63 : -0.44),
            radius * (highlightIndex == 0 ? 0.48 : 0.50));
        highlightNode.renderingOrder = 24;
        highlightNode.castsShadow = NO;
        [tubeNode addChildNode:highlightNode];
    }

    SCNMaterial *capMaterial = [SCNMaterial material];
    capMaterial.lightingModelName = SCNLightingModelPhysicallyBased;
    capMaterial.diffuse.contents =
        [NSColor colorWithSRGBRed:0.58 green:0.61 blue:0.65 alpha:1.0];
    capMaterial.roughness.contents = @0.26;
    capMaterial.metalness.contents = @0.90;

    SCNMaterial *sealMaterial = [SCNMaterial material];
    sealMaterial.lightingModelName = SCNLightingModelPhysicallyBased;
    sealMaterial.diffuse.contents =
        [NSColor colorWithSRGBRed:0.72 green:0.63 blue:0.43 alpha:1.0];
    sealMaterial.roughness.contents = @0.25;
    sealMaterial.metalness.contents = @0.92;

    SCNMaterial *ceramicMaterial = [SCNMaterial material];
    ceramicMaterial.lightingModelName = SCNLightingModelPhysicallyBased;
    ceramicMaterial.diffuse.contents =
        [NSColor colorWithSRGBRed:0.93 green:0.91 blue:0.84 alpha:1.0];
    ceramicMaterial.roughness.contents = @0.68;
    ceramicMaterial.metalness.contents = @0.0;

    SCNMaterial *connectorMaterial = [SCNMaterial material];
    connectorMaterial.lightingModelName = SCNLightingModelPhysicallyBased;
    connectorMaterial.diffuse.contents =
        [NSColor colorWithSRGBRed:0.26 green:0.28 blue:0.31 alpha:1.0];
    connectorMaterial.metalness.contents = @0.86;
    connectorMaterial.roughness.contents = @0.32;

    const double capThickness = 0.26;
    const double capCenter = length * 0.5 + capThickness * 0.5;
    for (NSInteger side = -1; side <= 1; side += 2) {
        SCNCylinder *cap =
            [SCNCylinder cylinderWithRadius:radius * 1.12 height:capThickness];
        cap.radialSegmentCount = 56;
        cap.firstMaterial = capMaterial;
        SCNNode *capNode = [SCNNode nodeWithGeometry:cap];
        capNode.eulerAngles = SCNVector3Make(0.0, 0.0, M_PI_2);
        capNode.position = SCNVector3Make(side * capCenter, 0.0, 0.0);
        [tubeNode addChildNode:capNode];

        // Glass-to-metal seal
        SCNTorus *seal =
            [SCNTorus torusWithRingRadius:radius * 0.965 pipeRadius:0.026];
        seal.ringSegmentCount = 56;
        seal.pipeSegmentCount = 10;
        seal.firstMaterial = sealMaterial;
        SCNNode *sealNode = [SCNNode nodeWithGeometry:seal];
        sealNode.eulerAngles = SCNVector3Make(0.0, 0.0, M_PI_2);
        sealNode.position = SCNVector3Make(side * (length * 0.5 - 0.015), 0.0, 0.0);
        [tubeNode addChildNode:sealNode];

        // Ceramic insulator disc at the end of each cap
        SCNCylinder *insulator =
            [SCNCylinder cylinderWithRadius:radius * 0.83 height:0.055];
        insulator.radialSegmentCount = 48;
        insulator.firstMaterial = ceramicMaterial;
        SCNNode *insulatorNode = [SCNNode nodeWithGeometry:insulator];
        insulatorNode.eulerAngles = SCNVector3Make(0.0, 0.0, M_PI_2);
        insulatorNode.position = SCNVector3Make(
            side * (length * 0.5 + capThickness + 0.026), 0.0, 0.0);
        [tubeNode addChildNode:insulatorNode];

        SCNCylinder *connector =
            [SCNCylinder cylinderWithRadius:radius * 0.27 height:0.34];
        connector.radialSegmentCount = 24;
        connector.firstMaterial = connectorMaterial;
        SCNNode *connectorNode = [SCNNode nodeWithGeometry:connector];
        connectorNode.eulerAngles = SCNVector3Make(0.0, 0.0, M_PI_2);
        connectorNode.position = SCNVector3Make(
            side * (length * 0.5 + capThickness + 0.20), 0.0, 0.0);
        [tubeNode addChildNode:connectorNode];
    }

    [self.equipmentRoot addChildNode:tubeNode];

    MDSTubeVisual *visual = [[MDSTubeVisual alloc] init];
    visual.tube = tube;
    visual.node = tubeNode;
    [self.tubeVisuals addObject:visual];

    NSString *title = [NSString stringWithFormat:@"TUBE %ld · y %+.1f cm",
                       (long)tube.displayNumber, tube.center.y];
    NSString *detail = [NSString stringWithFormat:@"Ø%.1f × %.1f cm%@",
                        configuration.activeDiameter,
                        configuration.activeLength,
                        isRequired ? @"   • coincidence" : @""];
    const double labelZ = MDSCaseDepth * 0.5 + 0.46;
    SCNNode *label = [self makeLabelWithTitle:title
                                       detail:detail
                                     position:SCNVector3Make(
                                         length * 0.5 + 3.65,
                                         tube.center.y + 0.45,
                                         labelZ)];
    [self.labelRoot addChildNode:label];
}

- (void)buildDirectionLabelForConfiguration:(MDSDetectorConfiguration *)configuration
                                   highestY:(double)highestY {
    NSString *title = nil;
    NSString *detail = nil;
    if (configuration.arrivalDirectionMode ==
        MDSArrivalDirectionModeRandomRealistic) {
        title = configuration.isShowerModeEnabled
            ? @"SHOWER  random realistic axis"
            : @"PRIMARY  random realistic";
        detail = configuration.isShowerModeEnabled
            ? [NSString stringWithFormat:@"cos²θ axis · spread ±%.0f°",
               configuration.showerAngularSpread]
            : @"Downward cos²θ arrival · seeded";
    } else if (configuration.isShowerModeEnabled) {
        title = [NSString stringWithFormat:@"PRIMARY  %.0f° from vertical",
                 configuration.primaryAngleFromVertical];
        detail = [NSString stringWithFormat:@"Azimuth %.0f° · spread ±%.0f°",
                  configuration.primaryAzimuth,
                  configuration.showerAngularSpread];
    } else {
        title = @"PRIMARY  vertical";
        detail = @"Simplified cosmic-ray direction";
    }

    SCNNode *label = [self makeLabelWithTitle:title
                                       detail:detail
                                     position:SCNVector3Make(0.0,
                                                             highestY + 4.2,
                                                             0.0)];
    [self.labelRoot addChildNode:label];
}

- (SCNNode *)makeLabelWithTitle:(NSString *)title
                         detail:(NSString *)detail
                       position:(SCNVector3)position {
    SCNNode *container = [SCNNode node];
    container.position = position;
    SCNBillboardConstraint *billboard =
        [SCNBillboardConstraint billboardConstraint];
    billboard.freeAxes = SCNBillboardAxisAll;
    container.constraints = @[ billboard ];

    NSFont *titleFont = [NSFont monospacedDigitSystemFontOfSize:0.66
                                                        weight:NSFontWeightSemibold];
    NSFont *detailFont = [NSFont monospacedDigitSystemFontOfSize:0.56
                                                          weight:NSFontWeightRegular];
    SCNNode *titleNode = [self textNodeWithString:title
                                             font:titleFont
                                            color:[NSColor colorWithSRGBRed:0.16
                                                                     green:0.19
                                                                      blue:0.23
                                                                     alpha:1.0]];
    titleNode.position = SCNVector3Make(0.0, 0.0, 0.0);
    [container addChildNode:titleNode];

    SCNNode *detailNode = [self textNodeWithString:detail
                                              font:detailFont
                                             color:[NSColor colorWithSRGBRed:0.34
                                                                      green:0.38
                                                                       blue:0.43
                                                                      alpha:1.0]];
    detailNode.position = SCNVector3Make(0.0, -0.78, 0.0);
    [container addChildNode:detailNode];

    // A translucent caption card keeps labels legible when they cross the
    // display case or its dark plinth. SceneKit text nodes report their local
    // bounds once their geometry has been created, so the card follows the
    // actual title and detail widths.
    SCNVector3 titleMinimum = SCNVector3Zero;
    SCNVector3 titleMaximum = SCNVector3Zero;
    SCNVector3 detailMinimum = SCNVector3Zero;
    SCNVector3 detailMaximum = SCNVector3Zero;
    [titleNode getBoundingBoxMin:&titleMinimum max:&titleMaximum];
    [detailNode getBoundingBoxMin:&detailMinimum max:&detailMaximum];
    const CGFloat minimumX = MIN(titleMinimum.x, detailMinimum.x) - 0.18;
    const CGFloat maximumX = MAX(titleMaximum.x, detailMaximum.x) + 0.18;
    const CGFloat topY = titleMaximum.y + 0.15;
    const CGFloat bottomY = detailNode.position.y + detailMinimum.y - 0.14;
    const CGFloat cardWidth = MAX(0.8, maximumX - minimumX);
    const CGFloat cardHeight = MAX(0.6, topY - bottomY);

    SCNPlane *outline = [SCNPlane planeWithWidth:cardWidth + 0.035
                                         height:cardHeight + 0.035];
    outline.cornerRadius = 0.14;
    SCNMaterial *outlineMaterial = [SCNMaterial material];
    outlineMaterial.lightingModelName = SCNLightingModelConstant;
    outlineMaterial.diffuse.contents =
        [NSColor colorWithSRGBRed:0.58 green:0.65 blue:0.72 alpha:0.55];
    outlineMaterial.transparency = 0.85;
    outlineMaterial.blendMode = SCNBlendModeAlpha;
    outlineMaterial.doubleSided = YES;
    outlineMaterial.writesToDepthBuffer = NO;
    outlineMaterial.readsFromDepthBuffer = NO;
    outline.firstMaterial = outlineMaterial;
    SCNNode *outlineNode = [SCNNode nodeWithGeometry:outline];
    outlineNode.position = SCNVector3Make((minimumX + maximumX) * 0.5,
                                          (topY + bottomY) * 0.5,
                                          -0.032);
    outlineNode.renderingOrder = 98;
    outlineNode.castsShadow = NO;
    [container addChildNode:outlineNode];

    SCNPlane *card = [SCNPlane planeWithWidth:cardWidth height:cardHeight];
    card.cornerRadius = 0.12;
    SCNMaterial *cardMaterial = [SCNMaterial material];
    cardMaterial.lightingModelName = SCNLightingModelConstant;
    cardMaterial.diffuse.contents =
        [NSColor colorWithSRGBRed:0.985 green:0.992 blue:1.0 alpha:0.92];
    cardMaterial.transparency = 0.95;
    cardMaterial.blendMode = SCNBlendModeAlpha;
    cardMaterial.doubleSided = YES;
    cardMaterial.writesToDepthBuffer = NO;
    cardMaterial.readsFromDepthBuffer = NO;
    card.firstMaterial = cardMaterial;
    SCNNode *cardNode = [SCNNode nodeWithGeometry:card];
    cardNode.position = SCNVector3Make((minimumX + maximumX) * 0.5,
                                       (topY + bottomY) * 0.5,
                                       -0.025);
    cardNode.renderingOrder = 99;
    cardNode.castsShadow = NO;
    [container addChildNode:cardNode];
    return container;
}

- (SCNNode *)textNodeWithString:(NSString *)string
                           font:(NSFont *)font
                          color:(NSColor *)color {
    SCNText *text = [SCNText textWithString:string extrusionDepth:0.012];
    text.font = font;
    text.flatness = 0.28;
    text.chamferRadius = 0.0;
    SCNMaterial *material = [SCNMaterial material];
    material.lightingModelName = SCNLightingModelConstant;
    material.diffuse.contents = color;
    material.emission.contents = color;
    material.writesToDepthBuffer = NO;
    material.readsFromDepthBuffer = YES;
    text.materials = @[ material ];
    SCNNode *node = [SCNNode nodeWithGeometry:text];
    node.renderingOrder = 100;
    return node;
}

- (void)frameCameraForConfiguration:(MDSDetectorConfiguration *)configuration {
    const double lateralExtent = configuration.activeLength * 0.5 + 6.3;
    const double verticalExtent = configuration.tubeSpacing +
                                  configuration.tubeRadius + 5.8;
    const double depthExtent = configuration.alignmentOffset +
                               configuration.tubeRadius + MDSCaseDepth * 0.5 + 0.6;
    const double boundingRadius = sqrt(lateralExtent * lateralExtent +
                                       verticalExtent * verticalExtent +
                                       depthExtent * depthExtent);
    const double distance = MAX(16.0, boundingRadius / tan(19.0 * M_PI / 180.0) * 0.82);
    const SCNVector3 direction = SCNVector3Make(0.84, 0.50, 1.18);
    const double length = sqrt(direction.x * direction.x +
                               direction.y * direction.y +
                               direction.z * direction.z);
    const SCNVector3 eye = SCNVector3Make(direction.x / length * distance,
                                          direction.y / length * distance,
                                          direction.z / length * distance);
    [self.sceneView setHomeTarget:SCNVector3Make(0.0, 0.0, 0.0) eye:eye];
}

- (void)resetCamera {
    [self.sceneView resetCameraAnimated:YES];
}

#if DEBUG
- (NSImage *)debugSnapshotImage {
    [self.sceneView layoutSubtreeIfNeeded];
    [self.sceneView displayIfNeeded];
    return [self.sceneView snapshot];
}
#endif

#pragma mark - Tracks

- (void)presentEvents:(NSArray<MDSSimulationEvent *> *)events
    acceptedEventIDs:(NSSet<NSNumber *> *)acceptedEventIDs {
    for (MDSSimulationEvent *event in events) {
        if (event.tracks.count == 0) {
            continue;
        }
        if (self.trackGroupsByEventID[@(event.eventID)] != nil) {
            continue;
        }
        const BOOL accepted = [acceptedEventIDs containsObject:@(event.eventID)];
        [self addTrackGroupForEvent:event accepted:accepted];
    }

    [self markEventIDsAccepted:acceptedEventIDs];
}

- (void)addTrackGroupForEvent:(MDSSimulationEvent *)event accepted:(BOOL)accepted {
    MDSTrackGroup *group = [[MDSTrackGroup alloc] init];
    group.eventID = event.eventID;
    group.shower = (event.kind == MDSSimulationEventKindShower);
    group.accepted = accepted;
    group.container = [SCNNode node];
    group.container.name = [NSString stringWithFormat:@"Event %llu", event.eventID];

    SCNMaterial *coreMaterial = [SCNMaterial material];
    coreMaterial.lightingModelName = SCNLightingModelConstant;
    coreMaterial.blendMode = SCNBlendModeAlpha;
    coreMaterial.doubleSided = YES;
    coreMaterial.writesToDepthBuffer = NO;
    coreMaterial.readsFromDepthBuffer = YES;
    group.coreMaterial = coreMaterial;

    SCNMaterial *haloMaterial = [SCNMaterial material];
    haloMaterial.lightingModelName = SCNLightingModelConstant;
    haloMaterial.blendMode = SCNBlendModeAdd;
    haloMaterial.doubleSided = YES;
    haloMaterial.writesToDepthBuffer = NO;
    haloMaterial.readsFromDepthBuffer = YES;
    group.haloMaterial = haloMaterial;

    for (MDSTrack *track in event.tracks) {
        const double radius = event.kind == MDSSimulationEventKindShower
            ? 0.045 : (accepted ? 0.075 : 0.055);
        SCNNode *line = [self lineNodeFromPoint:track.startPoint
                                        toPoint:track.endPoint
                                         radius:radius
                                       material:coreMaterial];
        if (line != nil) {
            [group.container addChildNode:line];
        }

        SCNNode *halo = [self lineNodeFromPoint:track.startPoint
                                        toPoint:track.endPoint
                                         radius:radius * 2.6
                                       material:haloMaterial];
        if (halo != nil) {
            [group.container addChildNode:halo];
        }
    }

    [self applyStyleToGroup:group];
    group.container.hidden = ![self trackGroupMatchesDisplayFilter:group];
    group.container.opacity = 0.82;
    [self.trackRoot addChildNode:group.container];
    [group.container runAction:[SCNAction fadeOpacityTo:1.0 duration:0.14]
                              forKey:MDSTrackAppearanceActionKey];
    _trackSequence += 1;

    [self.trackGroups addObject:group];
    self.trackGroupsByEventID[@(event.eventID)] = group;
    [self scheduleTrackFadeForGroup:group
                             delay:[self holdDurationForTrackGroup:group]];
    [self trimOldTrackGroupsIfNeeded];
}

- (void)markEventIDsAccepted:(NSSet<NSNumber *> *)eventIDs {
    for (NSNumber *eventID in eventIDs) {
        MDSTrackGroup *group = self.trackGroupsByEventID[eventID];
        if (group != nil && !group.isAccepted) {
            group.accepted = YES;
            [self applyStyleToGroup:group];
            group.fadeStartTime = 0.0;
            group.container.opacity = 1.0;
            [self scheduleTrackFadeForGroup:group
                                     delay:[self holdDurationForTrackGroup:group]];
        }
    }
}

- (void)applyStyleToGroup:(MDSTrackGroup *)group {
    NSColor *coreColor = nil;
    NSColor *emissionColor = nil;
    CGFloat coreTransparency = 1.0;
    if (group.isShower) {
        coreColor = [NSColor colorWithSRGBRed:0.48 green:0.32 blue:0.83 alpha:1.0];
        emissionColor = [NSColor colorWithSRGBRed:0.42 green:0.26 blue:0.78 alpha:1.0];
        coreTransparency = group.isAccepted ? 0.92 : 0.48;
    } else if (group.isAccepted) {
        coreColor = [NSColor colorWithSRGBRed:0.06 green:0.58 blue:0.34 alpha:1.0];
        emissionColor = [NSColor colorWithSRGBRed:0.08 green:0.72 blue:0.43 alpha:1.0];
        coreTransparency = 0.96;
    } else {
        coreColor = [NSColor colorWithSRGBRed:0.82 green:0.43 blue:0.08 alpha:1.0];
        emissionColor = [NSColor colorWithSRGBRed:0.65 green:0.32 blue:0.02 alpha:1.0];
        coreTransparency = 0.45;
    }
    group.coreMaterial.diffuse.contents = coreColor;
    group.coreMaterial.emission.contents = emissionColor;
    group.coreMaterial.transparency = coreTransparency;

    const BOOL showHalo = group.isAccepted;
    group.haloMaterial.diffuse.contents =
        [NSColor colorWithSRGBRed:0.08 green:0.82 blue:0.50 alpha:1.0];
    group.haloMaterial.emission.contents =
        [NSColor colorWithSRGBRed:0.08 green:0.82 blue:0.50 alpha:1.0];
    group.haloMaterial.transparency = showHalo ? 0.22 : 0.0;
}

- (SCNNode *)lineNodeFromPoint:(MDSVector3)start
                       toPoint:(MDSVector3)end
                        radius:(double)radius
                      material:(SCNMaterial *)material {
    const double dx = end.x - start.x;
    const double dy = end.y - start.y;
    const double dz = end.z - start.z;
    const double length = sqrt(dx * dx + dy * dy + dz * dz);
    if (length < 0.001) {
        return nil;
    }

    SCNCylinder *cylinder =
        [SCNCylinder cylinderWithRadius:radius height:length];
    cylinder.radialSegmentCount = 12;
    cylinder.firstMaterial = material;
    SCNNode *node = [SCNNode nodeWithGeometry:cylinder];
    node.position = SCNVector3Make((start.x + end.x) * 0.5,
                                   (start.y + end.y) * 0.5,
                                   (start.z + end.z) * 0.5);

    simd_float3 direction = simd_normalize(
        simd_make_float3(dx, dy, dz));
    if (simd_length(simd_cross(simd_make_float3(0.0, 1.0, 0.0), direction)) < 1.0e-5 &&
        simd_dot(simd_make_float3(0.0, 1.0, 0.0), direction) < 0.0) {
        node.simdOrientation = simd_quaternion((float)M_PI,
                                                simd_make_float3(1.0, 0.0, 0.0));
    } else {
        node.simdOrientation = simd_quaternion(simd_make_float3(0.0, 1.0, 0.0),
                                                direction);
    }
    node.name = @"Particle track";
    node.castsShadow = NO;
    node.renderingOrder = 44;
    return node;
}

- (void)scheduleTrackFadeForGroup:(MDSTrackGroup *)group
                            delay:(NSTimeInterval)delay {
    if (group == nil || !self.fadesTracks) {
        return;
    }
    group.fadeStartTime = [NSProcessInfo processInfo].systemUptime +
        MAX(0.0, delay);
    [self ensureTrackFadeTimer];
}

- (NSTimeInterval)holdDurationForTrackGroup:(MDSTrackGroup *)group {
    return group.isShower ? MDSShowerTrackFadeHoldDuration
                          : MDSTrackFadeHoldDuration;
}

- (NSTimeInterval)fadeDurationForTrackGroup:(MDSTrackGroup *)group {
    return group.isShower ? MDSShowerTrackFadeDuration
                          : MDSTrackFadeDuration;
}

- (void)ensureTrackFadeTimer {
    if (_trackFadeTimer != nil) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    NSTimer *timer = [NSTimer timerWithTimeInterval:1.0 / 30.0
                                           repeats:YES
                                             block:^(NSTimer *activeTimer) {
        [weakSelf updateTrackFades:activeTimer];
    }];
    _trackFadeTimer = timer;
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
}

- (void)updateTrackFades:(NSTimer *)timer {
    const NSTimeInterval now = [NSProcessInfo processInfo].systemUptime;
    BOOL hasPendingFade = NO;
    for (MDSTrackGroup *group in self.trackGroups) {
        if (!self.fadesTracks || group.fadeStartTime <= 0.0) {
            continue;
        }
        const NSTimeInterval elapsed = now - group.fadeStartTime;
        if (elapsed < 0.0) {
            hasPendingFade = YES;
            continue;
        }
        const NSTimeInterval fadeDuration =
            [self fadeDurationForTrackGroup:group];
        const CGFloat progress = (CGFloat)MIN(1.0, elapsed / fadeDuration);
        group.container.opacity = 1.0 - progress;
        if (progress < 1.0) {
            hasPendingFade = YES;
        } else {
            group.fadeStartTime = 0.0;
        }
    }
    if (!hasPendingFade) {
        [self stopTrackFadeTimer];
    }
}

- (void)stopTrackFadeTimer {
    [_trackFadeTimer invalidate];
    _trackFadeTimer = nil;
}

- (void)trimOldTrackGroupsIfNeeded {
    const NSUInteger maximumGroups = 30;
    while (self.trackGroups.count > maximumGroups) {
        MDSTrackGroup *oldest = self.trackGroups.firstObject;
        [self.trackGroups removeObjectAtIndex:0];
        [self.trackGroupsByEventID removeObjectForKey:@(oldest.eventID)];
        [oldest.container runAction:
            [SCNAction sequence:@[
                [SCNAction fadeOutWithDuration:0.18],
                [SCNAction removeFromParentNode],
            ]]];
    }
}

- (void)clearTracks {
    [self stopTrackFadeTimer];
    for (SCNNode *child in [self.trackRoot childNodes]) {
        [child removeFromParentNode];
    }
    [self.trackGroups removeAllObjects];
    [self.trackGroupsByEventID removeAllObjects];
}

#pragma mark - Hit flashes and simulated sparks

- (void)flashHits:(NSArray<MDSHit *> *)hits {
    for (MDSHit *hit in hits) {
        if (hit.tubeIndex < 0 || hit.tubeIndex >= (NSInteger)self.tubeVisuals.count) {
            continue;
        }
        MDSTubeVisual *visual = self.tubeVisuals[(NSUInteger)hit.tubeIndex];
        [self addSparkForHit:hit toTubeVisual:visual];
    }
}

- (void)addSparkForHit:(MDSHit *)hit toTubeVisual:(MDSTubeVisual *)visual {
    const BOOL accepted = hit.isConsumed;
    const BOOL background = hit.isBackground;
    const BOOL fullSpark = accepted || !background;

    NSColor *ionColor = nil;
    NSColor *arcColor = nil;
    NSColor *coreColor = nil;
    if (accepted) {
        ionColor = [NSColor colorWithSRGBRed:0.10 green:0.92 blue:0.48 alpha:1.0];
        arcColor = [NSColor colorWithSRGBRed:0.00 green:0.68 blue:0.30 alpha:1.0];
        coreColor = [NSColor colorWithSRGBRed:0.72 green:1.0 blue:0.84 alpha:1.0];
    } else if (background) {
        ionColor = [NSColor colorWithSRGBRed:0.10 green:0.44 blue:0.95 alpha:1.0];
        arcColor = [NSColor colorWithSRGBRed:0.04 green:0.30 blue:0.74 alpha:1.0];
        coreColor = [NSColor colorWithSRGBRed:0.62 green:0.85 blue:1.0 alpha:1.0];
    } else {
        ionColor = [NSColor colorWithSRGBRed:0.00 green:0.66 blue:0.96 alpha:1.0];
        arcColor = [NSColor colorWithSRGBRed:0.00 green:0.48 blue:0.82 alpha:1.0];
        coreColor = [NSColor colorWithSRGBRed:0.66 green:0.94 blue:1.0 alpha:1.0];
    }

    const double radius = visual.tube.radius;
    const double length = visual.tube.length;
    uint64_t state = hit.hitID * 0xD1B54A32D192ED03ULL;
    state ^= (uint64_t)llround(hit.timestamp * 1000000000.0);
    state ^= (uint64_t)(hit.tubeIndex + 1) * 0x9E3779B97F4A7C15ULL;
    state = MDSSparkMix64(state);

    const double xExtent = length * (background ? 0.46 : 0.34);
    const double sparkX = MDSSparkSigned(&state) * xExtent;

    SCNNode *spark = [SCNNode node];
    spark.position = SCNVector3Make(sparkX, 0.0, 0.0);
    spark.name = accepted ? @"Coincidence spark" : @"Simulated tube spark";
    spark.castsShadow = NO;
    [visual.node addChildNode:spark];

    if (fullSpark) {
        // The visible discharge is drawn as thin colored filaments. Alpha rather
        // than additive blending keeps the electric shape legible against the
        // bright crystal envelope.
        SCNMaterial *arcMaterial = [SCNMaterial material];
        arcMaterial.lightingModelName = SCNLightingModelConstant;
        arcMaterial.diffuse.contents = arcColor;
        arcMaterial.emission.contents = ionColor;
        arcMaterial.transparency = 0.96;
        arcMaterial.blendMode = SCNBlendModeAlpha;
        arcMaterial.doubleSided = YES;
        arcMaterial.writesToDepthBuffer = NO;
        arcMaterial.readsFromDepthBuffer = NO;

        SCNMaterial *arcHaloMaterial = [SCNMaterial material];
        arcHaloMaterial.lightingModelName = SCNLightingModelConstant;
        arcHaloMaterial.diffuse.contents = ionColor;
        arcHaloMaterial.emission.contents = ionColor;
        arcHaloMaterial.transparency = 0.19;
        arcHaloMaterial.blendMode = SCNBlendModeAdd;
        arcHaloMaterial.doubleSided = YES;
        arcHaloMaterial.writesToDepthBuffer = NO;
        arcHaloMaterial.readsFromDepthBuffer = NO;

        // A jagged filament along the anode wire anchors the discharge and
        // keeps it readable at a glance; branches then reach for the glass wall.
        const double pathSpan = MIN(2.35, length * 0.23);
        const NSInteger pathSegments = 7;
        MDSVector3 path[8];
        for (NSInteger index = 0; index <= pathSegments; index++) {
            const double x = -pathSpan * 0.5 +
                pathSpan * (double)index / (double)pathSegments +
                MDSSparkSigned(&state) * pathSpan * 0.055;
            const double angle = MDSSparkUnit(&state) * 2.0 * M_PI;
            const double radial = radius *
                (index == 0 || index == pathSegments
                    ? 0.0
                    : 0.025 + 0.11 * MDSSparkUnit(&state));
            path[index] = MDSVector3Make(x,
                                         cos(angle) * radial,
                                         sin(angle) * radial);
        }

        SCNMaterial *sheathMaterial = [SCNMaterial material];
        sheathMaterial.lightingModelName = SCNLightingModelConstant;
        sheathMaterial.diffuse.contents = ionColor;
        sheathMaterial.emission.contents = ionColor;
        sheathMaterial.transparency = 0.10;
        sheathMaterial.blendMode = SCNBlendModeAlpha;
        sheathMaterial.writesToDepthBuffer = NO;
        sheathMaterial.readsFromDepthBuffer = NO;
        SCNCylinder *sheath =
            [SCNCylinder cylinderWithRadius:radius * 0.085
                                      height:pathSpan + 0.34];
        sheath.radialSegmentCount = 20;
        sheath.firstMaterial = sheathMaterial;
        SCNNode *sheathNode = [SCNNode nodeWithGeometry:sheath];
        sheathNode.eulerAngles = SCNVector3Make(0.0, 0.0, M_PI_2);
        sheathNode.castsShadow = NO;
        sheathNode.renderingOrder = 59;
        [spark addChildNode:sheathNode];

        for (NSInteger index = 0; index < pathSegments; index++) {
            SCNNode *core = [self lineNodeFromPoint:path[index]
                                            toPoint:path[index + 1]
                                             radius:0.022
                                           material:arcMaterial];
            SCNNode *halo = [self lineNodeFromPoint:path[index]
                                            toPoint:path[index + 1]
                                             radius:0.064
                                           material:arcHaloMaterial];
            for (SCNNode *node in @[ core, halo ]) {
                node.name = @"Electric discharge";
                node.castsShadow = NO;
                node.renderingOrder = 62;
                [spark addChildNode:node];
            }
        }

        const NSInteger branchCount = accepted ? 4 : 3;
        for (NSInteger branchIndex = 0; branchIndex < branchCount; branchIndex++) {
            const NSInteger originIndex = branchIndex % 2 == 0 ? 2 : 3;
            const double angle = MDSSparkUnit(&state) * 2.0 * M_PI;
            const MDSVector3 origin = path[originIndex];
            const MDSVector3 middle = MDSVector3Make(
                origin.x + MDSSparkSigned(&state) * radius * 0.30,
                cos(angle) * radius * 0.44,
                sin(angle) * radius * 0.44);
            const MDSVector3 end = MDSVector3Make(
                origin.x + MDSSparkSigned(&state) * radius * 0.55,
                cos(angle + MDSSparkSigned(&state) * 0.32) * radius * 0.81,
                sin(angle + MDSSparkSigned(&state) * 0.32) * radius * 0.81);

            SCNNode *firstCore = [self lineNodeFromPoint:origin
                                                 toPoint:middle
                                                  radius:0.019
                                                material:arcMaterial];
            SCNNode *secondCore = [self lineNodeFromPoint:middle
                                                  toPoint:end
                                                   radius:0.017
                                                 material:arcMaterial];
            SCNNode *firstHalo = [self lineNodeFromPoint:origin
                                                  toPoint:middle
                                                   radius:0.055
                                                 material:arcHaloMaterial];
            SCNNode *secondHalo = [self lineNodeFromPoint:middle
                                                   toPoint:end
                                                    radius:0.049
                                                  material:arcHaloMaterial];
            for (SCNNode *node in @[ firstCore, secondCore, firstHalo, secondHalo ]) {
                node.name = @"Electric branch";
                node.castsShadow = NO;
                node.renderingOrder = 63;
                [spark addChildNode:node];
            }
        }

        // A small hot core and a faint colored halo mark the strike point
        // without flooding the transparent tube with white light.
        SCNSphere *coreSphere = [SCNSphere sphereWithRadius:MAX(0.035, radius * 0.085)];
        coreSphere.segmentCount = 20;
        SCNMaterial *coreMaterial = [SCNMaterial material];
        coreMaterial.lightingModelName = SCNLightingModelConstant;
        coreMaterial.diffuse.contents = coreColor;
        coreMaterial.emission.contents = coreColor;
        coreMaterial.transparency = 0.88;
        coreMaterial.blendMode = SCNBlendModeAlpha;
        coreMaterial.writesToDepthBuffer = NO;
        coreMaterial.readsFromDepthBuffer = NO;
        coreSphere.firstMaterial = coreMaterial;
        SCNNode *coreNode = [SCNNode nodeWithGeometry:coreSphere];
        coreNode.castsShadow = NO;
        coreNode.renderingOrder = 66;
        [spark addChildNode:coreNode];

        SCNSphere *haloSphere = [SCNSphere sphereWithRadius:radius * 0.24];
        haloSphere.segmentCount = 28;
        SCNMaterial *haloMaterial = [SCNMaterial material];
        haloMaterial.lightingModelName = SCNLightingModelConstant;
        haloMaterial.diffuse.contents = ionColor;
        haloMaterial.emission.contents = ionColor;
        haloMaterial.transparency = 0.09;
        haloMaterial.blendMode = SCNBlendModeAlpha;
        haloMaterial.writesToDepthBuffer = NO;
        haloMaterial.readsFromDepthBuffer = NO;
        haloSphere.firstMaterial = haloMaterial;
        SCNNode *haloNode = [SCNNode nodeWithGeometry:haloSphere];
        haloNode.castsShadow = NO;
        haloNode.renderingOrder = 58;
        [spark addChildNode:haloNode];

        for (NSInteger moteIndex = 0; moteIndex < 3; moteIndex++) {
            SCNSphere *mote = [SCNSphere sphereWithRadius:0.020];
            mote.segmentCount = 10;
            SCNMaterial *moteMaterial = [SCNMaterial material];
            moteMaterial.lightingModelName = SCNLightingModelConstant;
            moteMaterial.diffuse.contents = coreColor;
            moteMaterial.emission.contents = coreColor;
            moteMaterial.transparency = 0.82;
            moteMaterial.blendMode = SCNBlendModeAlpha;
            moteMaterial.writesToDepthBuffer = NO;
            moteMaterial.readsFromDepthBuffer = NO;
            mote.firstMaterial = moteMaterial;
            SCNNode *moteNode = [SCNNode nodeWithGeometry:mote];
            moteNode.renderingOrder = 67;
            moteNode.castsShadow = NO;
            [spark addChildNode:moteNode];
            const CGFloat dx = MDSSparkSigned(&state) * radius * 0.65;
            const CGFloat dy = MDSSparkSigned(&state) * radius * 0.5;
            const CGFloat dz = MDSSparkSigned(&state) * radius * 0.5;
            [moteNode runAction:
                [SCNAction group:@[
                    [SCNAction moveByX:dx y:dy z:dz duration:0.19],
                    [SCNAction fadeOutWithDuration:0.19],
                ]]];
        }
    } else {
        // Background pulses get a tiny, dim blue flash so noise remains visible
        // without competing with a cosmic-ray crossing.
        SCNSphere *pulse = [SCNSphere sphereWithRadius:MAX(0.045, radius * 0.115)];
        pulse.segmentCount = 16;
        SCNMaterial *pulseMaterial = [SCNMaterial material];
        pulseMaterial.lightingModelName = SCNLightingModelConstant;
        pulseMaterial.diffuse.contents = coreColor;
        pulseMaterial.emission.contents = ionColor;
        pulseMaterial.transparency = 0.62;
        pulseMaterial.blendMode = SCNBlendModeAlpha;
        pulseMaterial.writesToDepthBuffer = NO;
        pulseMaterial.readsFromDepthBuffer = NO;
        pulse.firstMaterial = pulseMaterial;
        SCNNode *pulseNode = [SCNNode nodeWithGeometry:pulse];
        pulseNode.castsShadow = NO;
        pulseNode.renderingOrder = 60;
        [spark addChildNode:pulseNode];
    }

    SCNLight *sparkLight = nil;
    if (fullSpark) {
        sparkLight = [SCNLight light];
        sparkLight.type = SCNLightTypeOmni;
        sparkLight.color = ionColor;
        sparkLight.intensity = accepted ? 46.0 : 32.0;
        sparkLight.attenuationStartDistance = 0.06;
        sparkLight.attenuationEndDistance = 1.7;
        sparkLight.castsShadow = NO;
        SCNNode *lightNode = [SCNNode node];
        lightNode.light = sparkLight;
        [spark addChildNode:lightNode];
    }

    const NSTimeInterval holdDuration = fullSpark ? 0.26 : 0.10;
    const NSTimeInterval duration = holdDuration + (fullSpark ? 0.34 : 0.20);
    spark.opacity = 1.0;
    [self beginSparkEffectForNode:spark
                            light:sparkLight
                     holdDuration:holdDuration
                         duration:duration
                         flickers:fullSpark];
}

#pragma mark - Spark effect lifetime

- (void)beginSparkEffectForNode:(SCNNode *)node
                          light:(SCNLight *)light
                   holdDuration:(NSTimeInterval)holdDuration
                       duration:(NSTimeInterval)duration
                       flickers:(BOOL)flickers {
    MDSSparkEffect *effect = [[MDSSparkEffect alloc] init];
    effect.node = node;
    effect.light = light;
    effect.startTime = [NSProcessInfo processInfo].systemUptime;
    effect.holdDuration = holdDuration;
    effect.duration = MAX(duration, holdDuration + 0.01);
    effect.baseLightIntensity = light != nil ? light.intensity : 0.0;
    effect.flickers = flickers;
    [_sparkEffects addObject:effect];

    if (_sparkTimer == nil) {
        __weak typeof(self) weakSelf = self;
        NSTimer *timer = [NSTimer timerWithTimeInterval:1.0 / 30.0
                                               repeats:YES
                                                 block:^(NSTimer *activeTimer) {
            [weakSelf updateSparkEffects:activeTimer];
        }];
        _sparkTimer = timer;
        [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    }
}

- (void)updateSparkEffects:(NSTimer *)timer {
    const NSTimeInterval now = [NSProcessInfo processInfo].systemUptime;
    NSMutableArray<MDSSparkEffect *> *remaining = [NSMutableArray array];
    for (MDSSparkEffect *effect in _sparkEffects) {
        SCNNode *node = effect.node;
        if (node.parentNode == nil) {
            continue;
        }
        const NSTimeInterval elapsed = now - effect.startTime;
        if (elapsed >= effect.duration) {
            [node removeFromParentNode];
            continue;
        }

        CGFloat opacity = 1.0;
        if (elapsed >= effect.holdDuration) {
            const NSTimeInterval fadeDuration =
                MAX(0.01, effect.duration - effect.holdDuration);
            opacity = (CGFloat)MAX(0.0,
                MIN(1.0, (effect.duration - elapsed) / fadeDuration));
        } else if (effect.flickers) {
            const CGFloat flickerPhase = (CGFloat)fabs(sin(elapsed * 74.0));
            opacity = 0.66 + 0.34 * flickerPhase;
        }
        node.opacity = opacity;

        if (effect.light != nil) {
            CGFloat lightFactor = 1.0;
            if (effect.flickers) {
                lightFactor =
                    0.44 + 0.56 * (CGFloat)fabs(sin(elapsed * 58.0));
            }
            effect.light.intensity =
                effect.baseLightIntensity * opacity * lightFactor;
        }
        [remaining addObject:effect];
    }

    [_sparkEffects setArray:remaining];
    if (_sparkEffects.count == 0) {
        [_sparkTimer invalidate];
        _sparkTimer = nil;
    }
}

- (void)clearSparkEffects {
    for (MDSSparkEffect *effect in [_sparkEffects copy]) {
        [effect.node removeFromParentNode];
    }
    [_sparkEffects removeAllObjects];
    [_sparkTimer invalidate];
    _sparkTimer = nil;
}

- (void)dealloc {
    [_sparkTimer invalidate];
    [_trackFadeTimer invalidate];
}

@end






