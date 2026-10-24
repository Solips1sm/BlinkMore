//! Allocation-free, time-based bilateral eyelid processing. Camera and ML stay native.
use std::slice;

pub const VALID: u32 = 1;
pub const CALIBRATED: u32 = 2;
pub const BLINK: u32 = 4;
pub const LEFT_ONLY: u32 = 8;
pub const RIGHT_ONLY: u32 = 16;
pub const LONG_CLOSURE: u32 = 32;
const MAX_POINTS: usize = 32;
const MAX_GAP: f64 = 0.25;

#[repr(C)]
#[derive(Clone, Copy)]
pub struct BMPoint {
    pub x: f64,
    pub y: f64,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct BMInput {
    pub left: *const BMPoint,
    pub left_count: u32,
    pub right: *const BMPoint,
    pub right_count: u32,
    pub face_width: f64,
    pub face_height: f64,
    pub timestamp: f64,
    pub confidence: f64,
    pub sensitivity: f64,
}

#[repr(C)]
#[derive(Clone, Copy, Default, Debug)]
pub struct BMOutput {
    pub phase: u32,
    pub flags: u32,
    pub closed_mask: u32,
    pub left_openness: f64,
    pub right_openness: f64,
    pub left_ratio: f64,
    pub right_ratio: f64,
    pub calibration: f64,
    pub open_seconds: f64,
    pub tracked_delta: f64,
    pub asymmetry: f64,
}

/// Rotated principal-axis aperture, independent of contour order or point count.
/// Pixel scaling is essential: Vision's points are normalized to the face box.
pub fn aperture(points: &[BMPoint], width: f64, height: f64) -> Option<f64> {
    if !(4..=MAX_POINTS).contains(&points.len())
        || !width.is_finite()
        || !height.is_finite()
        || width <= 0.0
        || height <= 0.0
    {
        return None;
    }
    let mut mx = 0.0;
    let mut my = 0.0;
    for p in points {
        if !p.x.is_finite()
            || !p.y.is_finite()
            || !(0.0..=1.0).contains(&p.x)
            || !(0.0..=1.0).contains(&p.y)
        {
            return None;
        }
        mx += p.x * width;
        my += p.y * height;
    }
    mx /= points.len() as f64;
    my /= points.len() as f64;
    let (mut xx, mut xy, mut yy) = (0.0, 0.0, 0.0);
    for p in points {
        let (x, y) = (p.x * width - mx, p.y * height - my);
        xx += x * x;
        xy += x * y;
        yy += y * y;
    }
    // The covariance half-angle gives the same axes without atan2 and sin/cos.
    let spread = (xx - yy).hypot(2.0 * xy);
    if !spread.is_finite() {
        return None;
    }
    let (c, s) = if spread == 0.0 {
        (1.0, 0.0)
    } else if xx >= yy {
        let c = ((1.0 + (xx - yy) / spread) * 0.5).sqrt();
        (c, (xy / spread) / c)
    } else {
        let s = ((1.0 - (xx - yy) / spread) * 0.5).sqrt().copysign(xy);
        ((xy / spread) / s, s)
    };
    let (mut lo_x, mut hi_x, mut lo_y, mut hi_y) = (
        f64::INFINITY,
        f64::NEG_INFINITY,
        f64::INFINITY,
        f64::NEG_INFINITY,
    );
    for p in points {
        let (x, y) = (p.x * width - mx, p.y * height - my);
        let (u, v) = (x * c + y * s, -x * s + y * c);
        lo_x = lo_x.min(u);
        hi_x = hi_x.max(u);
        lo_y = lo_y.min(v);
        hi_y = hi_y.max(v);
    }
    let span = hi_x - lo_x;
    if span < 8.0 {
        return None;
    }
    let ratio = (hi_y - lo_y) / span;
    if ratio.is_finite() && (0.0..=1.0).contains(&ratio) {
        Some(ratio)
    } else {
        None
    }
}

#[derive(Default)]
struct Eye {
    filtered: f64,
    baseline: f64,
    closed: bool,
}

impl Eye {
    fn update(&mut self, ratio: f64, dt: f64, alpha: f64, close: f64) -> f64 {
        self.filtered += alpha * (ratio - self.filtered);
        let openness = (self.filtered / self.baseline).clamp(0.0, 1.5);
        if self.closed {
            self.closed = openness < close + 0.16;
        } else {
            self.closed = openness < close;
        }
        // Follow sustained open-eye changes slowly, without learning a blink as normal.
        if !self.closed && (0.90..1.4).contains(&openness) {
            let tau = if ratio > self.baseline { 30.0 } else { 120.0 };
            self.baseline += (dt / tau).min(0.01) * (ratio - self.baseline);
        }
        openness
    }
}

pub struct Tracker {
    left: Eye,
    right: Eye,
    samples: [[f64; 128]; 2],
    count: usize,
    cursor: usize,
    calibration_seconds: f64,
    calibrated: bool,
    last_time: Option<f64>,
    last_valid: Option<f64>,
    open_since: Option<f64>,
    episode_start: Option<f64>,
    episode_mask: u32,
    episode_overlap: bool,
}

impl Default for Tracker {
    fn default() -> Self {
        Self::new()
    }
}

impl Tracker {
    pub fn new() -> Self {
        Self {
            left: Eye::default(),
            right: Eye::default(),
            samples: [[0.0; 128]; 2],
            count: 0,
            cursor: 0,
            calibration_seconds: 0.0,
            calibrated: false,
            last_time: None,
            last_valid: None,
            open_since: None,
            episode_start: None,
            episode_mask: 0,
            episode_overlap: false,
        }
    }

