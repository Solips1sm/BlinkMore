"use strict";
(() => {
  const $ = id => document.getElementById(id);
  const svgNS = "http://www.w3.org/2000/svg";
  const finite = n => typeof n === "number" && Number.isFinite(n);
  const fmt = (n, digits = 0, suffix = "") => finite(n) ? new Intl.NumberFormat(undefined, { maximumFractionDigits: digits, minimumFractionDigits: digits }).format(n) + suffix : "Collecting";
  const text = (id, value) => { const el = $(id); if (el && el.textContent !== String(value)) el.textContent = String(value); };
  const send = message => window.webkit?.messageHandlers?.blinkmore?.postMessage(message);
  const tabs = ["activity", "geometry", "settings-page"];
  let current = null, selected = 0, historyKey = "", achievementKey = "", cameraKey = "";
  function selectTab(index, focus = false) {
    if (!Number.isInteger(index) || index < 0 || index > 2) return;
    selected = index;
    document.querySelectorAll("[data-tab]").forEach((button, i) => {
      button.setAttribute("aria-selected", String(i === index)); button.tabIndex = i === index ? 0 : -1;
      $(tabs[i]).hidden = i !== index;
      if (focus && i === index) button.focus();
    });
    if (current && index === 1) geometry(current);
  }
  document.querySelectorAll("[data-tab]").forEach((button, index) => {
    button.addEventListener("click", () => selectTab(index));
    button.addEventListener("keydown", event => {
      let next;
      if (event.key === "ArrowRight") next = (index + 1) % 3;
      else if (event.key === "ArrowLeft") next = (index + 2) % 3;
      else if (event.key === "Home") next = 0;
      else if (event.key === "End") next = 2;
      else return;
      event.preventDefault(); selectTab(next, true);
    });
  });
  document.querySelectorAll("[data-action]").forEach(button => button.addEventListener("click", () => send({ action: button.dataset.action })));
  document.querySelectorAll("[data-go-settings]").forEach(button => button.addEventListener("click", () => selectTab(2)));
  $("theme-cycle").addEventListener("click", () => {
    const choices = ["system", "light", "dark"], value = choices[(choices.indexOf(current?.preferences?.theme ?? "system") + 1) % 3];
    send({ action: "set", key: "theme", value });
  });
  const preferenceLabel = (key, n) => ["intensity", "sensitivity"].includes(key) ? fmt(n * 100, 0, "%") : ["reminderSeconds", "fadeSeconds"].includes(key) ? fmt(n, key === "fadeSeconds" ? 1 : 0, "s") : fmt(n);
  document.querySelectorAll("[data-preference]").forEach(input => {
    input.addEventListener("input", () => { if (input.type === "range") text(`label-${input.dataset.preference}`, preferenceLabel(input.dataset.preference, Number(input.value))); });
    input.addEventListener("change", () => {
      if (input.type === "checkbox") {
        const frame = input.closest(".anistratenco-checkbox-frame");
        frame.dataset.activation = frame.dataset.activation === "first" ? "repeat" : "first";
      }
      send({ action: "set", key: input.dataset.preference, value: input.type === "checkbox" ? input.checked : input.type === "range" ? Number(input.value) : input.value });
    });
  });
  function rings(state) {
    const stats = state.statistics, model = BlinkMetrics.activity(stats.today, stats.week, stats.lifetime, state.preferences);
    const labels = ["blinks", "minutes", "days"];
    const accessible = [];
    model.rings.forEach((ring, i) => {
      const key = labels[i], circle = $(`ring-${key}`), radius = Number(circle.getAttribute("r")), circumference = Math.PI * 2 * radius;
      const offset = String(circumference * (1 - ring.progress));
      if (circle.style.strokeDashoffset !== offset) { circle.style.strokeDasharray = String(circumference); circle.style.strokeDashoffset = offset; }
      text(`goal-${key}`, `${fmt(ring.current, i === 1 ? 1 : 0)} / ${fmt(ring.goal)}`);
      text(`percent-${key}`, ring.goal === null ? "No goal" : fmt(ring.current / ring.goal * 100, 0, "%"));
      accessible.push(`${key}: ${fmt(ring.current, i === 1 ? 1 : 0)} of ${fmt(ring.goal)}`);
    });
    $("activity-rings").setAttribute("aria-label", accessible.join(", "));
    text("goals-complete", `${model.rings.filter(r => r.goal !== null && r.progress >= 1).length} of 3 goals`);
    text("ring-center-value", fmt(stats.today?.blinks ?? 0));
    const key = model.achievements.map(a => `${a.earned}-${Math.floor(a.progress * 100)}`).join("/");
    if (key !== achievementKey) {
      achievementKey = key;
      const fragment = document.createDocumentFragment();
      model.achievements.forEach(a => {
        const card = document.createElement("div"); card.className = `achievement${a.earned ? " earned" : ""}`;
        card.setAttribute("aria-label", `${a.name}. ${a.detail}. ${a.earned ? "Earned" : fmt(a.progress * 100, 0, "% complete")}`);
        const medal = document.createElement("span"); medal.className = "achievement-medal";
        const svg = document.createElementNS(svgNS, "svg"), use = document.createElementNS(svgNS, "use"); use.setAttribute("href", `#${a.glyph}`); svg.setAttribute("aria-hidden", "true"); svg.append(use); medal.append(svg);
        const words = document.createElement("div"), title = document.createElement("strong"), detail = document.createElement("p");
        title.textContent = a.name; detail.textContent = a.earned ? "Earned" : fmt(a.progress * 100, 0, "% complete"); words.append(title, detail); card.append(medal, words); card.title = a.detail; fragment.append(card);
      });
      $("achievement-grid").replaceChildren(fragment);
    }
  }
  function history(week = []) {
    const key = JSON.stringify(week.map(d => [d.day, finite(d.blinkRate) ? d.blinkRate.toFixed(1) : null]));
    if (key === historyKey) return; historyKey = key;
    const maximum = Math.max(1, ...week.map(d => finite(d.blinkRate) ? d.blinkRate : 0)), fragment = document.createDocumentFragment(), descriptions = [];
    week.slice(-7).forEach((day, i) => {
      const column = document.createElement("div"), rate = document.createElement("strong"), bar = document.createElement("i"), label = document.createElement("span");
      const valid = finite(day.blinkRate); column.className = `day-column${i === week.length - 1 ? " today" : ""}${valid ? "" : " empty"}`;
      rate.textContent = valid ? fmt(day.blinkRate, 1) : "No data"; bar.style.height = `${valid ? Math.max(3, day.blinkRate / maximum * 63) : 3}px`;
      const date = new Date(`${day.day}T12:00:00`); label.textContent = Number.isFinite(date.getTime()) ? new Intl.DateTimeFormat(undefined, { weekday: "short" }).format(date) : "";
      const description = `${day.day}: ${valid ? fmt(day.blinkRate, 1) + " per tracked minute" : "no data"}`;
      column.title = description; descriptions.push(description); column.append(rate, bar, label); fragment.append(column);
    });
    $("week-chart").replaceChildren(fragment); $("week-chart").setAttribute("aria-label", descriptions.join(", "));
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
    text("color-gamut", matchMedia("(color-gamut: p3)").matches && CSS.supports("color", "color(display-p3 1 0 0)") ? "Display P3" : "sRGB");
  }
  function reminderText(state) {
    if (!state.preferences.remindersEnabled) return "Screen reminders off";
    if (state.fading) return "Reminder active. Close your eyes to clear.";
    if (state.reminderState === "waitingForBlink") return "Blink to start the next reminder interval.";
    if (["tracking", "eyesClosed"].includes(state.phase)) return `Next cue in ${fmt(Math.max(0, state.preferences.reminderSeconds - state.openSeconds), 1, "s")}`;
    return "Reminders wait for fresh eye data.";
  }
  window.blinkmore = { selectTab, update(state) {
    if (!state || !state.preferences || !state.statistics) return;
    current = state; const stats = state.statistics, today = stats.today ?? {}, prefs = state.preferences;
    document.documentElement.classList.toggle("dark", state.actualTheme === "dark");
    document.documentElement.classList.toggle("reduce-motion", Boolean(state.reducedMotion));
    text("today-date", new Intl.DateTimeFormat(undefined, { weekday: "long", month: "short", day: "numeric" }).format(new Date()));
    $("tracking-status").dataset.phase = state.phase;
    text("tracking-title", state.title ?? "Starting camera"); text("tracking-detail", state.phase === "calibrating" ? `${fmt((state.calibration ?? 0) * 100)}% calibrated. ${state.detail ?? ""}` : state.detail ?? "");
    $("tracking-detail").title = state.detail ?? "";
    $("pause-button").querySelector("span").textContent = state.phase === "paused" ? "Resume" : "Pause";
    const unavailable = ["starting", "paused", "cameraDenied", "cameraMissing", "cameraError"].includes(state.phase);
    $("calibrate-button").disabled = unavailable; $("settings-calibrate").disabled = unavailable;
    $("camera-settings").hidden = state.phase !== "cameraDenied"; $("retry-button").hidden = !["cameraError", "cameraMissing", "delayed"].includes(state.phase);
    rings(state); history(stats.week);
    text("recent-rate", fmt(stats.recentRate, 1)); text("recent-rate-detail", `${fmt(stats.recentSeconds ?? 0)}s tracked in the last 60s`);
    text("daily-rate", fmt(today.blinkRate, 1)); text("daily-rate-detail", `${fmt((today.trackedSeconds ?? 0) / 60, 1)} minutes tracked today`);
    text("relative-rate", finite(stats.relativePercent) ? `${stats.relativePercent > 0 ? "+" : ""}${fmt(stats.relativePercent, 0, "%")}` : "Collecting");
    text("relative-rate-detail", finite(stats.baselineRate) ? `${fmt(stats.baselineRate, 1)}/min personal baseline` : "Needs 5 tracked minutes in prior days");
    const active = ["tracking", "eyesClosed"].includes(state.phase);
    text("open-interval", active ? fmt(state.openSeconds, 1, "s") : "Waiting"); text("open-interval-detail", reminderText(state));
    ["recent-rate", "daily-rate", "relative-rate", "open-interval"].forEach(id => $(id).classList.toggle("empty", ["Waiting", "Collecting"].includes($(id).textContent)));
    text("baseline-detail", finite(stats.baselineRate) ? "Prior six days, weighted by tracked time. Personal comparison, not a health score." : "No personal baseline yet. Prior days need at least 5 tracked minutes combined.");
    text("type-bilateral", fmt(today.blinks ?? 0)); text("type-left", fmt(today.leftClosures ?? 0)); text("type-right", fmt(today.rightClosures ?? 0)); text("type-long", fmt(today.longClosures));
    text("activity-exposure", `${fmt(today.reminders ?? 0)} cues today, ${fmt((today.trackedSeconds ?? 0) / 60, 1)} minutes observed`);
    const cameras = state.cameras ?? [], key = JSON.stringify(cameras);
    if (key !== cameraKey) {
      cameraKey = key; const fragment = document.createDocumentFragment();
      [{ id: "", name: "Automatic" }, ...cameras].forEach(camera => { const option = document.createElement("option"); option.value = camera.id; option.textContent = camera.name; fragment.append(option); });
      $("camera-choice").replaceChildren(fragment);
    }
    document.querySelectorAll("[data-preference]").forEach(input => {
      const key = input.dataset.preference, v = prefs[key];
      if (input.type === "checkbox") input.checked = Boolean(v);
      else if (document.activeElement !== input) input.value = v ?? "";
      if (input.type === "range" && document.activeElement !== input) text(`label-${key}`, preferenceLabel(key, Number(input.value)));
    });
    text("footer-notice", state.notice || stats.warning || "On this Mac. No camera images saved.");
    if (selected === 1) geometry(state);
  } };
  send({ action: "ready" });
})();
