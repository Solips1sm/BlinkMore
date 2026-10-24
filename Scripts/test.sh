#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
cargo fmt --manifest-path core/Cargo.toml -- --check
cargo test --manifest-path core/Cargo.toml --locked
cargo clippy --manifest-path core/Cargo.toml --all-targets -- -D warnings
node --check BlinkMore/Resources/UI/dashboard.js
node --check BlinkMore/Resources/UI/metrics.js
node Tests/WebModelTests.js
if [[ $(uname -s) == Darwin ]]; then
  mkdir -p test-results
  swiftc -O -parse-as-library Tests/StateTests.swift BlinkMore/Core/TrackingState.swift BlinkMore/Core/EyeCheck.swift BlinkMore/Services/AppPreferences.swift BlinkMore/Services/DailyStatistics.swift -o test-results/state-tests
  test-results/state-tests
  swiftc -parse-as-library Tests/ReminderTests.swift BlinkMore/Core/TrackingState.swift BlinkMore/Core/ReminderPolicy.swift -o test-results/reminder-tests
  test-results/reminder-tests
  swiftc -parse-as-library Tests/ExerciseTests.swift BlinkMore/Core/ExercisePolicy.swift -o test-results/exercise-tests
  test-results/exercise-tests
  swiftc -parse-as-library Tests/EyeCheckTests.swift BlinkMore/Core/TrackingState.swift BlinkMore/Core/EyeCheck.swift -o test-results/eye-check-tests
  test-results/eye-check-tests
  cargo build --manifest-path core/Cargo.toml --locked
  swiftc -parse-as-library -import-objc-header core/include/BlinkCore.h Tests/CoreBridgeTests.swift core/target/debug/libblinkmore_core.a -o test-results/core-bridge-tests
  test-results/core-bridge-tests
  swiftc -parse-as-library -import-objc-header core/include/BlinkCore.h Tests/VisionPipelineTests.swift BlinkMore/Core/*.swift BlinkMore/Services/AppPreferences.swift BlinkMore/Services/DailyStatistics.swift BlinkMore/Services/EyeTrackingService.swift core/target/debug/libblinkmore_core.a -o test-results/vision-pipeline-tests
  test-results/vision-pipeline-tests
fi
