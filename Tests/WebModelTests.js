"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const crypto = require("node:crypto");
const { activity, ring, contour, aperture } = require("../BlinkMore/Resources/UI/metrics.js");
assert.equal(ring(120, 100).progress, 1);
assert.equal(ring(-10, 100).progress, 0);
assert.equal(ring(10, 0).goal, null);
assert.equal(ring(NaN, 10).current, 0);
assert.equal(ring(10, Infinity).progress, 0);
const progress = activity({ blinks: 240, trackedSeconds: 1200 }, [{ trackedSeconds: 30 }, { trackedSeconds: 29 }, { trackedSeconds: 60 }], { resets: 10, trackedSeconds: 1800, days: 7 }, { blinkGoal: 300, minuteGoal: 30, dayGoal: 3 });
assert.deepEqual(progress.gauges.map(r => r.progress), [2 / 3, 2 / 3]);
assert(progress.achievements.every(a => a.earned));
assert(activity({}, [], {}, {}).achievements.every(a => !a.earned));
assert.equal(aperture(NaN, 100, 60, 160), null);
assert.equal(aperture(1, 100, 60, -1), null);
assert.equal(aperture(-5, 100, 60, 160), aperture(0, 100, 60, 160));
assert.equal(aperture(5, 100, 60, 160), aperture(1.5, 100, 60, 160));
assert(aperture(1, 100, 60, 160).includes("Q100 36"));
const eye = [[0.2, 0.4], [0.6, 0.4], [0.6, 0.6], [0.2, 0.6]];
const projection = contour(eye, 200, 100);
assert(Math.abs(projection.aperture - 0.25) < 1e-10);
assert.equal(projection.points.length, 4);
assert.equal(projection.axes.length, 2);
const angle = 0.4;
const rolled = eye.map(([x, y]) => {
  const u = (x - 0.4) * 200, v = (y - 0.5) * 100;
  return [0.4 + (u * Math.cos(angle) - v * Math.sin(angle)) / 200, 0.5 + (u * Math.sin(angle) + v * Math.cos(angle)) / 100];
});
assert(Math.abs(contour(rolled, 200, 100).aperture - 0.25) < 1e-10);
assert.equal(contour([[0, 0], [NaN, 0], [1, 1], [0, 1]], 200, 100), null);
assert.equal(contour(eye, 0, 100), null);
assert.equal(contour([[0.5, 0.5], [0.51, 0.5], [0.51, 0.51], [0.5, 0.51]], 200, 100), null);
const manifest = JSON.parse(fs.readFileSync("docs/design-primitives.json", "utf8"));
for (const [name, info] of Object.entries(manifest.files)) {
  assert.equal(crypto.createHash("sha256").update(fs.readFileSync(`BlinkMore/Resources/UI/vendor/${name}`)).digest("hex"), info.sha256);
}
console.log("Web model tests passed: goal bounds, achievements, aspect correction, principal axes, invalid scans, design primitive hashes");
