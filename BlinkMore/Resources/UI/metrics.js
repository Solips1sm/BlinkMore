"use strict";
const BlinkMetrics = (() => {
  const finite = (n) => typeof n === "number" && Number.isFinite(n);
  const value = (n) => finite(n) ? Math.max(0, n) : 0;
  function ring(current, goal) {
    const available = finite(goal) && goal > 0;
    return { current: value(current), goal: available ? goal : null, progress: available ? Math.min(1, value(current) / goal) : 0 };
  }
  function activity(today = {}, week = [], lifetime = {}, goals = {}) {
    const days = week.filter(d => finite(d.trackedSeconds) && d.trackedSeconds + 1e-6 >= 30).length;
    return {
      gauges: [ring(value(today.trackedSeconds) / 60, goals.minuteGoal), ring(days, goals.dayGoal), ring(value(today.resets), goals.resetGoal ?? 1)],
      achievements: [
        { name: "First moment", detail: "Finish one guided reset", current: value(lifetime.resets), target: 1, unit: "resets", glyph: "moment" },
        { name: "Ten moments", detail: "Finish ten guided resets", current: value(lifetime.resets), target: 10, unit: "resets", glyph: "petals" },
        { name: "Half an hour", detail: "Thirty minutes observed", current: value(lifetime.trackedSeconds) / 60, target: 30, unit: "min", glyph: "orbit" },
        { name: "Seven days", detail: "Seven days with thirty seconds observed", current: value(lifetime.days), target: 7, unit: "days", glyph: "days" },
        { name: "One hour", detail: "One hour observed across your history", current: value(lifetime.trackedSeconds) / 60, target: 60, unit: "min", glyph: "hour" },
        { name: "Fifty moments", detail: "Finish fifty guided resets", current: value(lifetime.resets), target: 50, unit: "resets", glyph: "bloom" },
        { name: "Five hours", detail: "Five hours observed across your history", current: value(lifetime.trackedSeconds) / 60, target: 300, unit: "min", glyph: "sun" },
        { name: "Two weeks", detail: "Fourteen days with thirty seconds observed", current: value(lifetime.days), target: 14, unit: "days", glyph: "calendar" }
      ].map(a => ({ ...a, earned: a.current + 1e-6 >= a.target, progress: Math.min(1, a.current / a.target) }))
    };
  }
  function aperture(opening, cx, cy, width) {
    if (![opening, cx, cy, width].every(finite) || width <= 0) return null;
    const gap = 24 * Math.min(1.5, Math.max(0, opening));
    return `M${cx-width/2} ${cy}Q${cx} ${cy-gap} ${cx+width/2} ${cy}Q${cx} ${cy+gap} ${cx-width/2} ${cy}Z`;
  }
  function contour(points, width, height) {
    if (!Array.isArray(points) || points.length < 4 || points.length > 32 || !finite(width) || !finite(height) || width <= 0 || height <= 0) return null;
    if (points.some(p => !Array.isArray(p) || p.length !== 2 || p.some(n => !finite(n) || n < 0 || n > 1))) return null;
    const pixels = points.map(([x, y]) => [x * width, (1 - y) * height]);
    const center = [0, 1].map(i => pixels.reduce((sum, p) => sum + p[i], 0) / pixels.length);
    let xx = 0, yy = 0, xy = 0;
    pixels.forEach(([x, y]) => { x -= center[0]; y -= center[1]; xx += x * x; xy += x * y; yy += y * y; });
    const angle = Math.atan2(2 * xy, xx - yy) / 2, c = Math.cos(angle), s = Math.sin(angle);
    const projected = pixels.map(([x, y]) => [(x - center[0]) * c + (y - center[1]) * s, -(x - center[0]) * s + (y - center[1]) * c]);
    const lo = [0, 1].map(i => Math.min(...projected.map(p => p[i]))), hi = [0, 1].map(i => Math.max(...projected.map(p => p[i])));
    if (hi[0] - lo[0] < 8) return null;
    const minX = Math.min(...pixels.map(p => p[0])), maxX = Math.max(...pixels.map(p => p[0]));
    const minY = Math.min(...pixels.map(p => p[1])), maxY = Math.max(...pixels.map(p => p[1]));
    const scale = Math.min(172 / Math.max(1, maxX - minX), 74 / Math.max(1, maxY - minY));
    const draw = ([x, y]) => [100 + (x - (minX + maxX) / 2) * scale, 56 + (y - (minY + maxY) / 2) * scale];
    const axis = (i, distance) => draw([center[0] + (i === 0 ? distance * c : -distance * s), center[1] + (i === 0 ? distance * s : distance * c)]);
    return { points: pixels.map(draw), axes: [[axis(0, lo[0]), axis(0, hi[0])], [axis(1, lo[1]), axis(1, hi[1])]], aperture: (hi[1] - lo[1]) / (hi[0] - lo[0]), span: hi[0] - lo[0] };
  }
  function motion(samples, now) {
    const paths = [[], []]; let previous = null;
    if (!Array.isArray(samples) || !finite(now)) return { left: "", right: "" };
    for (const sample of samples.slice(-160)) {
      if (!finite(sample.t) || sample.t > now || sample.t < now - 30) continue;
      if (!finite(sample.left) || !finite(sample.right)) { previous = null; continue; }
      if (previous !== null && sample.t <= previous) continue;
      const command = previous === null || sample.t - previous > 0.5 ? "M" : "L";
      const x = 12 + (sample.t - now + 30) / 30 * 616;
      [sample.left, sample.right].forEach((v, side) => paths[side].push(`${command}${x.toFixed(2)} ${(76 - Math.max(0, Math.min(1.5, v)) / 1.5 * 64).toFixed(2)}`));
      previous = sample.t;
    }
    return { left: paths[0].join(""), right: paths[1].join("") };
  }
  return { activity, ring, contour, aperture, motion };
})();
if (typeof module !== "undefined") module.exports = BlinkMetrics;
