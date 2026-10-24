use blinkmore_core::{BLINK, BMInput, BMOutput, BMPoint, CALIBRATED, Tracker};
use std::{hint::black_box, time::Instant};

const FACE_WIDTH: f64 = 200.0;
const FACE_HEIGHT: f64 = 300.0;
const FRAME_RATE: f64 = 15.0;
const FRAME_SECONDS: f64 = 1.0 / FRAME_RATE;
const UPDATES: usize = 1_000_000;
const SAMPLE_EVERY: usize = 97;
const CALIBRATION_UPDATES: usize = 30;
const WARMUP_UPDATES: usize = 3_000;

struct Frame {
    left: [BMPoint; 8],
    right: [BMPoint; 8],
}

fn eye(ratio: f64, center_x: f64, angle: f64) -> [BMPoint; 8] {
    let (s, c) = angle.sin_cos();
    std::array::from_fn(|i| {
        let a = i as f64 * std::f64::consts::TAU / 8.0;
        let (x, y) = (20.0 * a.cos(), 20.0 * ratio * a.sin());
        BMPoint {
            x: center_x + (x * c - y * s) / FACE_WIDTH,
            y: 0.5 + (x * s + y * c) / FACE_HEIGHT,
        }
    })
}

fn frame(i: usize) -> Frame {
    let phase = i % 60;
    let blink = (34..=35).contains(&phase);
    let t = i as f64;
    let left_ratio = if blink {
        0.05
    } else {
        0.30 + 0.003 * (t * 0.19).sin()
    };
    let right_ratio = if blink {
        0.05
    } else {
        0.29 + 0.003 * (t * 0.17).cos()
    };
    let angle = 0.04 * (t * 0.11).sin();
    Frame {
        left: eye(left_ratio, 0.34, angle),
        right: eye(right_ratio, 0.66, -angle),
    }
}

fn input(frame: &Frame, timestamp: f64) -> BMInput {
    BMInput {
        left: frame.left.as_ptr(),
        left_count: frame.left.len() as u32,
        right: frame.right.as_ptr(),
        right_count: frame.right.len() as u32,
        face_width: FACE_WIDTH,
        face_height: FACE_HEIGHT,
        timestamp,
        confidence: 0.99,
        sensitivity: 0.5,
    }
}

fn process(tracker: &mut Tracker, input: BMInput) -> BMOutput {
    unsafe { black_box(tracker).process(black_box(input)) }
}

fn main() {
    let frames: Vec<_> = (0..60).map(frame).collect();
    let mut tracker = Tracker::new();
    let mut timestamp = 0.0;

    for i in 0..CALIBRATION_UPDATES {
        timestamp += FRAME_SECONDS;
        let output = process(&mut tracker, input(&frames[i % frames.len()], timestamp));
        if i + 1 == CALIBRATION_UPDATES {
            assert!(
                output.flags & CALIBRATED != 0,
                "calibration must finish before timing"
            );
        }
    }

    let mut blink_events = 0;
    for i in 0..WARMUP_UPDATES {
        timestamp += FRAME_SECONDS;
        blink_events += usize::from(
            process(&mut tracker, input(&frames[i % frames.len()], timestamp)).flags & BLINK != 0,
        );
    }
    assert!(
        blink_events > 0,
        "synthetic workload must exercise blink processing"
    );

    let mut samples = Vec::with_capacity(UPDATES.div_ceil(SAMPLE_EVERY));
    let start = Instant::now();
    for i in 0..UPDATES {
        timestamp += FRAME_SECONDS;
        let input = input(&frames[i % frames.len()], timestamp);
        if i % SAMPLE_EVERY == 0 {
            let tick = Instant::now();
            let output = process(&mut tracker, input);
            samples.push(tick.elapsed().as_nanos());
            blink_events += usize::from(black_box(output).flags & BLINK != 0);
        } else {
            blink_events += usize::from(process(&mut tracker, input).flags & BLINK != 0);
        }
    }
    let elapsed = start.elapsed().as_secs_f64();
    samples.sort_unstable();
    println!(
        "{{\"architecture\":\"{}\",\"workload\":\"calibrated_tracking\",\"frame_rate_hz\":{FRAME_RATE},\"updates\":{UPDATES},\"calibration_updates\":{CALIBRATION_UPDATES},\"warmup_updates\":{WARMUP_UPDATES},\"landmarks_per_eye\":8,\"sample_every_updates\":{SAMPLE_EVERY},\"samples\":{},\"elapsed_seconds\":{elapsed},\"mean_ns_per_update\":{},\"median_ns\":{},\"p95_ns\":{},\"blink_events\":{blink_events}}}",
        std::env::consts::ARCH,
        samples.len(),
        elapsed * 1e9 / UPDATES as f64,
        samples[samples.len() / 2],
        samples[samples.len() * 95 / 100],
    );
}
