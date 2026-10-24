# BlinkMore

BlinkMore is a macOS menu bar app that gently fades the screen after a period without a detected blink. This fork keeps monitoring active on AC power and stops the app and camera on battery. It includes a calibrated Rust eyelid core, a local HTML/CSS dashboard hosted by Swift, light and dark themes, custom aperture and progress gauges, guided resets, personal blink comparisons and live eyelid geometry.

This is a fork of [oxremy/BlinkMore](https://github.com/oxremy/BlinkMore), maintained under [Solips1sm](https://github.com/Solips1sm/BlinkMore). The original MIT license and attribution are preserved. This build is separate from the upstream commercial app.

![Dark dashboard with synthetic QA data](docs/dashboard-dark.png)

![Light dashboard with synthetic QA data](docs/dashboard-light.png)

The screenshots use explicit QA fixtures. They contain no real camera images or personal tracking data.

## Build and install

Use macOS 14 or later, Xcode Command Line Tools and the stable Rust toolchain. Build on the Mac architecture you intend to run.

```sh
Scripts/test.sh
Scripts/build.sh
Scripts/install.sh
```

Set `BLINKMORE_SIGN_IDENTITY` when a valid local code signing identity is available; otherwise the build uses an ad hoc signature.

The build produces `dist/BlinkMore.app` and `dist/BlinkMoreACAgent`. The installer backs up the current app before replacing `/Applications/BlinkMore.app`, installs one login LaunchAgent and migrates the earlier Codex power watcher. It restores the previous app if installation fails. Installation requires write access to `/Applications`; it does not request administrator privileges automatically.

Allow camera access when macOS requests it. A locally signed replacement can require camera approval again. Look toward the camera with your eyes naturally open and blink normally while calibration completes. Left click the responsive eye icon to open the dashboard. Right click or Control click for the native menu with current blink statistics, pause, reminder controls, preview, calibration and Settings. The original open and closed eye images follow detected eyelid closures; a detected blink remains visible for 120 ms. The eight circle identity remains in the app icon and dashboard. The screen reminder duration and color from the previous installation are retained. Sensitivity uses the new calibrated scale.

Monitoring starts automatically when the charger is connected, including after login and wake. Disconnecting AC stops the app and releases the camera. Pause turns off the camera for five minutes; Resume starts a new calibration immediately. Turning off screen reminders keeps local activity measurement running. Preview reaches the selected tint quickly and shows it for two seconds without changing the daily reminder count. Automatic reminders wait for a blink afterward.

## Tracking and performance

AVFoundation captures 640 × 480 frames and discards late frames. Vision selects a visible primary face, follows its bounding box between full searches and finds both eyelid contours. Weak detections and faces smaller than 80 pixels are ignored. Overlap keeps the current face selected when background faces appear; equally sized candidates without a tracked match pause monitoring. A short capture callback replaces one pending pixel buffer while the separate serial inference queue is busy. Each inference consumes the newest buffer. Eye measurements run at up to 15 fps. Bounding box tracking waits 200 ms after its previous completion, allowing eyelid measurements between location updates. Frames already 100 ms old are rejected before expensive Vision work. There is at most one pending UI delivery, so a busy dashboard cannot create an unbounded frame backlog. Full face searches run every 0.7 seconds during tracking and at most five times per second while a face is absent; a second person entering between searches can take that interval to be detected.

Rust handles contour geometry, pixel aspect correction, independent eye calibration, smoothing, hysteresis, bilateral blink episodes and time accounting. It uses no external crates and allocates no memory during frame processing. Calibration collects at least 18 valid observations and 1.2 seconds of visible data. It derives each eye’s baseline from its upper aperture percentile. The C interface is used only from the capture queue; borrowed landmark buffers stay alive through each call.

Frames older than 250 ms are rejected. Explicit frame invalidation keeps calibration and clears temporal history without advancing the capture clock. Gaps over 250 ms reset blink episodes and the reminder clock, so missed camera time cannot become a phantom blink or an immediate fade. Face loss, uncertain pose and multiple faces clear reminders. Camera errors and a stalled stream trigger bounded retries. Closing the dashboard stops its update timer and releases its web view. The dashboard updates at most five times per second while visible, with one JavaScript update in flight. History and achievement views update only when their data changes; live contour drawing runs only on the Geometry tab. Tracking and fading stay native and do not wait on WebKit. Screen overlays redraw only when their color or intensity changes, and animate only on visibility transitions. Each blink interval receives one cue. A short inference gap does not restart its animation; a fresh eye closure clears it immediately, and lost tracking clears it within half a second. A six second safety limit clears a cue and waits for a blink or a restarted observation interval, rather than repeatedly pulsing the screen.

The Rust benchmark processes one million synthetic updates. The recorded Intel run measured a 714 ns 95th percentile per update, or 817 ns with two additional busy CPU workers. See [the measurement](docs/core-benchmark.json). These values exclude camera capture, Vision and display latency. They establish core overhead, not a measured improvement in real world detection accuracy or a guarantee under arbitrary CPU saturation. The dashboard shows actual camera delay, recent 95th percentile delay and processed frame rate. Eyeglass reflections, lighting, camera angle and CPU contention still affect tracking.

## Daily activity and privacy

Camera frames and facial landmarks stay in memory. The app has no network entitlement. Its interface uses bundled HTML/CSS in a nonpersistent WKWebView with network connections blocked by its content security policy. Camera access, the menu bar, fade overlays, color picker and file dialogs remain native. The bridge accepts commands only from the bundled main page and validates settings in Swift. It saves completed reset counts and guided seconds as daily aggregates, daily blink counts, visible tracking time, separate unilateral closure counts, longer bilateral closure counts, calibrated tracking and closed eye time, reminder counts and aggregate calibrated openness differences. Files are stored in the app sandbox under `Library/Application Support/BlinkMore/daily-statistics.json`. No raw eye measurements, video or per blink timestamps are written during normal operation. The explicit `--diagnose` launch flag writes one local status file with the current processing phase, calibration progress, quality checks and timing for troubleshooting. It contains no camera images or eye contour coordinates. Passing `--diagnose` to the AC agent forwards the flag to the app it launches.

The eye difference compares current openness against each eye’s own calibrated baseline. It describes unequal movement during tracked open eye periods, rather than anatomical eye size or a medical diagnosis. Separate unilateral closure counters describe short closures without a matching closure in the other eye. Blink rate appears after 30 seconds of visible data; mean eye difference appears after five seconds of calibrated open eye data.

The Today and History views prioritize today’s bilateral blink count, the recent rate, the daily rate and change from your own baseline. Recent rate uses tracked exposure within the last 60 wall clock seconds and needs 15 valid seconds. Daily rate needs 30 tracked seconds. The baseline combines the preceding six days, weighted by tracked time; days need 30 seconds each and the total needs five minutes. A zero baseline produces no relative percentage. The chart shows rate rather than raw count so shorter sessions are not presented as comparable daily totals. No population target or health score is assigned.

Short unilateral episodes are counted separately. Bilateral closures longer than 1.2 seconds are counted on reopening, separately from blinks. Both eyes closed reports the sampled share of newly calibrated tracking time with both eyelids classified as closed. These new counters begin with this version; existing history remains readable and unavailable older metrics stay empty. Missed frames, short closures and camera calibration affect these estimates. The camera’s left and right landmark names are used consistently; they are not a diagnosis of anatomical asymmetry.

Export includes retained history. Delete history requires confirmation and preserves data if the file cannot be removed safely. Saves are atomic and run off the capture queue. Corrupt files are copied for recovery before replacement; failed recovery disables saving to avoid overwriting the original. Recovery copies remain available locally after deleting current statistics. The recent window stays in memory and is cleared when history is deleted.

## Interface and design primitives

The Swift window hosts the local interface at 820 × 580 by default, with a 680 × 520 minimum. Today, Practice, History and Settings use regular and medium type, a 14 px text floor, keyboard navigation and reduced motion. Actual Anistratenco foundations, surface tokens, controls and checkbox CSS remain bundled unchanged. [The provenance manifest](docs/design-primitives.json) records their paths and hashes. The separate design repository is not modified. Native window elevation and shared inset and control recipes own depth. Shadow changes are immediate. Color stays inside bounded artwork with fixed gradients. The eight circle identity, responsive menu bar eye and native right click menu remain.

Today combines schematic eyelid apertures, the recent rate and an observation rhythm. Each eye drawing uses its own calibrated reference and clears with unavailable data. The trace exposes at most sixty in memory second bins, distinguishing observed time without a blink from a missing interval. Bins are not persisted or included in exports. History shows daily rate, personal comparisons, observed time and day goal arcs. These user selected goals have no clinical target. The old blink count goal is no longer shown. Settings retains the saved keys and existing reminder controls. Command comma opens Settings; Command W closes the dashboard.

Four custom milestone drawings reflect retained history: one completed reset, ten resets, thirty observed minutes and seven days with at least thirty observed seconds each. Native completion records each timed reset once. Cancelled or interrupted sessions add nothing. Deleting history resets achievements. Existing records remain readable; reset fields are optional and older days have no fabricated exercise counts. The installer backs up aggregate statistics locally alongside the previous app before replacement.

## Guided resets

Practice offers a thirty second sequence of ten seconds of natural blink play followed by a twenty second look away prompt. Either step also works alone. Eyelid events produce optional visual feedback without a required repetition count, speed target or complete blink grade. The look away scene asks for a distant real object; elapsed guidance does not verify gaze, viewing distance or a health result. No camera is required to finish a reset. Pause, Resume and End work through native state. Escape pauses a running reset. Leaving Practice or closing the window ends it.

Scheduled invitations are opt in, with a twenty minute starter interval and a five to sixty minute range. A quiet invitation appears in an open dashboard; the native menu can always start a reset. No exercise timer opens a window over the user's work. Later replaces the single deadline with a five minute retry. Sleep, inactive sessions, lock, five minute monitoring pause and at least sixty seconds of input inactivity reset cadence without replaying missed prompts. Lock uses macOS distributed notifications alongside public workspace lifecycle events and needs live verification on each macOS release. AC loss terminates the app as before.

Swift owns monotonic exercise deadlines independently of the web view and camera clock. A started reset clears the current tint and suspends automatic fades. Completing or ending it waits for a new blink interval before reminders resume. Native tracking and the menu bar icon remain independent of dashboard rendering. Completion saves only daily count and guided duration; no individual session timestamps or raw measurements are added. Built in exercises are independently authored. No ScreenBlink source, models, text, icons or sounds are imported.

## Measurement inspector

Settings contains an expandable inspector for actual Vision contours, principal axes, pixel aspect corrected aperture, calibrated openness, face crop proportions, observation confidence and sample age. Stale or unavailable contours clear. Equations explain calibration, smoothing and closure hysteresis. Observation confidence describes Vision's result, not measured blink accuracy. Interface colors are not eye coloration measurements. Iris color and retinal data are not inferred from this webcam mode. [Retinal imaging uses specialized optics and cameras](https://www.asrs.org/patients/advanced-retinal-imaging).

## Validation

`Scripts/test.sh` runs eleven Rust tests, Clippy with warnings rejected, JavaScript syntax and model checks, native exercise scheduling, reminder, preference and persistence tests plus real Swift to Rust ABI and blank frame Vision integration tests on macOS. Node.js 22 or later is used only by the JavaScript tests, not by the application or build. Coverage includes unordered contours, head roll, face aspect, independent eye sizes, blinks at 15 to 60 fps, unilateral closures, long closures, missing frames, stale time, FFI boundary validation, recovery, deletion ordering and daylight saving rollover.

Run the actual WKWebView dashboard and AppKit menu checks in a logged in macOS GUI session:

```sh
swiftc -parse-as-library Tests/DashboardTests.swift BlinkMore/Core/TrackingState.swift BlinkMore/UI/*.swift -o test-results/dashboard-tests
test-results/dashboard-tests
```

These checks exercise every tracking state, both themes, actual bridge controls and actions, arc gauge values, saved milestones, observation bins, camera independent exercise states and commands, chart focus preservation, live and stale geometry, light and dark text contrast, reduced motion, blink icon transitions, context menu actions, the smallest window size and minimum text size. Screenshots are written to `test-results`. CI tests the Rust core on Linux and builds the native app on macOS. Camera accuracy, battery transitions and screen visibility require a real Mac and are not claimed by synthetic tests.
