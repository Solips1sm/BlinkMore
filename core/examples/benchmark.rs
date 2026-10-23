use blinkmore_core::{BMInput, BMPoint, Tracker};
use std::{hint::black_box, time::Instant};

fn main() {
    let points: [BMPoint; 8] = std::array::from_fn(|i| {
        let angle = i as f64 * std::f64::consts::TAU / 8.0;
        BMPoint {
            x: 0.5 + 0.10 * angle.cos(),
            y: 0.5 + 0.02 * angle.sin(),
        }
    });
    let mut tracker = Tracker::new();
    let mut samples = Vec::with_capacity(10_000);
    let start = Instant::now();
    for i in 1..=1_000_000 {
        let tick = Instant::now();
        let output = unsafe {
            tracker.process(black_box(BMInput {
                left: points.as_ptr(),
                right: points.as_ptr(),
                left_count: 8,
                right_count: 8,
                face_width: 200.0,
                face_height: 300.0,
                timestamp: i as f64 / 30.0,
                confidence: 0.99,
                sensitivity: 0.5,
            }))
        };
        black_box(output);
        if i % 100 == 0 {
            samples.push(tick.elapsed().as_nanos());
        }
    }
    let elapsed = start.elapsed().as_secs_f64();
    samples.sort_unstable();
    println!(
        "{{\"updates\":1000000,\"elapsed_seconds\":{elapsed},\"median_ns\":{},\"p95_ns\":{}}}",
        samples[samples.len() / 2],
        samples[samples.len() * 95 / 100]
    );
}
