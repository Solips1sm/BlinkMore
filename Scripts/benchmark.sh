#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p test-results
cargo build --manifest-path core/Cargo.toml --release --example benchmark --locked
swiftc -O -parse-as-library Tests/PerformanceBenchmarks.swift BlinkMore/Core/TrackingState.swift BlinkMore/Core/EyeCheck.swift BlinkMore/Services/AppPreferences.swift BlinkMore/Services/DailyStatistics.swift -o test-results/performance-benchmarks
node Scripts/benchmark-models.js > test-results/models-benchmark.json
test-results/performance-benchmarks > test-results/statistics-benchmark.json
: > test-results/core-matrix.jsonl
for points in 4 8 16 32; do
  core/target/release/examples/benchmark "$points" >> test-results/core-matrix.jsonl
done
python3 - <<'PY'
import json,platform,datetime
from pathlib import Path
p=Path('test-results')
report={'date':datetime.datetime.now(datetime.timezone.utc).isoformat(),'host':platform.platform(),'command':'Scripts/benchmark.sh','limits':'Synthetic microbenchmarks. No camera, Vision, CPU contention, energy or long run memory measurement. No end to end latency claim.','models':json.loads((p/'models-benchmark.json').read_text()),'statistics':json.loads((p/'statistics-benchmark.json').read_text()),'rust':[json.loads(s) for s in (p/'core-matrix.jsonl').read_text().splitlines()]}
Path('docs/performance-benchmarks.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
PY
