#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $(uname -s) == Darwin ]] || { echo 'Run UI checks in a macOS GUI session.' >&2; exit 1; }
mkdir -p test-results
Scripts/test-bundle-ui.sh
swiftc -parse-as-library Tests/OverlayFadeTests.swift BlinkMore/Services/OverlayFade.swift -o test-results/overlay-tests
test-results/overlay-tests
swiftc -parse-as-library Tests/DashboardTests.swift BlinkMore/Core/TrackingState.swift BlinkMore/UI/*.swift -o test-results/dashboard-tests
test-results/dashboard-tests
