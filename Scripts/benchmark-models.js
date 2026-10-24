"use strict";
const assert = require("node:assert/strict");
const m = require("../BlinkMore/Resources/UI/metrics.js");
const bins = Array.from({length:60}, (_,i)=>({tracked:i%7?1:0,blinks:i%5===0?1:0}));
const week = Array.from({length:7},()=>({trackedSeconds:1800,blinks:450,resets:2,resetSeconds:40}));
const points = n=>Array.from({length:n},(_,i)=>[.5+.2*Math.cos(i*2*Math.PI/n),.5+.08*Math.sin(i*2*Math.PI/n)]);
const trace = Array.from({length:1000},(_,i)=>({t:i/15+1,left:1+.1*Math.sin(i),right:1,events:0}));
assert.equal(m.aggregate(week).rate,15);
assert.equal(m.contour(points(32),200,300).points.length,32);
const jobs = {
 goals:()=>m.activity(week[0],week,{trackedSeconds:12600,days:7,resets:14},{}),
 recent:()=>m.recent(bins), weightedWeek:()=>m.aggregate(week),
 contour8:()=>m.contour(points8,200,300), contour32:()=>m.contour(points32,200,300),
 motion1000:()=>m.motion(trace,68,60), setup:()=>m.setup({phase:"cameraDenied"})
};
const points8=points(8),points32=points(32);
const results=[];let checksum=0;
for(const [name,job] of Object.entries(jobs)) {
 for(let i=0;i<100;i++) job();
 const times=[];
 for(let i=0;i<500;i++){const start=process.hrtime.bigint();const out=job();times.push(Number(process.hrtime.bigint()-start)/1000);checksum+=Object.keys(out).length;}
 times.sort((a,b)=>a-b);
 results.push({name,samples:500,medianUs:times[250],p95Us:times[475]});
}
assert(checksum>0);
console.log(JSON.stringify({runtime:process.version,unit:"microseconds",fixture:"Synthetic bounded models; excludes DOM, camera and Vision",results}));
