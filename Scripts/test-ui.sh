#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $(uname -s) == Darwin ]] || { echo 'Run UI checks in a macOS GUI session.' >&2; exit 1; }
mkdir -p test-results
cargo build --manifest-path core/Cargo.toml --locked
swiftc -parse-as-library -import-objc-header core/include/BlinkCore.h Tests/NativeWindowTests.swift BlinkMore/Core/*.swift BlinkMore/Services/*.swift BlinkMore/UI/*.swift BlinkMore/App/ApplicationController.swift core/target/debug/libblinkmore_core.a -o test-results/native-window-tests
test-results/native-window-tests
swiftc -parse-as-library Tests/DashboardTests.swift BlinkMore/Core/TrackingState.swift BlinkMore/UI/*.swift -o test-results/dashboard-tests
test-results/dashboard-tests
