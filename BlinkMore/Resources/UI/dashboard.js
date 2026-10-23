"use strict";
(() => {
  let current = null;
  let historyKey = "";
  let cameraKey = "";
  const $ = (id) => document.getElementById(id);
  const finite = (value, fallback = 0) => typeof value === "number" && Number.isFinite(value) ? value : fallback;
  const clamp = (value, min = 0, max = 1) => Math.min(max, Math.max(min, finite(value)));
  const text = (id, value) => { const el = $(id); const next = String(value); if (el.textContent !== next) el.textContent = next; };
  const send = (message) => window.webkit?.messageHandlers?.blinkmore?.postMessage(message);
  const minutes = (seconds) => { const total = Math.floor(finite(seconds) / 60); return total >= 60 ? `${Math.floor(total / 60)}h ${total % 60}m` : `${total}m`; };
  const percentage = (value) => value === null || value === undefined ? "Collecting" : `${finite(value).toFixed(1)}%`;
  const icon = (button, name) => button.querySelector("use")?.setAttribute("href", `#${name}`);

  function selectTab(name, focus = false) {
    document.querySelectorAll("[data-tab]").forEach((tab) => {
      const selected = tab.dataset.tab === name;
      tab.setAttribute("aria-selected", String(selected)); tab.tabIndex = selected ? 0 : -1;
      $(tab.dataset.tab).hidden = !selected;
      if (selected && focus) tab.focus();
    });
  }
  document.querySelectorAll("[data-tab]").forEach((tab) => {
    tab.addEventListener("click", () => selectTab(tab.dataset.tab));
    tab.addEventListener("keydown", (event) => {
      const tabs = [...document.querySelectorAll("[data-tab]")];
      let index = tabs.indexOf(tab);
      if (event.key === "ArrowRight") index = (index + 1) % tabs.length;
      else if (event.key === "ArrowLeft") index = (index + tabs.length - 1) % tabs.length;
      else if (event.key === "Home") index = 0;
      else if (event.key === "End") index = tabs.length - 1;
      else return;
      event.preventDefault(); selectTab(tabs[index].dataset.tab, true);
    });
  });
  document.addEventListener("keydown", (event) => {
    if (event.metaKey && event.key === ",") { event.preventDefault(); selectTab("settings", true); }
  });
  document.querySelectorAll("[data-action]").forEach((button) => button.addEventListener("click", () => send({ action: button.dataset.action })));
  document.querySelectorAll("[data-theme]").forEach((button) => button.addEventListener("click", () => send({ action: "set", key: "theme", value: button.dataset.theme })));
  $("theme-cycle").addEventListener("click", () => {
    const choices = ["system", "light", "dark"];
    const next = choices[(choices.indexOf(current?.preferences?.theme ?? "system") + 1) % choices.length];
    send({ action: "set", key: "theme", value: next });
  });

  const rangeLabels = {
    reminderSeconds: ["reminder-seconds-value", (v) => `${v} seconds`],
    fadeSeconds: ["fade-seconds-value", (v) => `${v.toFixed(1)} seconds`],
    intensity: ["intensity-value", (v) => `${Math.round(v * 100)}%`],
    sensitivity: ["sensitivity-value", (v) => `${Math.round(v * 100)}%`],
  };
  document.querySelectorAll("[data-preference]").forEach((input) => {
    let timer;
    const commit = () => {
      clearTimeout(timer);
      const value = input.type === "checkbox" ? input.checked : input.type === "range" ? Number(input.value) : input.value;
      send({ action: "set", key: input.dataset.preference, value });
    };
    input.addEventListener("change", commit);
    if (input.type === "range") input.addEventListener("input", () => {
      const [id, format] = rangeLabels[input.dataset.preference]; text(id, format(Number(input.value)));
      clearTimeout(timer); timer = setTimeout(commit, 70);
    });
  });

  function drawEye(side, openness, closed, active) {
    const height = active ? (closed ? 0.5 : 18 * clamp(openness)) : 5;
    const path = `M8 40 Q72 ${40 - height * 2} 136 40 Q72 ${40 + height * 2} 8 40 Z`;
    $(`${side}-eye`).setAttribute("d", path); $(`${side}-clip`).setAttribute("d", path);
    text(`${side}-value`, active ? closed ? "Closed" : `${Math.round(clamp(openness) * 100)}% open` : "Waiting");
  }

  function renderHistory(week) {
    const safe = Array.isArray(week) ? week.slice(-7) : [];
    const key = JSON.stringify(safe.map((day) => [day.day, day.blinks, Math.floor(finite(day.trackedSeconds) / 5), Math.round(finite(day.asymmetry))]));
    if (key === historyKey) return;
    historyKey = key;
    const any = safe.some((day) => finite(day.trackedSeconds) > 0);
    $("empty-history").hidden = any; $("week-chart").hidden = !any;
    const chart = document.createDocumentFragment();
    const rows = document.createDocumentFragment();
    const maximum = Math.max(1, ...safe.map((day) => finite(day.blinks)));
    safe.forEach((day, index) => {
      const date = new Date(`${day.day}T12:00:00`);
      const validDate = Number.isFinite(date.getTime());
      const short = validDate ? new Intl.DateTimeFormat(undefined, { weekday: "short" }).format(date) : String(day.day);
      const long = validDate ? new Intl.DateTimeFormat(undefined, { day: "numeric", month: "short" }).format(date) : String(day.day);
      const column = document.createElement("div"); column.className = `day-column${index === safe.length - 1 ? " today" : ""}`;
      column.setAttribute("aria-label", `${long}: ${finite(day.blinks)} blinks`);
      const count = document.createElement("strong"); count.textContent = String(finite(day.blinks));
      const bar = document.createElement("i"); bar.style.height = `${Math.max(2, finite(day.blinks) / maximum * 115)}px`; bar.setAttribute("aria-hidden", "true");
      const label = document.createElement("span"); label.textContent = short;
      column.append(count, bar, label); chart.append(column);
      const row = document.createElement("tr");
      [long, String(finite(day.blinks)), minutes(day.trackedSeconds), percentage(day.asymmetry)].forEach((value) => {
        const cell = document.createElement("td"); cell.textContent = value; row.append(cell);
      });
      rows.prepend(row);
    });
    $("week-chart").replaceChildren(chart); $("history-rows").replaceChildren(rows);
  }

  window.blinkmore = {
    update(state) {
      if (!state || typeof state !== "object" || !state.preferences || !state.statistics) return;
      current = state;
      const preferences = state.preferences;
      const stats = state.statistics.today ?? {};
      document.documentElement.classList.toggle("dark", state.actualTheme === "dark");
      $("tracking-card").dataset.phase = String(state.phase);
      text("tracking-title", state.title ?? "Starting camera"); text("tracking-detail", state.detail ?? "");
      text("today-date", new Intl.DateTimeFormat(undefined, { weekday: "long", day: "numeric", month: "long" }).format(new Date()));
      const paused = state.phase === "paused";
      const active = ["tracking", "eyesClosed"].includes(state.phase);
      const unavailable = ["paused", "cameraDenied", "cameraMissing", "cameraError", "starting"].includes(state.phase);
      $("calibrate-button").disabled = unavailable;
      $("camera-settings").hidden = state.phase !== "cameraDenied";
      $("retry-button").hidden = !["cameraMissing", "cameraError", "delayed"].includes(state.phase);
      $("pause-button").querySelector("span").textContent = paused ? "Resume monitoring" : "Pause 5 minutes";
      icon($("pause-button"), paused ? "play" : "pause");
      $("calibration-track").hidden = state.phase !== "calibrating";
      $("calibration-progress").value = clamp(state.calibration);
      text("calibration-label", `${Math.round(clamp(state.calibration) * 100)}% calibrated`);
      const mask = finite(state.closedMask);
      drawEye("left", state.left, Boolean(mask & 1), active);
      drawEye("right", state.right, Boolean(mask & 2), active);
      let progress = 0;
      if (state.phase === "calibrating") {
        text("reminder-value", `${Math.round(clamp(state.calibration) * 100)}%`); text("reminder-caption", "calibrating"); progress = clamp(state.calibration);
      } else if (state.fading) {
        text("reminder-value", "Blink"); text("reminder-caption", "a gentle reset"); progress = 1;
      } else if (active && preferences.remindersEnabled) {
        text("reminder-value", `${Math.max(0, finite(preferences.reminderSeconds) - finite(state.openSeconds)).toFixed(1)}s`);
        text("reminder-caption", "until reminder"); progress = clamp(finite(state.openSeconds) / Math.max(3, finite(preferences.reminderSeconds)));
      } else {
        text("reminder-value", paused ? "Paused" : !preferences.remindersEnabled ? "Off" : "Waiting");
        text("reminder-caption", paused ? "camera is off" : !preferences.remindersEnabled ? "reminders" : "for your eyes");
      }
      $("dial-progress").style.strokeDashoffset = String(326.726 * (1 - progress));
      text("today-blinks", finite(stats.blinks)); text("today-tracked", minutes(stats.trackedSeconds));
      text("today-rate", stats.blinkRate == null ? "Collecting" : finite(stats.blinkRate).toFixed(1));
      text("today-asymmetry", percentage(stats.asymmetry));
      $("left-rail").style.width = `${active ? clamp(state.left) * 100 : 0}%`;
      $("right-rail").style.width = `${active ? clamp(state.right) * 100 : 0}%`;
      text("processing-delay", finite(state.latencyMs) > 0 ? `${Math.round(state.latencyMs)} ms` : "Waiting");
      text("processing-p95", finite(state.p95Ms) > 0 ? `${Math.round(state.p95Ms)} ms` : "Waiting");
      text("processing-fps", finite(state.fps) > 0 ? finite(state.fps).toFixed(1) : "Waiting");
      text("performance-detail", state.phase === "delayed" ? "Processing is busy. Old frames are ignored, and screen reminders wait for fresh eye data." : "Old frames are dropped rather than queued. Reminders wait when tracking is uncertain.");
      text("today-left-only", finite(stats.leftClosures)); text("today-right-only", finite(stats.rightClosures)); text("today-reminders", finite(stats.reminders));
      renderHistory(state.statistics.week);
      const nextCameraKey = JSON.stringify(state.cameras ?? []);
      if (nextCameraKey !== cameraKey) {
        cameraKey = nextCameraKey;
        const automatic = document.createElement("option"); automatic.value = ""; automatic.textContent = "Automatic camera selection";
        $("camera-choice").replaceChildren(automatic);
        for (const camera of state.cameras ?? []) {
          const option = document.createElement("option"); option.value = String(camera.id); option.textContent = String(camera.name); $("camera-choice").append(option);
        }
      }
      document.querySelectorAll("[data-preference]").forEach((input) => {
        if (document.activeElement === input) return;
        const value = preferences[input.dataset.preference];
        if (input.type === "checkbox") input.checked = Boolean(value);
        else if (value !== undefined) input.value = String(value);
        const range = rangeLabels[input.dataset.preference];
        if (range) text(range[0], range[1](finite(value)));
      });
      document.querySelectorAll("[data-theme]").forEach((button) => button.setAttribute("aria-pressed", String(button.dataset.theme === preferences.theme)));
      icon($("theme-cycle"), state.actualTheme === "dark" ? "moon" : "sun");
      $("theme-cycle").setAttribute("aria-label", `Appearance: ${preferences.theme}. Click to change.`);
      $("storage-warning").hidden = !state.statistics.warning; text("storage-warning", state.statistics.warning ?? "");
      $("toast").hidden = !state.notice; text("toast", state.notice ?? "");
    },
  };
  send({ action: "ready" });
})();
