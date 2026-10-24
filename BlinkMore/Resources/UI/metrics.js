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
      rings: [ring(today.blinks, goals.blinkGoal), ring(value(today.trackedSeconds) / 60, goals.minuteGoal), ring(days, goals.dayGoal)],
      achievements: [
        { name: "First blink", detail: "One bilateral blink recorded", current: value(lifetime.blinks), target: 1, glyph: "eye" },
        { name: "A thousand", detail: "1,000 blinks in saved history", current: value(lifetime.blinks), target: 1000, glyph: "spark" },
        { name: "Half an hour", detail: "30 tracked minutes recorded", current: value(lifetime.trackedSeconds) / 60, target: 30, glyph: "clock" },
        { name: "Seven days", detail: "Seven days with 30s of data", current: value(lifetime.days), target: 7, glyph: "award" }
      ].map(a => ({ ...a, earned: a.current + 1e-6 >= a.target, progress: Math.min(1, a.current / a.target) }))
    };
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
  return { activity, ring, contour };
})();
if (typeof module !== "undefined") module.exports = BlinkMetrics;
