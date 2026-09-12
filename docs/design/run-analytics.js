(() => {
  const root = document.documentElement;
  const toggles = [
    document.getElementById("themeToggle"),
    document.getElementById("themeTogglePhone"),
  ].filter(Boolean);

  function labelFor(theme) {
    return theme === "dark" ? "Light" : "Dark";
  }

  function setTheme(next) {
    root.setAttribute("data-theme", next);
    localStorage.setItem("fathom-theme", next);
    toggles.forEach((btn) => {
      btn.textContent = labelFor(next);
    });
  }

  function toggleTheme() {
    const cur = root.getAttribute("data-theme") || "light";
    setTheme(cur === "light" ? "dark" : "light");
  }

  const stored = localStorage.getItem("fathom-theme");
  if (stored === "light" || stored === "dark") {
    setTheme(stored);
  } else {
    setTheme(root.getAttribute("data-theme") || "light");
  }

  toggles.forEach((btn) => btn.addEventListener("click", toggleTheme));

  const chart = document.getElementById("storyChart");
  const tabs = document.querySelectorAll(".rn-tab");
  tabs.forEach((tab) => {
    tab.addEventListener("click", () => {
      const series = tab.getAttribute("data-series") || "all";
      tabs.forEach((t) => {
        const on = t === tab;
        t.classList.toggle("is-active", on);
        t.setAttribute("aria-selected", on ? "true" : "false");
      });
      if (!chart) return;
      if (series === "all") chart.removeAttribute("data-focus");
      else chart.setAttribute("data-focus", series);
    });
  });

  const tip = document.getElementById("scrubTip");
  const samples = [
    { t: "04:20", pace: "6'24\"", hr: 142, cad: 158 },
    { t: "08:10", pace: "6'14\"", hr: 161, cad: 164 },
    { t: "12:40", pace: "6'12\"", hr: 168, cad: 162 },
    { t: "16:05", pace: "9'40\"", hr: 128, cad: 118 },
    { t: "19:50", pace: "11'20\"", hr: 112, cad: 104 },
  ];

  if (chart && tip) {
    chart.addEventListener("pointermove", (e) => {
      const rect = chart.getBoundingClientRect();
      const x = Math.min(Math.max(e.clientX - rect.left, 0), rect.width);
      const idx = Math.min(
        samples.length - 1,
        Math.floor((x / rect.width) * samples.length),
      );
      const s = samples[idx];
      tip.hidden = false;
      tip.querySelector(".t-title").textContent = s.t;
      tip.querySelector(".t-mono").textContent =
        `Pace ${s.pace} · HR ${s.hr} · Cad ${s.cad}`;
      tip.style.left = `${Math.min(Math.max(x - 20, 8), rect.width - 150)}px`;
    });
    chart.addEventListener("pointerleave", () => {
      tip.hidden = true;
    });
  }

  function toastExport() {
    const note = document.createElement("div");
    note.setAttribute("role", "status");
    note.textContent = "Session export saved";
    Object.assign(note.style, {
      position: "fixed",
      bottom: "24px",
      left: "50%",
      transform: "translateX(-50%)",
      padding: "10px 14px",
      borderRadius: "999px",
      background: "var(--bg-elev)",
      border: "1px solid var(--line)",
      color: "var(--ink)",
      fontFamily: "var(--font-mono)",
      fontSize: "12px",
      zIndex: "40",
      boxShadow: "0 8px 24px color-mix(in srgb, #000 35%, transparent)",
    });
    document.body.appendChild(note);
    setTimeout(() => note.remove(), 2200);
  }

  document.getElementById("exportPrimary")?.addEventListener("click", toastExport);
})();
