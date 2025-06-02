# Muon Detector Simulator

A native macOS educational simulation of a three-tube cosmic-ray muon telescope.
It is written in Objective-C with AppKit and SceneKit and has no third-party
runtime dependencies or network features.

> **Simulation only.** This app does not measure radiation, connect to detector
> hardware, or produce calibrated scientific results. Every rate, count, track,
> and spark comes from a model with adjustable assumptions.

## Requirements

- macOS 13.0 or later to run the app.
- macOS 14.0 or later to run the XCTest target.
- Xcode with the macOS SDK. XcodeGen is optional; the generated Xcode project is
  checked in.

## Build and run

Open `MuonDetectorSimulator.xcodeproj` in Xcode, select the
`MuonDetectorSimulator` scheme, and run. Or build from Terminal:

```sh
xcodebuild \
  -project MuonDetectorSimulator.xcodeproj \
  -scheme MuonDetectorSimulator \
  -configuration Debug \
  build
```

The built app is normally under DerivedData:

```sh
open "$HOME"/Library/Developer/Xcode/DerivedData/MuonDetectorSimulator-*/Build/Products/Debug/"Muon Detector Simulator.app"
```

Run the tests with:

```sh
xcodebuild \
  -project MuonDetectorSimulator.xcodeproj \
  -scheme MuonDetectorSimulator \
  -destination 'platform=macOS' \
  test
```

To regenerate the project after changing `project.yml`, install XcodeGen and run
`xcodegen generate`. Building and testing the app do not require XcodeGen.

## Using the app

- **Start** begins the configured simulated interval. **Pause** and **Resume**
  control playback, **Step** advances to the next scheduled detector event, and
  **Reset** stops the run and unlocks the configuration.
- Drag in the 3D view to orbit; scroll or pinch to zoom. **Reset View** restores
  the fitted isometric camera. **Labels** shows or hides the tube and primary-
  direction annotations.
- **Hide Shield** is an overlay button inside the 3D view. It removes the clear
  crystal display cover so the tubes and mounts can be inspected, and changes to
  **Show Shield** to put the cover back. This affects presentation only.
- The **Particles** menu filters the recent 3D tracks to all particles, muon
  candidates, or shower particles. It is a display filter; hit flashes, statistics,
  the timeline, and the event log are unchanged.
- **Fade tracks** (also in the View menu) controls whether every recent particle
  track remains visible and then fades out. Single muon candidates use a short
  hold; shower trajectories use a longer hold (about six seconds) so the full
  particle fan can be inspected before it fades. Accepted green tracks keep
  their green styling during the hold; missed amber tracks fade the same way.
  Turn fading off to keep tracks on screen. This is presentation-only.
- **Export JSON…** in the Results header, or **File > Export Results as JSON…**
  (⌘E), saves a structured JSON report of the current run. **File > Export
  Results as CSV…** (⇧⌘E) saves the same data for a spreadsheet. Both contain the
  model settings and seed, summary counts, per-tube totals, histogram bins, and
  the retained event log, and carry the simulation-only disclaimer. The on-screen
  log and export retain at most the latest 3,000 rows; summary counts and
  histogram bins remain complete.
- Short-lived electric sparks mark simulated pulses: green for accepted
  coincidences, cyan for other particle hits, and a dim blue pulse for background.
  Spark positions are illustrative annotations, not reconstructed interaction
  points.
- The inspector validates every setting and explains its assumption. Configuration
  is locked while a run is active or complete; use **Reset** to edit and run again.
- The event log, timeline, per-tube totals, and coincidence readouts update while
  simulated time advances. The results describe the seeded model, not a physical
  detector.

## Default configuration

| Setting | Default |
| --- | --- |
| Duration | 60 simulated seconds |
| Random seed | 12345 |
| Tube centre-to-centre spacing | 6.0 cm |
| Transverse alignment offset | 0.0 cm |
| Active gas length | 10.0 cm |
| Active gas diameter | 1.4 cm |
| Detection efficiency, tubes 1 / 2 / 3 | 90% / 92% / 88% |
| Background rate | 2.0 pulses/s per tube |
| Arrival directions | vertical (simplified) |
| Candidate cosmic event rate | 30 events/min |
| Coincidence window | 1.0 µs |
| Required tubes | all three (3-fold) |
| Shower mode | off |
| Shower primary angle / azimuth | 10° from downward vertical / 30° |
| Shower multiplicity / angular spread | 6 particles / 8° |
| Fade tracks | on (presentation only) |

## Simulation model

The engine is Foundation-only and deterministic for a given seed and settings.

- **Arrivals.** Candidate cosmic events and each tube's background pulses use
  independent Poisson arrival processes. The default arrival model is a simplified
  vertical direction. The **Random (realistic)** model samples a new downward
  primary axis for each candidate using a cos²θ weighting up to 80° from vertical,
  with a uniform azimuth; the seeded PRNG makes the sequence reproducible. A
  candidate direction is retained only when a straight ray can cross every selected
  tube, so the default 3-fold stack has a narrow geometric acceptance and favors
  near-vertical tracks. In shower mode, particles are sampled uniformly in a cone
  around the primary axis. When the primary axis itself is random, its maximum
  zenith is reduced as needed so the whole shower cone remains below horizontal.
  If the configured geometry cannot be crossed by a downward ray, a random
  candidate falls back to an unconditional direction and may miss the required
  tubes.
