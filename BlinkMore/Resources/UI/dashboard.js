"use strict";
(() => {
  const $ = id => document.getElementById(id), svgNS = "http://www.w3.org/2000/svg";
  const finite = n => typeof n === "number" && Number.isFinite(n);
  const fmt = (n, digits = 0, suffix = "") => finite(n) ? new Intl.NumberFormat(undefined, { maximumFractionDigits: digits }).format(n) + suffix : "Collecting";
  const text = (id, value) => { const el = $(id); if (el && el.textContent !== String(value)) el.textContent = String(value); };
  const send = value => window.webkit?.messageHandlers?.blinkmore?.postMessage(value);
  const pages = ["activity", "practice", "history", "settings-page", "examine"], tabOrder = [0, 4, 1, 2, 3];
  let motionSamples = [], lastMotionTime = null;
  let current = null, selected = 0, historyKey = "", achievementKey = "", cameraKey = "", rhythmKey = "", lastBlinks = null, lastExercise = "idle", lastCheck = "idle", historySelection = null;
  function svg(name, attributes = {}) {
    const node = document.createElementNS(svgNS, name);
    Object.entries(attributes).forEach(([key, value]) => node.setAttribute(key, String(value))); return node;
  }
  function selectTab(index, focus = false) {
    if (!Number.isInteger(index) || index < 0 || index >= pages.length) return;
    if (selected === 1 && index !== 1 && ["running", "paused", "completed"].includes(current?.exercise?.phase)) send({ action: "exercise", command: "end" });
    if (selected === 4 && index !== 4) {
      if (current?.eyeCheck?.phase === "running") send({ action: "cancelCheck" });
      motionSamples = []; lastMotionTime = null;
    }
    if (selected !== index) document.querySelector("main").scrollTop = 0;
    window.scrollTo(0, 0);
    selected = index; document.body.dataset.page = String(index);
    document.querySelectorAll("[data-tab]").forEach(button => {
      const active = Number(button.dataset.tab) === index;
      button.setAttribute("aria-selected", String(active)); button.tabIndex = active ? 0 : -1;
      if (active && focus) button.focus();
    });
    pages.forEach((page, i) => $(page).hidden = i !== index);
    if (current && index === 0) { live(current); rhythm(current.statistics.recentBins); }
    if (current && index === 2) { progress(current); history(current.statistics.week, current.statistics.baselineRate); }
    if (current && index === 4) { geometry(current); liveView(current); }
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
  document.querySelectorAll("[data-routine]").forEach(button => button.addEventListener("click", () => send({ action: "exercise", command: "start", routine: button.dataset.routine })));
  document.querySelectorAll("[data-history]").forEach(button => button.addEventListener("click", () => selectTab(2)));
  document.querySelectorAll("[data-inspect]").forEach(button => button.addEventListener("click", () => { selectTab(4); $("measurement-details").open = true; if (current) geometry(current); }));
  $("measurement-details").addEventListener("toggle", () => { if (current && $("measurement-details").open) geometry(current); });
  $("review-check").addEventListener("click", () => $("check-session").scrollIntoView({ block: "nearest" }));
  $("theme-cycle").addEventListener("click", () => {
    const choices = ["system", "light", "dark"]; send({ action: "set", key: "theme", value: choices[(choices.indexOf(current?.preferences?.theme ?? "system") + 1) % 3] });
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
    const active = ["tracking", "eyesClosed"].includes(state.phase) && finite(state.frameAgeMs) && state.frameAgeMs <= 500;
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
    week.slice(-7).forEach((day, i) => {
      const x = 46 + i * 91.3, valid = finite(day.blinkRate), y = valid ? 102 - day.blinkRate / maximum * 88 : 102;
      if (valid) fragment.append(svg("path", { d: `M${x} 102V${y}`, class: `week-stem${i === 6 ? " week-today" : ""}` }));
      else fragment.append(svg("circle", { cx: x, cy: 100, r: 3, class: "week-missing" }));
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
    document.body.dataset.exercise = phase;
    $("practice-ready").hidden = phase !== "idle"; $("practice-session").hidden = phase === "idle";
    const running = phase === "running", paused = phase === "paused", done = phase === "completed", look = e.step === "look";
    $("blink-scene").toggleAttribute("hidden", look); $("look-scene").toggleAttribute("hidden", !look);
    text("exercise-kind", e.routine === "blink" ? "Blink play" : e.routine === "look" ? "Look away" : "Full reset");
    text("exercise-state", paused ? "Paused" : done ? "Complete" : look ? "Look away" : "Blink play");
    text("exercise-heading", done ? "A moment taken" : paused ? "Reset paused" : look ? "Look beyond the screen" : "Blink naturally");
    text("exercise-instruction", done ? "Return at your own pace." : paused ? "Resume when you are ready." : look ? "Choose a distant real object." : "Let the drawing follow your blinks.");
    text("exercise-remaining", done ? "Done" : fmt(Math.ceil(finite(e.remaining) ? e.remaining : 0)));
    document.querySelector(".exercise-clock .muted").hidden = done;
    const progress = finite(e.progress) ? Math.max(0, Math.min(1, e.progress)) : 0;
    $("exercise-progress").style.transform = `scaleX(${progress})`; document.querySelector(".exercise-progress").setAttribute("aria-valuenow", String(Math.round(progress * 100)));
    const feedback = ["tracking", "eyesClosed"].includes(state.phase) && finite(state.frameAgeMs) && state.frameAgeMs <= 500;
    text("exercise-feedback", done ? "Saved to today’s activity." : look ? "Timer guidance. You can look away." : feedback ? "Live eyelid feedback" : "Camera feedback off. The guide still works.");
    if (running && !look) $("practice-lid").setAttribute("d", BlinkMetrics.aperture(feedback ? (state.left + state.right) / 2 : 1, 300, 85, 230) ?? "");
    $("exercise-pause").hidden = !running; $("exercise-resume").hidden = !paused;
    $("exercise-end").textContent = done ? "Back to practice" : "End reset";
    if (phase !== lastExercise) {
      if (phase === "running" && lastExercise !== "paused") selectTab(1);
      if (paused) $("exercise-resume").focus();
      if (done) $("exercise-end").focus();
      lastExercise = phase;
    }
  }
  function scan(side, points, data, active) {
    const projection = active ? BlinkMetrics.contour(points, data.width, data.height) : null;
    $(`${side}-wait`).hidden = projection !== null;
    text(`${side}-aperture`, projection ? fmt(data[`${side}Aperture`], 3) : "Waiting");
    text(`${side}-count`, projection ? projection.points.length : "Waiting");
    const dots = document.createDocumentFragment(), axes = document.createDocumentFragment();
    if (projection) {
      $(`${side}-outline`).setAttribute("d", projection.points.map((p, i) => `${i === 0 ? "M" : "L"}${p[0].toFixed(2)},${p[1].toFixed(2)}`).join(" ") + "Z");
      projection.points.forEach(([x, y]) => { const dot = document.createElementNS(svgNS, "circle"); dot.setAttribute("cx", x); dot.setAttribute("cy", y); dot.setAttribute("r", 1.65); dots.append(dot); });
      projection.axes.forEach(([a, b]) => { const line = document.createElementNS(svgNS, "path"); line.setAttribute("d", `M${a[0]},${a[1]}L${b[0]},${b[1]}`); axes.append(line); });
    } else { $(`${side}-outline`).setAttribute("d", ""); }
    $(`${side}-points`).replaceChildren(dots); $(`${side}-axes`).replaceChildren(axes);
    $(`${side}-scan`).setAttribute("aria-label", projection ? `${side} eyelid, ${projection.points.length} landmarks, aperture ${fmt(data[`${side}Aperture`], 3)}` : `${side} eyelid landmarks unavailable`);
  }
  function liveView(state) {
    const active = ["tracking", "eyesClosed"].includes(state.phase) && finite(state.frameAgeMs) && state.frameAgeMs <= 500 && finite(state.left) && finite(state.right);
    text("live-difference", active ? fmt(Math.abs(state.left - state.right) * 100, 1, "%") : "Waiting");
    text("live-daily-difference", fmt(state.statistics.today?.asymmetry, 1, "%"));
    text("live-age", active ? fmt(state.frameAgeMs, 0, "ms") : "Waiting");
    text("live-fps", active && state.fps > 0 ? fmt(state.fps, 1) : "Waiting");
    $("start-check").disabled = !active || (state.calibration ?? 0) < 1;
    const time = state.sampleTime;
    if (finite(time) && time > 0 && time !== lastMotionTime) {
      if (lastMotionTime !== null && time < lastMotionTime) motionSamples = [];
      motionSamples.push({ t: time, left: active ? state.left : null, right: active ? state.right : null });
      motionSamples = motionSamples.filter(p => p.t >= time - 30).slice(-160); lastMotionTime = time;
    }
    const traceNow = finite(time) ? time + (finite(state.frameAgeMs) ? Math.max(0, state.frameAgeMs) / 1000 : 0) : 0;
    const trace = BlinkMetrics.motion(motionSamples, traceNow);
    $("motion-left").setAttribute("d", trace.left); $("motion-right").setAttribute("d", trace.right);
    const check = state.eyeCheck ?? { phase: "idle" }, running = check.phase === "running", done = check.phase === "completed";
    $("review-check").hidden = !["completed", "cancelled"].includes(check.phase);
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
  window.blinkmore = { selectTab, update(state) {
    if (!state?.preferences || !state.statistics) return;
    current = state; const stats = state.statistics, today = stats.today ?? {}, prefs = state.preferences;
    document.documentElement.classList.toggle("dark", state.actualTheme === "dark");
    document.documentElement.classList.toggle("reduce-motion", Boolean(state.reducedMotion));
    $("tracking-status").dataset.phase = state.phase;
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
    document.querySelectorAll("[data-routine]").forEach(button => button.disabled = state.phase === "paused");
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
    blinkPulse(state); progress(state); if (selected === 2) history(stats.week, stats.baselineRate); exerciseView(state);
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
    if (selected === 4) { geometry(state); liveView(state); }
  } };
  send({ action: "ready" });
})();
