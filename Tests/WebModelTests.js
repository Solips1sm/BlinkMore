"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const crypto = require("node:crypto");
const { activity, ring, contour, aperture, motion, freshEyes } = require("../BlinkMore/Resources/UI/metrics.js");
assert.equal(ring(120, 100).progress, 1);
assert.equal(ring(120, 100).complete, true);
assert.equal(ring(0, 100).complete, false);
assert.equal(ring(100, 0).complete, false);
assert.equal(ring(NaN, 100).complete, false);
assert.equal(ring(-10, 100).progress, 0);
assert.equal(ring(10, 0).goal, null);
assert.equal(ring(NaN, 10).current, 0);
assert.equal(ring(10, Infinity).progress, 0);
const progress = activity({ blinks: 240, trackedSeconds: 1200 }, [{ trackedSeconds: 30 }, { trackedSeconds: 29 }, { trackedSeconds: 60 }], { resets: 10, trackedSeconds: 1800, days: 7 }, { blinkGoal: 300, minuteGoal: 30, dayGoal: 3 });
assert.deepEqual(progress.gauges.map(r => r.progress), [2 / 3, 2 / 3, 0]);
assert.equal(progress.achievements.filter(a => a.earned).length, 4);
assert(activity({}, [], {resets:50,trackedSeconds:18000,days:14}).achievements.every(a => a.earned));
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

for (const [name, info] of Object.entries(manifest.assets)) {
  assert.equal(crypto.createHash("sha256").update(fs.readFileSync(`BlinkMore/Resources/UI/${name}`)).digest("hex"), info.sha256);
}

const trace = motion([{t:10,left:1,right:.8},{t:10.2,left:0,right:0},{t:11,left:1,right:1}], 12);
assert.equal((trace.left.match(/M/g)||[]).length, 2);
assert.equal((trace.left.match(/L/g)||[]).length, 1);
assert.equal(motion([{t:12,left:1,right:1}], 11).left, "");
assert.equal(motion([{t:1,left:1,right:1}], 40).left, "");
assert.equal((motion([{t:10,left:1,right:1},{t:10.1,left:null,right:null},{t:10.2,left:1,right:1}],11).left.match(/M/g)||[]).length,2);

assert.equal(projection.span,80);
assert.equal(projection.height,20);
assert.equal(projection.area,1600);
assert.deepEqual(projection.center,[80,50]);
const nativeTrace=motion([{t:10,left:1,right:0.5,events:0},{t:10.066,left:0.1,right:0.1,events:0},{t:10.133,left:1,right:1,events:4}],11,15);
assert.equal(nativeTrace.events.length,1);
assert.equal(nativeTrace.events[0].type,"blink");
assert(nativeTrace.left.includes("75.20"));
assert(nativeTrace.difference.includes("48.00"));
assert.equal(nativeTrace.areas.filter(Boolean).length,2);
assert(Math.abs(nativeTrace.observed-0.133)<1e-8);
assert.equal(motion([{t:1,left:1,right:1}],2,9).left,"");
assert.equal((motion([{t:10,left:1,right:1},{t:10.3,left:1,right:1}],11).left.match(/M/g)||[]).length,2);
console.log("Studio model passed: pixel geometry, native brief closure, signed difference, filled segments, event ticks and missing intervals");

const {setup,replay}=require("../BlinkMore/Resources/UI/metrics.js");
const prepared={phase:"tracking",frameAgeMs:60,latencyMs:30,left:1,right:.9,calibration:1,scene:{ageMs:300,count:1},geometry:{left:eye,right:eye,width:200,height:100}};
assert.equal(setup(prepared).ready,true);
assert.equal(setup({...prepared,frameAgeMs:800}).ready,false);
assert.equal(setup({...prepared,latencyMs:-1}).checks[3].ok,false);
assert.equal(setup({...prepared,scene:{ageMs:100,count:2}}).checks[1].ok,false);
assert.equal(setup({...prepared,phase:"cameraDenied"}).checks[0].ok,false);
assert.equal(setup({...prepared,calibration:.5}).checks[4].ok,false);
const calibrating=setup({...prepared,phase:"calibrating",calibration:.5});
assert.equal(calibrating.visible,true);
assert.equal(calibrating.checks[4].ok,false);
assert.equal(setup({...prepared,geometry:{}}).checks[2].ok,false);
assert.equal(freshEyes(prepared),true);
assert.equal(freshEyes({...prepared,frameAgeMs:501}),false);
assert.equal(freshEyes({...prepared,phase:"noFace"}),false);
assert.equal(freshEyes({...prepared,phase:"calibrating"}),false);
assert.equal(freshEyes({...prepared,left:null}),false);
const playback=replay([{t:0,left:1,right:1},{t:.1,left:.1,right:.1},{t:.2,left:1,right:1}]);
assert.equal(playback.duration,.2);assert(playback.left.includes("L160.00"));
assert.equal(replay([]).left,"");assert.equal(replay([{t:0,left:1,right:1},{t:3,left:1,right:1}]).left,"");
assert.equal((replay([{t:0,left:1,right:1},{t:.1,left:null,right:null},{t:.2,left:1,right:1}]).left.match(/M/g)||[]).length,2);

const practice = activity({resetSeconds:50},[{resets:1},{resets:0},{resets:2}],{},{practiceGoal:60,practiceDayGoal:3}).practiceGoals;
assert.deepEqual(practice.map(g=>g.current),[50,2]);
assert.equal(practice[0].complete,false);
assert.equal(activity({resetSeconds:60},[],{},{practiceGoal:60}).practiceGoals[0].complete,true);

const {recent,aggregate}=require("../BlinkMore/Resources/UI/metrics.js");
assert.equal(recent([{tracked:1,blinks:0}]).rate,null);
assert.equal(recent(Array.from({length:60},()=>({tracked:1,blinks:0}))).rate,0);
assert.equal(recent([{tracked:0,blinks:2},{tracked:NaN,blinks:5}]).blinks,0);
const weighted=aggregate([{trackedSeconds:30,blinks:10},{trackedSeconds:1200,blinks:180}]);
assert(Math.abs(weighted.rate-190*60/1230)<1e-10);
assert.equal(aggregate([{trackedSeconds:0,blinks:20}]).rate,null);
assert.equal(aggregate([{trackedSeconds:60,blinks:0}]).rate,0);

assert.equal(setup(prepared).next,"Ready");
assert.equal(setup({...prepared,phase:"cameraDenied"}).next,"Allow camera access");
