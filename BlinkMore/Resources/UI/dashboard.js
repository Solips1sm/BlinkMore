"use strict";
(() => {
  const $ = id => document.getElementById(id), svgNS = "http://www.w3.org/2000/svg";
  const finite = n => typeof n === "number" && Number.isFinite(n);
  const fmt = (n, digits = 0, suffix = "") => finite(n) ? new Intl.NumberFormat(undefined, { maximumFractionDigits: digits }).format(Math.abs(n) < 0.5 * 10 ** -digits ? 0 : n) + suffix : "Collecting";
  const text = (id, value) => { const el = $(id); if (el && el.textContent !== String(value)) el.textContent = String(value); };
  const send = value => window.webkit?.messageHandlers?.blinkmore?.postMessage(value);
  const pages = ["activity", "practice", "history", "settings-page", "examine"], tabOrder = [0, 4, 1, 2, 3];
  let motionSpan = 30, studio = "motion", practiceBlinks = 0, replayFrame = null, replayClip = null;
  let current = null, selected = 0, historyKey = "", achievementKey = "", cameraKey = "", rhythmKey = "", lastBlinks = null, lastExercise = "idle", lastCheck = "idle", historySelection = null;
  function svg(name, attributes = {}) {
    const node = document.createElementNS(svgNS, name);
    Object.entries(attributes).forEach(([key, value]) => node.setAttribute(key, String(value))); return node;
  }
  function selectTab(index, focus = false) {
    if (!Number.isInteger(index) || index < 0 || index >= pages.length) return;
    if (index !== 1) stopReplay();
    if (selected === 1 && index !== 1 && ["running", "paused", "completed"].includes(current?.exercise?.phase)) send({ action: "exercise", command: "end" });
    if (selected === 4 && index !== 4) {
      if (current?.eyeCheck?.phase === "running") send({ action: "cancelCheck" });

    }
    const changed = selected !== index;
    if (changed) document.querySelector("main").scrollTop = 0;
    window.scrollTo(0, 0);
    selected = index; document.body.dataset.page = String(index);
    document.querySelectorAll("[data-tab]").forEach(button => {
      const active = Number(button.dataset.tab) === index;
      button.setAttribute("aria-selected", String(active)); button.tabIndex = active ? 0 : -1;
      if (active && focus) button.focus();
    });
    pages.forEach((page, i) => $(page).hidden = i !== index);
    const activeTab = document.querySelector(`[data-tab="${index}"]`), nav = document.querySelector("nav");
    nav.style.setProperty("--tab-x", `${activeTab.offsetLeft}px`);
    nav.style.setProperty("--tab-width", `${activeTab.offsetWidth}px`);
    if (changed) {
      send({ action: "view", tab: index });
      if (!document.documentElement.classList.contains("reduce-motion") && !matchMedia("(prefers-reduced-motion:reduce)").matches) {
        $(pages[index]).animate([{ opacity: .35, transform: "translateY(5px)" }, { opacity: 1, transform: "translateY(0)" }], { duration: 180, easing: "ease-out" });
      }
    }
    if (current && index === 0) { live(current); rhythm(current.statistics.recentBins); }
    if (current && index === 2) { progress(current); history(current.statistics.week, current.statistics.baselineRate); coverageView(current.coverage); }
    if (current && index === 4) {
      if (studio === "setup") setupView(current);
      else { geometry(current); liveView(current); }
    }
  }
  document.querySelectorAll("[data-tab]").forEach(button => {
    button.addEventListener("click", () => selectTab(Number(button.dataset.tab)));
    button.addEventListener("keydown", event => {
      const i = tabOrder.indexOf(Number(button.dataset.tab));
      const next = event.key === "ArrowRight" ? tabOrder[(i + 1) % 5] : event.key === "ArrowLeft" ? tabOrder[(i + 4) % 5] : event.key === "Home" ? 0 : event.key === "End" ? 3 : null;
      if (next === null) return; event.preventDefault(); selectTab(next, true);
    });
  });
  document.querySelectorAll("[data-action]").forEach(button => button.addEventListener("click", () => send({ action: button.dataset.action })));
  document.querySelectorAll("[data-exercise]").forEach(button => button.addEventListener("click", () => send({ action: "exercise", command: button.dataset.exercise })));
  document.querySelectorAll("button[data-routine]").forEach(button => button.addEventListener("click", () => send({ action: "exercise", command: "start", routine: button.dataset.routine })));
  document.querySelectorAll("[data-history]").forEach(button => button.addEventListener("click", () => selectTab(2)));
  document.querySelectorAll("[data-inspect]").forEach(button => button.addEventListener("click", () => { selectTab(4); $("measurement-details").open = true; if (current) geometry(current); }));
  new ResizeObserver(() => {
    const tab = document.querySelector(`[data-tab="${selected}"]`), nav = document.querySelector("nav");
    nav.style.setProperty("--tab-x", `${tab.offsetLeft}px`); nav.style.setProperty("--tab-width", `${tab.offsetWidth}px`);
  }).observe(document.querySelector("nav"));
  document.querySelectorAll("[data-span]").forEach(button => button.addEventListener("click", () => {
    motionSpan = Number(button.dataset.span);
    document.querySelectorAll("[data-span]").forEach(b => b.setAttribute("aria-pressed", String(b === button)));
    if (current) liveView(current);
  }));
  function selectStudio(next) {
    if (!["motion","difference","geometry","setup"].includes(next)) return;
    if (studio === next) return;
    if (studio !== next && current?.eyeCheck?.phase === "running") send({action:"cancelCheck"});
    if (studio !== next) document.querySelector("main").scrollTop = 0;
    studio = next; $("examine").dataset.studio = studio; send({action:"view",tab:selected,studio});
    document.querySelectorAll("button[data-studio]").forEach(b => b.setAttribute("aria-pressed",String(b.dataset.studio === studio)));
    $("geometry-workspace").hidden = studio !== "geometry";
    $("setup-workspace").hidden = studio !== "setup";
    document.querySelector(".motion-panel").hidden = !["motion","difference"].includes(studio);
    if (current) {
      if (studio === "setup") setupView(current);
      else { geometry(current); liveView(current); }
    }
  }
  document.querySelectorAll("button[data-studio]").forEach(button => button.addEventListener("click", () => selectStudio(button.dataset.studio)));
  function showSetup() { selectTab(4); selectStudio("setup"); document.querySelector("main").scrollTop = 0; }
  document.querySelectorAll("[data-setup]").forEach(button => button.addEventListener("click", showSetup));
  $("setup-settings").addEventListener("click",()=>selectTab(3));
  function stopReplay() { if (replayFrame !== null) cancelAnimationFrame(replayFrame); replayFrame = null; replayClip = null; }
  function mirrorEyes(left,right) {
    [["left",left,112],["right",right,328]].forEach(([side,value,cx])=>{
      const path = $("mirror-"+side), d = finite(value) ? BlinkMetrics.aperture(value,cx,50,176) ?? "" : "";
      if (path.getAttribute("d") !== d) path.setAttribute("d",d);
    });
  }
  $("mirror-replay").addEventListener("click",()=>{
    const clip = current?.mirror?.clip ?? [], trace = BlinkMetrics.replay(clip);
    if (!trace.left || current?.mirror?.phase === "running") return;
    stopReplay();
    if (current.reducedMotion || matchMedia("(prefers-reduced-motion:reduce)").matches) {
      text("mirror-source","Recorded trace"); text("mirror-description","Playback animation is off with reduced motion."); $("mirror-trace").focus(); return;
    }
    replayClip = clip;
    let sampleIndex = 0;
    const start = performance.now(), first = replayClip[0].t;
    const play = now => {
      if (!replayClip || selected !== 1) { stopReplay(); return; }
      const elapsed = (now-start)/1000, time = first+elapsed;
      while (sampleIndex + 1 < replayClip.length && replayClip[sampleIndex + 1].t <= time) sampleIndex++;
      const sample = replayClip[sampleIndex];
      mirrorEyes(sample && time-sample.t<=.25 ? sample.left : null,sample && time-sample.t<=.25 ? sample.right : null);
      text("mirror-source","Recorded blink");
      if (elapsed < trace.duration) replayFrame = requestAnimationFrame(play);
      else { replayFrame = null; replayClip = null; text("mirror-source","Replay complete"); }
    };
    replayFrame = requestAnimationFrame(play);
  });
  ["points", "axes"].forEach(overlay => $("overlay-" + overlay).addEventListener("click", event => {
    const button = event.currentTarget, visible = button.getAttribute("aria-pressed") !== "true";
    button.setAttribute("aria-pressed", String(visible));
    document.querySelectorAll(overlay === "points" ? ".landmark-points" : ".principal-axes").forEach(g => g.toggleAttribute("hidden", !visible));
  }));
  $("measurement-details").addEventListener("toggle", () => { if (current && $("measurement-details").open) geometry(current); });
  $("review-check").addEventListener("click", () => $("check-session").scrollIntoView({ block: "nearest" }));
  $("theme-cycle").addEventListener("click", () => {
    send({ action: "set", key: "theme", value: current?.actualTheme === "dark" ? "light" : "dark" });
  });
  const preferenceLabel = (key, n) => ["intensity", "sensitivity"].includes(key) ? fmt(n * 100, 0, "%") : ["reminderSeconds", "fadeSeconds"].includes(key) ? fmt(n, key === "fadeSeconds" ? 1 : 0, "s") : fmt(n);
  document.querySelectorAll("[data-preference]").forEach(input => {
    input.addEventListener("input", () => { if (input.type === "range") text(`label-${input.dataset.preference}`, preferenceLabel(input.dataset.preference, Number(input.value))); });
    input.addEventListener("change", () => {
      if (input.type === "checkbox") { const f = input.closest(".anistratenco-checkbox-frame"); f.dataset.activation = f.dataset.activation === "first" ? "repeat" : "first"; }
      send({ action: "set", key: input.dataset.preference, value: input.type === "checkbox" ? input.checked : input.type === "range" ? Number(input.value) : input.value });
    });
  });
  document.addEventListener("keydown", event => {
    if (event.key === "Escape" && current?.exercise?.phase === "running") { event.preventDefault(); send({ action: "exercise", command: "pause" }); $("exercise-resume").focus(); }
  });
  function live(state) {
    const active = BlinkMetrics.freshEyes(state);
    $("live-instrument").classList.toggle("unavailable", !active);
    ["left", "right"].forEach((side, i) => $(`${side}-live`).setAttribute("d", active ? BlinkMetrics.aperture(state[side], i === 0 ? 112 : 328, 66, 176) ?? "" : ""));
    $("live-eyes").setAttribute("aria-label", active ? `Relative eyelid opening. Left ${fmt(state.left * 100)} percent, right ${fmt(state.right * 100)} percent of each reference.` : "Live eyelid data unavailable");
  }
  function blinkPulse(state) {
    const blinks = state.statistics.lifetime?.blinks;
    if (finite(blinks) && lastBlinks !== null && blinks > lastBlinks) {
      for (const id of ["live-instrument", "exercise-art"]) $(id).dataset.blink = $(id).dataset.blink === "first" ? "repeat" : "first";
    }
    if (finite(blinks)) lastBlinks = blinks;
  }
  function rhythm(bins = []) {
    const key = JSON.stringify(bins); if (key === rhythmKey) return; rhythmKey = key;
    const fragment = document.createDocumentFragment(); let observed = 0, blinks = 0;
    Array.from({ length: 60 }, (_, i) => bins[i] ?? {}).forEach((bin, i) => {
      const tracked = finite(bin.tracked) && bin.tracked > 0, count = finite(bin.blinks) ? Math.max(0, Math.floor(bin.blinks)) : 0;
      const height = !tracked ? 18 : count > 0 ? 10 + 7 * Math.min(count, 3) : 2;
      fragment.append(svg("path", { d: `M${12 + i * 10.4} ${32 - height / 2}v${height}`, class: !tracked ? "rhythm-gap" : count > 0 ? "rhythm-event" : "rhythm-coverage" }));
      if (tracked) { observed += bin.tracked; blinks += count; }
    });
    if (observed === 0) fragment.replaceChildren(svg("path", { d: "M12 32H628", class: "rhythm-gap" }));
    $("rhythm-chart").replaceChildren(fragment);
    $("rhythm-chart").setAttribute("aria-label", `${fmt(blinks)} detected blinks in ${fmt(observed)} tracked seconds. Dashed intervals have no observations. Mark height caps at three events per second.`);
  }
  const medal = {
    moment: "M7 29h34M13 28a11 11 0 0 1 22 0M24 9v5M10 15l4 4M38 15l-4 4M13 36h22",
    petals: "M24 24C2 4 2 44 24 24C44 2 4 2 24 24C46 44 46 4 24 24C4 46 44 46 24 24ZM20 24h8M24 20v8",
    orbit: "M11 35A17 17 0 1 1 37 35M24 3v6M3 24h6M39 24h6M24 15v9l8 6M16 42h16",
    days: "M6 33V24M12 33V16M18 33V20M24 33V10M30 33V17M36 33V13M42 33V22M6 39h36",
    hour: "M24 5a19 19 0 1 0 0 38a19 19 0 1 0 0-38M24 12v13l9 5M24 5v3M5 24h3M40 24h3",
    bloom: "M24 24C4 0 0 24 24 24C0 44 24 48 24 24C44 48 48 24 24 24C48 4 24 0 24 24ZM24 19v10M19 24h10",
    sun: "M12 28a12 12 0 0 1 24 0M5 29h38M24 5v7M8 11l5 5M40 11l-5 5M8 36h32M15 42h18",
    calendar: "M10 10h28v30H10ZM16 5v10M32 5v10M10 20h28M16 27h2M23 27h2M30 27h2M16 33h2M23 33h2M30 33h2"
  };
  function progress(state) {
    const stats = state.statistics, model = BlinkMetrics.activity(stats.today, stats.week, stats.lifetime, state.preferences);
    model.gauges.forEach((g, i) => {
      const name = ["minutes", "days", "resets"][i], unit = ["min", "days", "resets"][i];
      $("gauge-" + name).style.strokeDashoffset = String(100 * (1 - g.progress));
      text("goal-" + name, `${fmt(g.current, i === 0 ? 1 : 0)} ${unit}`);
      text(["time-goal-note", "day-goal-note", "reset-goal-note"][i], `Goal ${fmt(g.goal)} ${unit}${i === 1 ? " in seven" : ""}`);
      $("today-goal-" + name).style.strokeDashoffset = String(100 * (1 - g.progress));
      text("today-value-" + name, `${fmt(g.current, i === 0 ? 1 : 0)} / ${fmt(g.goal)} ${unit}`);
      $(name + "-gauge").setAttribute("aria-label", `${fmt(g.current, i === 0 ? 1 : 0)} of ${fmt(g.goal)} ${unit}, personal observation goal`);
    });
    const earned = model.achievements.filter(a => a.earned).length;
    const next = model.achievements.filter(a => !a.earned).sort((a, b) => b.progress - a.progress)[0];
    text("next-milestone", next ? `${next.name}: ${fmt(Math.floor(next.progress * 100), 0, "% recorded")}` : "All milestones earned");
    text("earned-count", `${earned} of ${model.achievements.length} earned`);
    text("goals-summary", `${fmt(stats.today?.resets ?? 0)} resets today`);
    text("today-achievement", earned ? `${earned} milestones earned` : "View progress");
    const key = model.achievements.map(a => `${a.earned}-${Math.floor(a.progress * 100)}`).join("/");
    if (key === achievementKey) return; achievementKey = key;
    const fragment = document.createDocumentFragment();
    model.achievements.forEach(a => {
      const card = document.createElement("article"); card.className = `achievement${a.earned ? " earned" : ""}`;
      const drawing = svg("svg", { viewBox: "0 0 48 48", "aria-hidden": "true" }); drawing.append(svg("path", { d: medal[a.glyph] }));
      const title = document.createElement("h3"), detail = document.createElement("p"), track = document.createElement("div"), fill = document.createElement("span");
      title.textContent = a.name; detail.textContent = a.earned ? "Earned" : `${fmt(a.current, a.unit === "min" ? 1 : 0)} of ${fmt(a.target)} ${a.unit}`;
      track.className = "achievement-track house-rail"; fill.style.transform = `scaleX(${a.progress})`; track.append(fill);
      card.title = a.detail; card.setAttribute("aria-label", `${a.name}. ${a.detail}. ${a.earned ? "Earned" : detail.textContent}`);
      card.append(drawing, title, detail, track); fragment.append(card);
    });
    $("achievement-grid").replaceChildren(fragment);
  }
  function history(week = [], baseline) {
    const key = JSON.stringify([week, baseline]); if (key === historyKey) return; historyKey = key;
    const maximum = Math.max(1, finite(baseline) ? baseline : 0, ...week.map(d => finite(d.blinkRate) ? d.blinkRate : 0)) * 1.1;
    const fragment = document.createDocumentFragment(), descriptions = [];
    if ($("week-days").childElementCount !== Math.min(7, week.length)) $("week-days").replaceChildren();
    if (finite(baseline)) fragment.append(svg("path", { d: `M24 ${102 - baseline / maximum * 88}H616`, class: "week-baseline" }));
    let previousPoint = null;
    week.slice(-7).forEach((day, i) => {
      const x = 46 + i * 91.3, valid = finite(day.blinkRate), y = valid ? 102 - day.blinkRate / maximum * 88 : 102;
      if (valid) fragment.append(svg("path", { d: `M${x} 102V${y}`, class: `week-stem${i === 6 ? " week-today" : ""}` }));
      else fragment.append(svg("circle", { cx: x, cy: 100, r: 3, class: "week-missing" }));
      if (valid) {
        if (previousPoint) fragment.append(svg("path", { d: `M${previousPoint[0]} ${previousPoint[1]}L${x} ${y}`, class: "week-connection" }));
        const point = svg("circle", { cx:x,cy:y,r:3.2,class:i === 6 ? "week-point week-today" : "week-point" });
        const title = svg("title"); title.textContent = `${day.day}: ${fmt(day.blinkRate,1)} blinks per tracked minute`; point.append(title); fragment.append(point); previousPoint = [x,y];
      } else previousPoint = null;
      const date = new Date(`${day.day}T12:00:00`);
      let button = $("week-days").children[i];
      if (!button) {
        button = document.createElement("button");
        button.addEventListener("click", () => {
          historySelection = button.dataset.day; text("baseline-detail", button.dataset.description);
          $("week-days").querySelectorAll("button").forEach(b => b.setAttribute("aria-pressed", String(b === button)));
        });
        $("week-days").append(button);
      }
      button.textContent = Number.isFinite(date.getTime()) ? new Intl.DateTimeFormat(undefined, { weekday: "short" }).format(date) : "Day";
      const description = `${day.day}: ${valid ? fmt(day.blinkRate, 1) + " / min" : "No rate"}, ${fmt((day.trackedSeconds ?? 0) / 60, 1)} min observed`;
      button.dataset.day = day.day; button.dataset.description = description;
      button.setAttribute("aria-label", description); button.setAttribute("aria-pressed", String(historySelection ? historySelection === day.day : i === week.length - 1));
      descriptions.push(description);
    });
    $("week-chart").replaceChildren(fragment);
    $("week-chart").setAttribute("aria-label", descriptions.join(". "));
    text("baseline-detail", [...$("week-days").children].find(b => b.dataset.day === historySelection)?.dataset.description ?? (finite(baseline) ? `${fmt(baseline, 1)} / min personal baseline, prior six days.` : "Your baseline needs five tracked minutes in prior days."));
  }
  function exerciseView(state) {
    const e = state.exercise ?? { phase: "idle", step: "blink", remaining: 10, progress: 0 }, phase = e.phase;
    document.body.dataset.exercise = phase; document.body.dataset.practiceRoutine = e.routine ?? "reset";
    $("mirror-panel").hidden = e.routine !== "blink";
    if (e.routine !== "blink" || phase === "idle") stopReplay();
    $("practice-ready").hidden = phase !== "idle"; $("practice-session").hidden = phase === "idle";
    const running = phase === "running", paused = phase === "paused", done = phase === "completed", look = e.step === "look";
    $("blink-scene").toggleAttribute("hidden", look); $("look-scene").toggleAttribute("hidden", !look);
    text("exercise-kind", e.routine === "blink" ? "Blink mirror" : e.routine === "look" ? "Look away" : "Full reset");
    text("exercise-state", paused ? "Paused" : done ? "Complete" : look ? "Look away" : "Blink play");
    text("exercise-heading", done ? e.routine === "blink" ? "Your blink, reflected" : "A moment taken" : paused ? "Reset paused" : look ? "Look beyond the screen" : "Blink naturally");
    text("exercise-instruction", done ? e.routine === "blink" ? "Captured locally, ready to replay." : "Return at your own pace." : paused ? "Resume when you are ready." : look ? "Choose a distant real object." : "Let the drawing follow your blinks.");
    text("exercise-remaining", done ? "Done" : fmt(Math.ceil(finite(e.remaining) ? e.remaining : 0)));
    document.querySelector(".exercise-clock .muted").hidden = done;
    const progress = finite(e.progress) ? Math.max(0, Math.min(1, e.progress)) : 0;
    $("exercise-progress").style.transform = `scaleX(${progress})`; document.querySelector(".exercise-progress").setAttribute("aria-valuenow", String(Math.round(progress * 100)));
    const feedback = BlinkMetrics.freshEyes(state);
    if (running && lastExercise !== "running" && lastExercise !== "paused") practiceBlinks = state.statistics.lifetime?.blinks ?? 0;
    text("practice-blinks", feedback ? fmt(Math.max(0, (state.statistics.lifetime?.blinks ?? 0) - practiceBlinks)) : "Unavailable");
    ["left", "right"].forEach(side => text("practice-" + side, feedback ? fmt(state[side] * 100, 0, "% ref") : "Unavailable"));
    text("exercise-feedback", done ? "Saved to today’s activity." : look ? "Timer guidance. You can look away." : feedback ? "Live eyelid feedback" : "Camera feedback off. The guide still works.");
    if (running && !look) $("practice-lid").setAttribute("d", BlinkMetrics.aperture(feedback ? (state.left + state.right) / 2 : 1, 300, 85, 230) ?? "");
    $("exercise-pause").hidden = !running; $("exercise-resume").hidden = !paused;
    $("exercise-end").textContent = done ? "Back to practice" : "End reset";
    if (e.routine === "blink") mirrorView(state);
    if (phase !== lastExercise) {
      if (phase === "running" && lastExercise !== "paused") selectTab(1);
      if (paused) $("exercise-resume").focus();
      if (done) $("exercise-end").focus();
      lastExercise = phase;
    }
  }
  function mirrorView(state) {
    const mirror = state.mirror ?? {phase:"idle",clip:[],blinks:0,observedSeconds:0}, trace = BlinkMetrics.replay(mirror.clip);
    const active = BlinkMetrics.freshEyes(state);
    if ($("mirror-trace-left").getAttribute("d") !== trace.left) $("mirror-trace-left").setAttribute("d",trace.left);
    if ($("mirror-trace-right").getAttribute("d") !== trace.right) $("mirror-trace-right").setAttribute("d",trace.right);
    const recording = mirror.phase === "running", cancelled = mirror.phase === "cancelled";
    if (recording || state.reducedMotion || !trace.left) stopReplay();
    $("mirror-replay").textContent = state.reducedMotion ? "View trace" : "Replay blink";
    $("mirror-replay").disabled = recording || !trace.left || !(mirror.blinks > 0);
    text("mirror-totals",`${fmt(mirror.blinks ?? 0)} blinks, ${fmt(mirror.observedSeconds ?? 0,1)}s observed`);
    if (replayFrame === null) {
      text("mirror-source",recording ? active ? "Live capture" : "Waiting for tracking" : mirror.phase === "paused" ? "Capture paused" : cancelled ? "Capture ended" : "Captured blink");
      const last = Array.isArray(mirror.clip) ? mirror.clip[mirror.clip.length-1] : null;
      mirrorEyes(recording ? active ? state.left : null : last?.left,recording ? active ? state.right : null : last?.right);
    }
    text("mirror-description",cancelled ? "The person left view or tracking changed. Start a new mirror to capture again." : recording ? active ? "Blink naturally. Replay becomes available when capture ends or pauses." : "Waiting for visible, calibrated eyes. Missing time is not counted." : trace.left ? `Latest detected blink, ${fmt(trace.duration,2)}s of recorded movement. Left violet, right teal.` : "No blink captured. Start again when both eyes are visible.");
    $("mirror-eyes").setAttribute("aria-label",replayFrame !== null ? "Playback of recorded eyelid openings" : recording && active ? "Live measured eyelid openings" : "Captured eyelid openings");
  }
  function setupView(state) {
    if (studio !== "setup") return;
    const model = BlinkMetrics.setup(state), g = state.geometry ?? {}, box = g.box;
    text("setup-summary",model.ready ? "Ready for observation" : "Adjust the conditions below");
    const fragment = document.createDocumentFragment();
    for (const check of model.checks) {
      const row = document.createElement("div"); row.className = "setup-check"; row.dataset.ready = String(check.ok);
      const mark = svg("svg",{viewBox:"0 0 24 24","aria-hidden":"true"});
      mark.append(svg("circle",{cx:12,cy:12,r:9}));
      mark.append(svg("path",{d:check.ok ? "m7.5 12 3 3 6-6" : "M9 12h6"}));
      const copy = document.createElement("div"), name = document.createElement("span"), detail = document.createElement("p");
      name.textContent = check.name; detail.textContent = check.detail; copy.append(name,detail); row.append(mark,copy); fragment.append(row);
    }
    $("setup-checks").replaceChildren(fragment);
    const framed = model.visible && Array.isArray(box) && box.length===4 && box.every(finite) && box[2]>0 && box[3]>0 && box.every(v=>v>=0 && v<=1);
    $("setup-face").toggleAttribute("hidden",!framed);
    if (framed) {
      for (const [key,value] of Object.entries({x:box[0]*320,y:(1-box[1]-box[3])*240,width:box[2]*320,height:box[3]*240,rx:8})) $("setup-face").setAttribute(key,value);
    }
    for (const side of ["left","right"]) {
      const points = g[side];
      const d = framed && model.checks[2].ok && Array.isArray(points) ? points.map(([x,y],i)=>`${i ? "L" : "M"}${(box[0]+x*box[2])*320} ${(1-box[1]-y*box[3])*240}`).join("")+"Z" : "";
      $("setup-"+side+"-eye").setAttribute("d",d);
    }
    text("setup-sample",model.visible ? `${fmt(g.width)} × ${fmt(g.height)} px face crop` : state.detail ?? "Waiting for a camera sample");
    $("setup-calibrate").disabled = !model.visible;
    $("setup-allow").hidden = state.phase !== "cameraDenied";
    $("setup-retry").hidden = !["cameraMissing","cameraError","delayed"].includes(state.phase);
  }
  function coverageView(coverage) {
    const segments = coverage?.segments ?? [], span = 300, fragment = document.createDocumentFragment();
    const names = {tracking:"Eyes observed",eyesClosed:"Eye closure",calibrating:"Calibrating",noFace:"Face not visible",multipleFaces:"Multiple faces",lowQuality:"Camera angle",delayed:"Missing or delayed",paused:"Camera paused",cameraDenied:"Camera access blocked",cameraMissing:"Camera unavailable",cameraError:"Camera error",starting:"Starting camera"};
    const interruptions = [];
    for (const segment of segments) {
      if (![segment.start,segment.end].every(finite) || segment.end<=segment.start || segment.start<0 || segment.end>span) continue;
      const observed = ["tracking","eyesClosed"].includes(segment.phase), calibrating = segment.phase === "calibrating";
      const rect = svg("rect",{x:segment.start/span*640,y:5,width:(segment.end-segment.start)/span*640,height:24,class:observed ? "coverage-observed" : calibrating ? "coverage-calibrating" : segment.phase === "delayed" ? "coverage-unknown" : "coverage-interrupted"});
      const title = svg("title"); title.textContent = `${names[segment.phase] ?? "Unknown"}, ${fmt(segment.end-segment.start,1)}s`; rect.append(title); fragment.append(rect);
      if (!observed && !calibrating) interruptions.push(segment);
    }
    $("coverage-segments").replaceChildren(fragment);
    text("coverage-total",`${fmt(coverage?.observedSeconds ?? 0,1)}s valid exposure`);
    text("coverage-summary",segments.length ? "Teal observed, violet calibration, stripes missing" : "Waiting for observations");
    $("coverage-empty").hidden = segments.length>0;
    const events = document.createDocumentFragment();
    for (const segment of interruptions.slice(-4).reverse()) {
      const row = document.createElement("div"), name = document.createElement("dt"), duration = document.createElement("dd");
      name.textContent = names[segment.phase] ?? "Unknown"; duration.textContent = `${fmt(segment.end-segment.start,1)}s, ${fmt(span-segment.end)}s ago`;
      row.append(name,duration); events.append(row);
    }
    $("coverage-events").replaceChildren(events);
    $("coverage-chart").setAttribute("aria-label",`Last five minutes of camera states. ${fmt(coverage?.observedSeconds ?? 0,1)} seconds valid calibrated exposure. ${interruptions.length} interruptions. Unpainted time has no history. Recent interruptions are listed below; stripes mean missing or delayed data.`);
  }
  function scan(side, points, data, active) {
    const projection = active ? BlinkMetrics.contour(points, data.width, data.height) : null;
    for (const [metric, digits, suffix] of [["span",1," px"],["height",1," px"],["area",1," px²"],["tilt",1,"°"]]) text(`${side}-${metric}`, projection ? fmt(projection[metric], digits, suffix) : "Unavailable");
    $(`${side}-wait`).hidden = projection !== null;
    text(`${side}-aperture`, projection ? fmt(data[`${side}Aperture`], 3) : "Waiting");
    text(`${side}-count`, projection ? projection.points.length : "Waiting");
    const dots = document.createDocumentFragment(), axes = document.createDocumentFragment();
    if (projection) {
      $(`${side}-outline`).setAttribute("d", projection.points.map((p, i) => `${i === 0 ? "M" : "L"}${p[0].toFixed(2)},${p[1].toFixed(2)}`).join(" ") + "Z");
      projection.points.forEach(([x, y], i) => {
        const dot = svg("circle", {cx:x,cy:y,r:1.65}), title = svg("title");
        title.textContent = `Landmark ${i+1}: ${fmt(points[i][0]*data.width,1)}, ${fmt(points[i][1]*data.height,1)} px in face coordinates`;
        dot.append(title); dots.append(dot);
      });
      projection.axes.forEach(([a, b]) => { const line = document.createElementNS(svgNS, "path"); line.setAttribute("d", `M${a[0]},${a[1]}L${b[0]},${b[1]}`); axes.append(line); });
    } else { $(`${side}-outline`).setAttribute("d", ""); }
    $(`${side}-points`).replaceChildren(dots); $(`${side}-axes`).replaceChildren(axes);
    $(`${side}-scan`).setAttribute("aria-label", projection ? `${side} eyelid, ${projection.points.length} landmarks, aperture ${fmt(data[`${side}Aperture`], 3)}` : `${side} eyelid landmarks unavailable`);
  }
  function liveView(state) {
    const active = BlinkMetrics.freshEyes(state);
    text("live-difference", active ? fmt(Math.abs(state.left - state.right) * 100, 1, "%") : "Waiting");
    text("live-daily-difference", fmt(state.statistics.today?.asymmetry, 1, "%"));
    text("live-age", active ? fmt(state.frameAgeMs, 0, "ms") : "Waiting");
    text("live-fps", active && state.fps > 0 ? fmt(state.fps, 1) : "Waiting");
    $("start-check").disabled = !active || (state.calibration ?? 0) < 1;
    if (studio !== "geometry") {
      const time = state.sampleTime;
      const traceNow = finite(time) ? time + (finite(state.frameAgeMs) ? Math.max(0, state.frameAgeMs) / 1000 : 0) : 0;
      const trace = BlinkMetrics.motion(state.motion ?? [], traceNow, motionSpan);
      const difference = studio === "difference";
      text("motion-title", difference ? "Left minus right opening" : "Opening over time");
      text("motion-reference-label", difference ? "Zero = equal relative opening" : "Dashed = 100% reference");
      document.querySelector(".motion-lane-labels").hidden = difference;
      document.querySelector(".motion-reference").setAttribute("d", difference ? "M12 84H628" : "M12 32H628M12 112H628");
      $("motion-left").setAttribute("d", difference ? trace.difference : trace.left); $("motion-right").setAttribute("d", difference ? "" : trace.right);
      $("motion-left-area").setAttribute("d", difference ? "" : trace.areas[0]); $("motion-right-area").setAttribute("d", difference ? "" : trace.areas[1]);
      const marks = document.createDocumentFragment();
      for (const event of trace.events) {
        const marker = svg("path", { d: `M${event.x} 165v5`, class: `trace-event event-${event.type}` });
        const title = svg("title"); title.textContent = event.type === "blink" ? "Bilateral blink" : `${event.type} closure`; marker.append(title); marks.append(marker);
      }
      $("motion-events").replaceChildren(marks);
      text("motion-start", `${motionSpan}s ago`);
      text("motion-coverage", `${fmt(trace.observed,1)}s observed`);
      text("motion-event-count", `${trace.events.filter(e=>e.type === "blink").length} blinks in view`);
      $("motion-chart").setAttribute("aria-label", ` ${difference ? "Left minus right opening, minus 100 to plus 100 percentage points, zero centered" : "Left and right opening in separate lanes"} over ${motionSpan} seconds. ${difference ? "Above zero means the left is relatively more open; below zero means the right is relatively more open." : "Dashed lines mark 100 percent reference; display caps at 150 percent."} Gaps have no measurement. ${fmt(trace.observed,1)} seconds observed. ${trace.events.length} closure events.`);
    }
    const check = state.eyeCheck ?? { phase: "idle" }, running = check.phase === "running", done = check.phase === "completed";
    $("review-check").hidden = !["completed", "cancelled"].includes(check.phase);
    $("check-session").dataset.phase = check.phase;
    $("check-session").hidden = check.phase === "idle"; $("start-check").hidden = running; $("cancel-check").hidden = !running;
    text("check-status", running ? "Observing both eyes" : done ? "Observation complete" : "Observation ended");
    text("check-remaining", running ? `${fmt(Math.ceil(check.remaining ?? 0))}s remaining` : "");
    $("check-progress").style.transform = `scaleX(${finite(check.progress) ? Math.max(0, Math.min(1, check.progress)) : 0})`;
    $("check-rail").setAttribute("aria-valuenow", String(Math.round((check.progress ?? 0) * 100)));
    text("check-left", finite(check.left) ? fmt(check.left * 100, 1, "% ref") : "Collecting");
    text("check-right", finite(check.right) ? fmt(check.right * 100, 1, "% ref") : "Collecting");
    text("check-left-closures", fmt(check.leftClosures)); text("check-right-closures", fmt(check.rightClosures));
    text("check-exposure", fmt(check.observedSeconds, 1, "s")); text("check-blinks", fmt(check.blinks)); text("check-difference", fmt(check.difference, 1, "%"));
    if (check.phase !== lastCheck) {
      if (running) $("cancel-check").focus();
      if (["completed", "cancelled"].includes(check.phase)) $("review-check").focus();
      lastCheck = check.phase;
    }
    text("check-description", running ? "Blink normally. Missing camera time stays unmeasured." : finite(check.difference) ? "Average opening difference during visible, calibrated open eye time. This result stays in memory." : "Not enough calibrated open eye time for a comparison. Try again when both eyes are visible.");
  }
  function geometry(state) {
    const g = state.geometry ?? {}, active = ["tracking", "eyesClosed", "calibrating"].includes(state.phase) && finite(state.frameAgeMs) && state.frameAgeMs <= 500;
    ["left", "right"].forEach(side => {
      scan(side, g[side], g, active);
      text(`${side}-openness`, active && state.phase !== "calibrating" ? fmt(state[side] * 100, 0, "% ref") : "Waiting");
    });
    text("sample-status", active ? `Sample ${fmt(state.frameAgeMs, 0)}ms old` : "Waiting for fresh landmarks");
    text("face-crop", active ? `${fmt(g.width)} × ${fmt(g.height)} px` : "Waiting");
    text("face-aspect", active && g.height > 0 ? fmt(g.width / g.height, 3) : "Waiting");
    text("vision-confidence", active ? fmt(g.confidence, 2) : "Waiting");
    const left = active ? BlinkMetrics.contour(g.left, g.width, g.height) : null, right = active ? BlinkMetrics.contour(g.right, g.width, g.height) : null;
    text("eye-spacing", left && right ? `Contour center separation ${fmt(Math.hypot(left.center[0]-right.center[0],left.center[1]-right.center[1]),1)} px. Pixel geometry changes with camera distance and angle.` : "Geometry waits for fresh landmarks.");
    text("eye-difference", fmt(state.statistics.today?.asymmetry, 1, "%")); text("closed-share", fmt(state.statistics.today?.closedPercent, 1, "%"));
    const close = 0.38 + 0.28 * (state.preferences.sensitivity ?? 0.5);
    text("threshold-equation", `${fmt(close * 100)}% / ${fmt((close + 0.16) * 100)}%`);
    text("processing-latency", active && finite(state.latencyMs) && state.latencyMs > 0 ? fmt(state.latencyMs, 0, "ms") : "Waiting");
    text("processing-p95", finite(state.p95Ms) && state.p95Ms > 0 ? fmt(state.p95Ms, 0, "ms") : "Waiting");
    text("processing-fps", active && finite(state.fps) && state.fps > 0 ? fmt(state.fps, 1) : "Waiting"); text("processing-drops", fmt(state.dropped ?? 0));
    text("reminder-state", reminderText(state));
    text("color-gamut", "sRGB");
  }
  function reminderText(state) {
    if (state.eyeCheck?.phase === "running") return "Reminders rest during the eye check.";
    if (["running", "paused"].includes(state.exercise?.phase)) return "Reminders rest during the reset.";
    if (!state.preferences.remindersEnabled) return "Screen reminders off";
    if (state.fading) return "Reminder active. Close your eyes to clear.";
    if (state.reminderState === "waitingForBlink") return "Blink to start the next reminder interval.";
    if (["tracking", "eyesClosed"].includes(state.phase)) return `Next cue in ${fmt(Math.max(0, state.preferences.reminderSeconds - state.openSeconds), 1, "s")}`;
    return "Reminders wait for fresh eye data.";
  }
  window.blinkmore = { selectTab, showSetup, update(state) {
    if (!state?.preferences || !state.statistics) return;
    current = state; const stats = state.statistics, today = stats.today ?? {}, prefs = state.preferences;
    document.documentElement.classList.toggle("dark", state.actualTheme === "dark");
    document.documentElement.classList.toggle("reduce-motion", Boolean(state.reducedMotion));
    $("tracking-status").dataset.phase = state.phase;
    text("attention-banner", state.attention || ""); $("attention-banner").hidden = !state.attention;
    $("theme-cycle").setAttribute("aria-label", state.actualTheme === "dark" ? "Switch to light appearance" : "Switch to dark appearance");
    const scene = state.scene ?? {}, freshScene = finite(scene.ageMs) && scene.ageMs >= 0 && scene.ageMs <= 1500;
    text("scene-summary", freshScene ? `${scene.count} measurable ${scene.count === 1 ? "face" : "faces"} in view${scene.count > 1 ? ", observation paused" : ""}` : "Scene check pending");
    const preparing = ["starting", "calibrating"].includes(state.phase), calibrated = state.phase === "calibrating";
    const rail = $("tracking-rail"); rail.hidden = !preparing; rail.dataset.determinate = String(calibrated);
    rail.setAttribute("aria-label", calibrated ? "Eye calibration" : "Starting camera");
    if (calibrated) rail.setAttribute("aria-valuenow", String(Math.round(Math.max(0, Math.min(1, state.calibration ?? 0)) * 100)));
    else rail.removeAttribute("aria-valuenow");
    rail.firstElementChild.style.transform = calibrated ? `scaleX(${Math.max(0, Math.min(1, state.calibration ?? 0))})` : "";
    text("tracking-title", state.title ?? "Starting camera");
    text("tracking-detail", state.phase === "calibrating" ? `${fmt((state.calibration ?? 0) * 100)}% calibrated` : state.phase === "tracking" ? "" : state.detail ?? "");
    $("tracking-detail").title = state.detail ?? "";
    $("pause-button").querySelector("span").textContent = state.phase === "paused" ? "Resume" : "Pause";
    const unavailable = ["starting", "paused", "cameraDenied", "cameraMissing", "cameraError"].includes(state.phase);
    $("calibrate-button").disabled = unavailable; $("settings-calibrate").disabled = unavailable;
    $("camera-settings").hidden = state.phase !== "cameraDenied"; $("retry-button").hidden = !["cameraError", "cameraMissing", "delayed"].includes(state.phase);
    $("start-reset").disabled = state.phase === "paused";
    document.querySelectorAll("button[data-routine]").forEach(button => button.disabled = state.phase === "paused");
    text("recent-rate", fmt(stats.recentRate, 1)); $("recent-rate").classList.toggle("empty", !finite(stats.recentRate));
    text("recent-rate-detail", `${fmt(stats.recentSeconds ?? 0)}s observed`);
    text("relative-rate-detail", finite(stats.baselineRate) ? `Usual ${fmt(stats.baselineRate, 1)} / min` : "Building your baseline");
    text("activity-exposure", `${fmt((today.trackedSeconds ?? 0) / 60, 1)} min observed today`);
    text("daily-rate", fmt(today.blinkRate, 1, " / min"));
    text("relative-rate", finite(stats.relativePercent) ? `${stats.relativePercent > 0 ? "+" : ""}${fmt(stats.relativePercent, 0, "%")}` : "Collecting");
    text("type-bilateral", fmt(today.blinks ?? 0)); text("type-left", fmt(today.leftClosures ?? 0)); text("type-right", fmt(today.rightClosures ?? 0)); text("type-long", fmt(today.longClosures)); text("resets-today", fmt(today.resets));
    const due = Boolean(state.exercise?.due) && !state.fading;
    text("invitation-title", due ? "Ready for a reset?" : "A moment for your eyes");
    text("invitation-detail", due ? "A quiet break is ready." : "Blink, then look away.");
    $("exercise-later").hidden = !due; $("exercise-skip").hidden = !due;
    if (selected === 0) { live(state); rhythm(stats.recentBins); }
    blinkPulse(state); progress(state); if (selected === 2) { history(stats.week, stats.baselineRate); coverageView(state.coverage); } exerciseView(state);
    const cameras = state.cameras ?? [], key = JSON.stringify(cameras);
    if (key !== cameraKey) {
      cameraKey = key; const fragment = document.createDocumentFragment();
      [{ id: "", name: "Automatic" }, ...cameras].forEach(camera => { const option = document.createElement("option"); option.value = camera.id; option.textContent = camera.name; fragment.append(option); });
      $("camera-choice").replaceChildren(fragment);
    }
    document.querySelectorAll("[data-preference]").forEach(input => {
      const key = input.dataset.preference, value = prefs[key];
      if (input.type === "checkbox") input.checked = Boolean(value);
      else if (document.activeElement !== input) input.value = value ?? "";
      if (input.type === "range" && document.activeElement !== input) text(`label-${key}`, preferenceLabel(key, Number(input.value)));
    });
    text("footer-notice", state.notice || stats.warning || "");
    if (selected === 4) {
      if (studio === "setup") setupView(state);
      else { geometry(state); liveView(state); }
    }
  } };
  send({ action: "ready" });
})();
