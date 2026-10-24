"use strict";
const BlinkMetrics = (() => {
  const finite = (n) => typeof n === "number" && Number.isFinite(n);
  const value = (n) => finite(n) ? Math.max(0, n) : 0;
  function freshEyes(state = {}) {
    return ["tracking", "eyesClosed"].includes(state.phase) && finite(state.frameAgeMs) && state.frameAgeMs >= 0 && state.frameAgeMs <= 500 && finite(state.left) && finite(state.right);
  }
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
    return { points: pixels.map(draw), axes: [[axis(0, lo[0]), axis(0, hi[0])], [axis(1, lo[1]), axis(1, hi[1])]], aperture: (hi[1] - lo[1]) / (hi[0] - lo[0]), span: hi[0] - lo[0], height: hi[1] - lo[1], tilt: angle * 180 / Math.PI, center, area: Math.abs(pixels.reduce((sum, p, i) => { const q = pixels[(i + 1) % pixels.length]; return sum + p[0] * q[1] - q[0] * p[1]; }, 0)) / 2 };
  }
  function motion(samples, now, span = 30) {
    const paths = [[], []], areas = [[], []], events = [], difference = [];
    let previous = null, segmentStart = null, segmentEnd = null, observed = 0;
    if (!Array.isArray(samples) || !finite(now) || ![15,30,60].includes(span)) return { left: "", right: "", difference: "", areas: ["",""], events: [], observed: 0 };
    const closeArea = () => {
      if (segmentStart !== null) [80,160].forEach((base, i) => areas[i].push(`L${segmentEnd} ${base}L${segmentStart} ${base}Z`));
      segmentStart = null;
    };
    for (const sample of samples.slice(-1000)) {
      if (!finite(sample.t) || sample.t > now || sample.t < now - span) continue;
      if (!finite(sample.left) || !finite(sample.right)) { closeArea(); previous = null; continue; }
      if (previous !== null && sample.t <= previous) continue;
      const connected = previous !== null && sample.t - previous <= 0.25;
      if (!connected) closeArea();
      const command = connected ? "L" : "M", x = (12 + (sample.t - now + span) / span * 616).toFixed(2);
      if (segmentStart === null) segmentStart = x;
      segmentEnd = x;
      [sample.left, sample.right].forEach((v, side) => {
        const point = `${command}${x} ${(80 + side * 80 - Math.max(0, Math.min(1.5, v)) / 1.5 * 72).toFixed(2)}`;
        paths[side].push(point); areas[side].push(point);
      });
      difference.push(`${command}${x} ${(84-Math.max(-1,Math.min(1,sample.left-sample.right))*72).toFixed(2)}`);
      if (sample.events & 60) events.push({ x: Number(x), type: sample.events & 4 ? "blink" : sample.events & 32 ? "long" : sample.events & 8 ? "left" : "right" });
      if (connected) observed += sample.t - previous;
      previous = sample.t;
    }
    closeArea();
    return { left: paths[0].join(""), right: paths[1].join(""), difference: difference.join(""), areas: areas.map(p=>p.join("")), events, observed };
  }
  function setup(state = {}) {
    const fresh = finite(state.frameAgeMs) && state.frameAgeMs >= 0 && state.frameAgeMs <= 500;
    const g = state.geometry ?? {}, scene = state.scene ?? {};
    const visible = fresh && ["tracking","eyesClosed","calibrating"].includes(state.phase);
    const camera = fresh && !["paused","starting","cameraDenied","cameraError","cameraMissing"].includes(state.phase);
    const one = finite(scene.ageMs) && scene.ageMs >= 0 && scene.ageMs <= 1500 && scene.count === 1;
    const lids = visible && contour(g.left,g.width,g.height) !== null && contour(g.right,g.width,g.height) !== null;
    const reference = visible && state.calibration >= 1 && ["tracking","eyesClosed"].includes(state.phase);
    const freshMeasurement = fresh && finite(state.latencyMs) && state.latencyMs >= 0 && state.latencyMs <= 250;
    const checks = [
      {name:"Camera stream",ok:camera,detail:camera ? "Receiving frames" : state.phase === "cameraDenied" ? "Allow camera access" : state.phase === "paused" ? "Resume monitoring" : "Waiting for the camera"},
      {name:"One person",ok:one,detail:one ? "Single measurable face" : scene.count > 1 ? "One person at a time" : "Move into view"},
      {name:"Both eyelids",ok:lids,detail:lids ? "Both contours measured" : "Face the camera with both eyes visible"},
      {name:"Fresh samples",ok:freshMeasurement,detail:freshMeasurement ? `${Math.round(state.frameAgeMs)}ms sample age` : "Waiting for recent measurements"},
      {name:"Eye reference",ok:reference,detail:reference ? "Independent reference for each eye" : "Blink normally while calibration finishes"}
    ];
    return {checks,ready:checks.every(c=>c.ok),visible};
  }
  function replay(clip) {
    const result = {left:"",right:"",duration:0};
    if (!Array.isArray(clip) || clip.length < 2 || clip.length > 300) return result;
    const start = clip[0].t, end = clip[clip.length-1].t;
    if (![start,end].every(finite) || end <= start || end-start > 2) return result;
    const paths = [[],[]]; let previous = null;
    for (const p of clip) {
      if (!finite(p.t) || (previous !== null && p.t <= previous)) continue;
      if (!finite(p.left) || !finite(p.right)) { previous = null; continue; }
      const command = previous === null || p.t-previous > .25 ? "M" : "L", x = 4+(p.t-start)/(end-start)*312;
      [p.left,p.right].forEach((v,i)=>paths[i].push(`${command}${x.toFixed(2)} ${(32+i*36-Math.max(0,Math.min(1.5,v))*18).toFixed(2)}`));
      previous = p.t;
    }
    return {left:paths[0].join(""),right:paths[1].join(""),duration:end-start};
  }
  return { activity, ring, contour, aperture, motion, setup, replay, freshEyes };
})();
if (typeof module !== "undefined") module.exports = BlinkMetrics;