    fn clear_temporal(&mut self) {
        self.open_since = None;
        self.episode_start = None;
        self.episode_mask = 0;
        self.episode_overlap = false;
        self.left.closed = false;
        self.right.closed = false;
    }

    fn missing(&mut self, phase: u32) -> BMOutput {
        self.clear_temporal();
        self.last_valid = None;
        BMOutput {
            phase,
            calibration: if self.calibrated {
                1.0
            } else {
                self.progress()
            },
            ..Default::default()
        }
    }

    fn progress(&self) -> f64 {
        (self.calibration_seconds / 1.2)
            .min(self.count as f64 / 18.0)
            .min(0.95)
    }

    /// Pointers must reference the stated number of live points for this call.
    /// The tracker must have one caller at a time; Swift owns the serial capture queue.
    /// # Safety
    /// Non-null point pointers must be readable for their declared lengths (at most 32).
    pub unsafe fn process(&mut self, input: BMInput) -> BMOutput {
        let t = input.timestamp;
        if !t.is_finite() || t < 0.0 || self.last_time.is_some_and(|last| t <= last) {
            return self.missing(5);
        }
        if !input.confidence.is_finite()
            || input.confidence < 0.6
            || input.confidence > 1.0
            || input.left.is_null()
            || input.right.is_null()
            || !(4..=MAX_POINTS as u32).contains(&input.left_count)
            || !(4..=MAX_POINTS as u32).contains(&input.right_count)
        {
            return self.missing(0);
        }
        let left = unsafe { slice::from_raw_parts(input.left, input.left_count as usize) };
        let right = unsafe { slice::from_raw_parts(input.right, input.right_count as usize) };
        let (Some(l), Some(r)) = (
            aperture(left, input.face_width, input.face_height),
            aperture(right, input.face_width, input.face_height),
        ) else {
            return self.missing(4);
        };
        let dt = self.last_valid.map_or(0.0, |last| t - last);
        let reset = dt <= 0.0 || dt > MAX_GAP;
        if reset {
            self.clear_temporal();
        }
        self.last_time = Some(t);
        self.last_valid = Some(t);
        let tracked_delta = if reset { 0.0 } else { dt };
        if !self.calibrated {
            self.samples[0][self.cursor] = l;
            self.samples[1][self.cursor] = r;
            self.cursor = (self.cursor + 1) % 128;
            self.count = (self.count + 1).min(128);
            self.calibration_seconds += tracked_delta;
            if self.count >= 18 && self.calibration_seconds >= 1.2 {
                let mut baseline = [0.0; 2];
                for (side, target) in baseline.iter_mut().enumerate() {
                    let mut sorted = self.samples[side];
                    sorted[..self.count].sort_unstable_by(f64::total_cmp);
                    *target = sorted[(self.count - 1) * 4 / 5];
                }
                if baseline.iter().all(|x| *x >= 0.075) {
                    self.left.baseline = baseline[0];
                    self.right.baseline = baseline[1];
                    self.left.filtered = l;
                    self.right.filtered = r;
                    self.calibrated = true;
                }
            }
            if !self.calibrated {
                return BMOutput {
                    phase: 1,
                    flags: VALID,
                    calibration: self.progress(),
                    left_ratio: l,
                    right_ratio: r,
                    tracked_delta,
                    ..Default::default()
                };
            }
        }
        let sensitivity = if input.sensitivity.is_finite() {
            input.sensitivity.clamp(0.0, 1.0)
        } else {
            0.5
        };
        let close = 0.38 + 0.28 * sensitivity;
        let alpha = if reset {
            1.0
        } else {
            1.0 - (-tracked_delta / 0.025).exp()
        };
        let ln = self.left.update(l, tracked_delta, alpha, close);
        let rn = self.right.update(r, tracked_delta, alpha, close);
        let closed = u32::from(self.left.closed) | (u32::from(self.right.closed) << 1);
        let mut flags = VALID | CALIBRATED;
        if closed != 0 {
            self.open_since = None;
            if self.episode_start.is_none() {
                self.episode_start = Some(t);
            }
            self.episode_mask |= closed;
            self.episode_overlap |= closed == 3;
        } else {
            if let Some(start) = self.episode_start {
                if (0.025..=1.2).contains(&(t - start)) {
                    if self.episode_overlap {
                        flags |= BLINK;
                    } else {
                        if self.episode_mask & 1 != 0 {
                            flags |= LEFT_ONLY;
                        }
                        if self.episode_mask & 2 != 0 {
                            flags |= RIGHT_ONLY;
                        }
                    }
                } else if t - start > 1.2 && self.episode_overlap {
                    flags |= LONG_CLOSURE;
                }
                self.episode_start = None;
                self.episode_mask = 0;
                self.episode_overlap = false;
            }
            self.open_since.get_or_insert(t);
        }
        BMOutput {
            phase: if closed == 0 { 2 } else { 3 },
            flags,
            closed_mask: closed,
            left_openness: ln,
            right_openness: rn,
            left_ratio: l,
            right_ratio: r,
            calibration: 1.0,
            open_seconds: self.open_since.map_or(0.0, |start| t - start),
            tracked_delta,
            asymmetry: (ln - rn).abs() / ((ln + rn) * 0.5).max(0.2),
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn bm_tracker_new() -> *mut Tracker {
    Box::into_raw(Box::new(Tracker::new()))
}

/// # Safety
/// `tracker` is null or an unfreed pointer returned by bm_tracker_new, with no concurrent calls.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn bm_tracker_free(tracker: *mut Tracker) {
    if !tracker.is_null() {
        drop(unsafe { Box::from_raw(tracker) });
    }
}

/// # Safety
/// `tracker` is null or a live pointer returned by bm_tracker_new, with no concurrent calls.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn bm_tracker_reset(tracker: *mut Tracker) {
    if let Some(tracker) = unsafe { tracker.as_mut() } {
        *tracker = Tracker::new();
    }
}

/// Clear only temporal history after a missing or stale capture; keep eye calibration.
/// # Safety
/// `tracker` is null or a live pointer returned by bm_tracker_new, with no concurrent calls.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn bm_tracker_invalidate(tracker: *mut Tracker) -> BMOutput {
    match unsafe { tracker.as_mut() } {
        Some(tracker) => tracker.missing(0),
        None => BMOutput {
            phase: 5,
            ..Default::default()
        },
    }
}

/// # Safety
/// Tracker and point buffers must satisfy the ownership and length contracts in process().
#[unsafe(no_mangle)]
pub unsafe extern "C" fn bm_tracker_process(tracker: *mut Tracker, input: BMInput) -> BMOutput {
    match unsafe { tracker.as_mut() } {
        Some(tracker) => unsafe { tracker.process(input) },
        None => BMOutput {
            phase: 5,
            ..Default::default()
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn eye(ratio: f64, angle: f64, width: f64, height: f64) -> [BMPoint; 8] {
        let (s, c) = angle.sin_cos();
        std::array::from_fn(|i| {
            let a = i as f64 * std::f64::consts::TAU / 8.0;
            let (x, y) = (20.0 * a.cos(), 20.0 * ratio * a.sin());
            BMPoint {
                x: 0.5 + (x * c - y * s) / width,
                y: 0.5 + (x * s + y * c) / height,
            }
        })
    }

    fn step(tracker: &mut Tracker, t: f64, l: f64, r: f64) -> BMOutput {
        let left = eye(l, 0.0, 200.0, 300.0);
        let right = eye(r, 0.0, 200.0, 300.0);
        unsafe {
            tracker.process(BMInput {
                left: left.as_ptr(),
                right: right.as_ptr(),
                left_count: 8,
                right_count: 8,
                face_width: 200.0,
                face_height: 300.0,
                timestamp: t,
                confidence: 0.99,
                sensitivity: 0.5,
            })
        }
    }

    fn calibrated() -> Tracker {
        let mut tracker = Tracker::new();
        for i in 1..=60 {
            step(&mut tracker, i as f64 / 30.0, 0.30, 0.22);
        }
        assert!(tracker.calibrated);
        tracker
    }

    #[test]
    fn aperture_handles_roll_aspect_ratio_and_unordered_contours() {
        for angle in [0.0, 0.25, 0.65, -0.5] {
            let mut points = eye(0.3, angle, 160.0, 360.0);
            let value = aperture(&points, 160.0, 360.0).unwrap();
            assert!((value - 0.3).abs() < 1e-10);
            points.reverse();
            assert!((aperture(&points, 160.0, 360.0).unwrap() - value).abs() < 1e-10);
        }
    }

    #[test]
    fn covariance_axes_match_trigonometric_reference_for_irregular_contours() {
        fn reference(points: &[BMPoint], width: f64, height: f64) -> f64 {
            let cx = points.iter().map(|p| p.x * width).sum::<f64>() / points.len() as f64;
            let cy = points.iter().map(|p| p.y * height).sum::<f64>() / points.len() as f64;
            let (mut xx, mut xy, mut yy) = (0.0, 0.0, 0.0);
            for p in points {
                let (x, y) = (p.x * width - cx, p.y * height - cy);
                xx += x * x;
                xy += x * y;
                yy += y * y;
            }
            let (s, c) = (0.5 * (2.0 * xy).atan2(xx - yy)).sin_cos();
            let (mut low, mut high) = ([f64::INFINITY; 2], [f64::NEG_INFINITY; 2]);
            for p in points {
                let (x, y) = (p.x * width - cx, p.y * height - cy);
                for (i, projected) in [x * c + y * s, -x * s + y * c].into_iter().enumerate() {
                    low[i] = low[i].min(projected);
                    high[i] = high[i].max(projected);
                }
            }
            (high[1] - low[1]) / (high[0] - low[0])
        }
        for count in 4..=MAX_POINTS {
            for angle in [0.0_f64, 1e-12, 1e-6, 0.25, 0.785, 1.57, -1.57, 2.9] {
                for ratio in [0.02, 0.15, 0.3, 0.8] {
                    let (s, c) = angle.sin_cos();
                    let points: Vec<_> = (0..count)
                        .map(|i| {
                            let t = i as f64 * std::f64::consts::TAU / count as f64;
                            let (x, y) = (
                                20.0 * t.cos(),
                                20.0 * ratio * t.sin() * (1.0 + 0.08 * (3.0 * t).cos()),
                            );
                            BMPoint {
                                x: 0.5 + (x * c - y * s) / 160.0,
                                y: 0.5 + (x * s + y * c) / 360.0,
                            }
                        })
                        .collect();
                    let actual = aperture(&points, 160.0, 360.0).unwrap();
                    assert!(
                        (actual - reference(&points, 160.0, 360.0)).abs() < 1e-10,
                        "count={count}, angle={angle}, ratio={ratio}"
                    );
                }
            }
        }
    }

    #[test]
    fn rejects_invalid_geometry() {
        assert!(
            aperture(
                &[BMPoint {
                    x: f64::NAN,
                    y: 0.0
                }; 8],
                200.0,
                300.0
            )
            .is_none()
        );
        assert!(aperture(&eye(0.3, 0.0, 200.0, 300.0), 0.0, 300.0).is_none());
        assert!(aperture(&[BMPoint { x: 0.5, y: 0.5 }; 8], 200.0, 300.0).is_none());
        assert!(aperture(&eye(0.3, 0.0, 200.0, 300.0), f64::MAX, f64::MAX).is_none());
    }

    #[test]
    fn independent_calibration_does_not_label_natural_eye_sizes_as_asymmetry() {
        let mut tracker = calibrated();
        let output = step(&mut tracker, 2.04, 0.30, 0.22);
        assert!(output.asymmetry < 0.001);
        assert_eq!(output.phase, 2);
    }

    #[test]
    fn bilateral_blink_counts_once_and_wink_does_not_count_as_blink() {
        let mut tracker = calibrated();
        assert_eq!(step(&mut tracker, 2.04, 0.03, 0.02).closed_mask, 3);
        step(&mut tracker, 2.08, 0.03, 0.02);
        assert_ne!(step(&mut tracker, 2.12, 0.30, 0.22).flags & BLINK, 0);
        assert_eq!(step(&mut tracker, 2.16, 0.30, 0.22).flags & BLINK, 0);
        step(&mut tracker, 2.20, 0.03, 0.22);
        step(&mut tracker, 2.24, 0.03, 0.22);
        let wink = step(&mut tracker, 2.28, 0.30, 0.22);
        assert_eq!(wink.flags & BLINK, 0);
        assert_ne!(wink.flags & LEFT_ONLY, 0);
    }

    #[test]
    fn inference_gap_cannot_create_phantom_blink_or_count_stale_time() {
        let mut tracker = calibrated();
        step(&mut tracker, 2.04, 0.03, 0.02);
        let output = step(&mut tracker, 3.0, 0.30, 0.22);
        assert_eq!(output.flags & BLINK, 0);
        assert_eq!(output.tracked_delta, 0.0);
        assert_eq!(output.open_seconds, 0.0);
    }

    #[test]
    fn long_eye_closure_is_not_a_blink() {
        let mut tracker = calibrated();
        for i in 1..=45 {
            step(&mut tracker, 2.0 + i as f64 / 30.0, 0.02, 0.02);
        }
        let opened = step(&mut tracker, 3.54, 0.30, 0.22);
        assert_eq!(opened.flags & BLINK, 0);
        assert_ne!(opened.flags & LONG_CLOSURE, 0);
        assert_eq!(step(&mut tracker, 3.58, 0.30, 0.22).flags & LONG_CLOSURE, 0);
    }

    #[test]
    fn calibration_excludes_normal_blinks_and_requires_valid_time() {
        let mut tracker = Tracker::new();
        for i in 1..=60 {
            let closed = (20..24).contains(&i);
            step(
                &mut tracker,
                i as f64 / 30.0,
                if closed { 0.02 } else { 0.3 },
                if closed { 0.02 } else { 0.22 },
            );
        }
        assert!(tracker.calibrated);
        assert!((tracker.left.baseline - 0.3).abs() < 0.01);
        assert_eq!(step(&mut tracker, f64::NAN, 0.3, 0.22).phase, 5);
        assert_eq!(step(&mut tracker, 1.0, 0.3, 0.22).phase, 5);
    }
    #[test]
    fn detects_blinks_with_variable_frame_intervals() {
        for interval in [1.0 / 15.0, 1.0 / 24.0, 1.0 / 30.0, 1.0 / 60.0] {
            let mut tracker = Tracker::new();
            let mut t = 0.0;
            let mut count = 0;
            while t < 8.0 {
                t += interval;
                let closed = (3.0..3.18).contains(&t) || (5.0..5.18).contains(&t);
                let output = step(
                    &mut tracker,
                    t,
                    if closed { 0.02 } else { 0.3 },
                    if closed { 0.02 } else { 0.22 },
                );
                if output.flags & BLINK != 0 {
                    count += 1;
                }
            }
            assert_eq!(count, 2, "frame interval {interval}");
        }
    }

    #[test]
    fn missing_frames_clear_closure_episodes_and_stare_time() {
        let mut tracker = calibrated();
        step(&mut tracker, 2.04, 0.03, 0.02);
        let missing = unsafe {
            tracker.process(BMInput {
                left: std::ptr::null(),
                right: std::ptr::null(),
                left_count: 0,
                right_count: 0,
                face_width: 0.0,
                face_height: 0.0,
                timestamp: 2.08,
                confidence: 0.0,
                sensitivity: 0.5,
            })
        };
        assert_eq!(missing.phase, 0);
        let output = step(&mut tracker, 2.12, 0.3, 0.22);
        assert_eq!(output.flags & BLINK, 0);
        assert_eq!(output.open_seconds, 0.0);
        assert_eq!(output.tracked_delta, 0.0);
    }

    #[test]
    fn ffi_rejects_null_and_excessive_counts_before_reading_buffers() {
        let output = unsafe {
            bm_tracker_process(
                std::ptr::null_mut(),
                BMInput {
                    left: std::ptr::null(),
                    right: std::ptr::null(),
                    left_count: u32::MAX,
                    right_count: 0,
                    face_width: 200.0,
                    face_height: 300.0,
                    timestamp: 1.0,
                    confidence: 1.0,
                    sensitivity: f64::NAN,
                },
            )
        };
        assert_eq!(output.phase, 5);
        let mut tracker = calibrated();
        let points = eye(0.3, 0.0, 200.0, 300.0);
        let output = unsafe {
            tracker.process(BMInput {
                left: points.as_ptr(),
                right: points.as_ptr(),
                left_count: u32::MAX,
                right_count: 8,
                face_width: 200.0,
                face_height: 300.0,
                timestamp: 2.04,
                confidence: 1.0,
                sensitivity: 0.5,
            })
        };
        assert_eq!(output.phase, 0);
    }
    #[test]
    fn invalid_frames_cannot_move_the_capture_clock_into_the_future() {
        let mut tracker = calibrated();
        step(&mut tracker, 2.04, 0.03, 0.02);
        let missing = unsafe {
            tracker.process(BMInput {
                left: std::ptr::null(),
                right: std::ptr::null(),
                left_count: 0,
                right_count: 0,
                face_width: 0.0,
                face_height: 0.0,
                timestamp: 10_000.0,
                confidence: 0.0,
                sensitivity: 0.5,
            })
        };
        assert_eq!(missing.calibration, 1.0);
        let fresh = step(&mut tracker, 2.12, 0.3, 0.22);
        assert_eq!(fresh.phase, 2);
        assert_eq!(fresh.open_seconds, 0.0);
        assert_eq!(fresh.tracked_delta, 0.0);
        assert_eq!(fresh.flags & BLINK, 0);
        unsafe { bm_tracker_invalidate(&mut tracker) };
        assert_eq!(step(&mut tracker, 2.16, 0.3, 0.22).phase, 2);
    }
}