- **Geometry.** Each active volume is a finite cylinder. Candidate rays are traced
  against the cylinders, including radial and end-cap intersections.
- **Detection.** A geometric crossing becomes a particle pulse only if an
  independent per-tube efficiency trial succeeds. Candidate primaries are aimed
  through the crossing interval of the selected tubes, so a candidate that cannot
  reach the required active volumes is not generated when the geometry permits a
  crossing ray. Rays directed toward the telescope aperture represent the subset
  of an isotropic flux that reaches this small detector; the candidate event rate
  is a user assumption, not a calibrated flux.
- **Timing.** Particle pulse timestamps receive deterministic Gaussian jitter with
  a fixed standard deviation of 0.025 µs, clipped to three standard deviations.
  Background pulses use their Poisson arrival time.
- **Coincidence.** On each new pulse in a selected tube, the engine searches back
  through unconsumed pulses in the other required tubes within the configured
  window and accepts the latest complete set. Each pulse can be used by at most
  one coincidence. A set built from more than one source, or containing background,
  is marked accidental.
- **Results.** Per-tube hit totals, 2-fold and 3-fold counts, accidental counts,
  histogram bins, elapsed simulated time, and the coincidence rate are derived from
  accepted coincidences. The rate is accepted coincidences per simulated minute;
  it is not a measurement.
- **Presentation.** The SceneKit view converts engine geometry into tube, track,
  label, and spark nodes. It does not participate in event generation or
  coincidence decisions. All particle tracks optionally fade after a hold using
  a presentation timer; shower trajectories linger longer so their fan is
  readable. The particle filter, labels, shield, and fade
  controls never alter the model.

### Units

- Length: centimetres.
- Simulated time and timestamps: seconds.
- Coincidence window: microseconds in the interface, seconds internally.
- Background rate: pulses per second per tube.
- Candidate cosmic rate: events per simulated minute.
- Coincidence rate: accepted coincidences per simulated minute.

## Exporting results

Use the **Export JSON…** button in the Results header or **File > Export Results
as JSON…** (⌘E) after starting a run. Choose a destination for a UTF-8 JSON file.
Use **File > Export Results as CSV…** (⇧⌘E) for the equivalent
spreadsheet-friendly CSV file. Both reports contain:

- a simulation-only disclaimer;
- the seed and all configuration assumptions, including the arrival-direction
  model;
- current simulated time, completion state, hit and coincidence totals, 2-fold
  and 3-fold counts, accidental count, and coincidence rate;
- per-tube hit totals and configured efficiencies;
- every histogram bin with its time range, hit count, and accepted-coincidence
  count;
- the retained event-log rows with numeric and display timestamps, source,
  details, and result.

The JSON report is pretty-printed with stable keys and nested `configuration`,
`simulation`, `summary`, `tube_totals`, `histogram`, `event_log`, and
`log_retention` sections so it can be inspected or scripted. The CSV report uses
the same sections in a flat, sectioned layout. Both formats state whether the log
was truncated.

The event log is capped at the latest 3,000 rows for presentation. The summary
counts and histogram remain exact for the run. Exported values are modeled
outputs, not measurements.

## Reproducibility

The pseudorandom generator is seeded. The same seed and settings produce the same
event sequence, timestamps, coincidences, and histogram totals regardless of
playback speed or whether the run is generated in one batch or advanced one event
at a time. Playback speed changes only the wall-clock pace. Use **Reset** to replay
the same sequence; use **Randomize** before starting to choose a new seed.

## Architecture

- `MuonDetectorSimulator/App` — application lifecycle, menus, main window, About
  panel, and debug capture harness.
- `MuonDetectorSimulator/UI` — main layout and playback, validated inspector,
  native event-log table, timeline drawing, and "How it works" content.
- `MuonDetectorSimulator/Scene` — SceneKit scene, stylized crystal GM tubes,
  removable display shield, labels, camera controls, tracks, hit sparks, and
  presentation-only effects.
- `MuonDetectorSimulator/Simulation` — Foundation-only simulator and seeded
  pseudorandom generator.
- `MuonDetectorSimulator/Models` — configuration, geometry, tube, hit, track,
  event, coincidence, and batch value objects, plus the Foundation-only JSON and
  CSV results exporter.
- `MuonDetectorSimulatorTests` — standalone XCTest coverage for the PRNG,
  ray/cylinder geometry, configuration validation, deterministic event sequences,
  random-direction and random-shower geometry, selected-tube acceptance,
  coincidence timing, background accidentals, shower multiplicity, JSON and CSV
  results export formatting, and statistics/histogram consistency.

## Modeling limits

The app intentionally omits dead time, recovery time, afterpulsing, pulse shape,
amplifier response, high-voltage behavior, detailed particle transport, energy
loss, multiple scattering, track reconstruction, material geometry, and a full
atmospheric cascade. Background is abstract Poisson noise. The random-direction
model is a seeded teaching approximation (cos²θ, capped at 80° from vertical and
filtered by selected-tube geometric acceptance), not a calibrated underground or
surface muon flux; it omits altitude, weather, geomagnetic, east-west, and
calibrated detector-acceptance corrections. The candidate rate, efficiencies,
geometry, and shower parameters are adjustable assumptions, not calibrations.
Coincidence reduces unrelated background but does not by itself prove that a
particle is a muon or determine its mass or energy.

The spark animation and display case are presentation elements. Removing the shield
does not alter the detector model, and a spark's position along a tube is not a
reconstructed physical interaction point.









