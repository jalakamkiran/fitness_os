(() => {
  const root = document.documentElement;
  const phoneToggle = document.getElementById("themeToggle");
  const railToggle = document.getElementById("themeToggleRail");
  const period = document.getElementById("periodSeg");
  const chartAxis = document.getElementById("chartAxis");
  const chartLine = document.getElementById("hrLine");
  const chartArea = document.getElementById("hrArea");
  const periodLabel = document.getElementById("periodLabel");

  const series = {
    day: {
      label: "Last 24h",
      axis: ["00", "06", "12", "18", "now"],
      points: [62, 58, 56, 72, 88, 76, 64, 60, 58],
    },
    week: {
      label: "7 days",
      axis: ["Mon", "Wed", "Fri", "Sun"],
      points: [61, 59, 58, 60, 57, 56, 58],
    },
    month: {
      label: "30 days",
      axis: ["W1", "W2", "W3", "W4"],
      points: [63, 61, 60, 59, 58, 57, 58, 56],
    },
  };

  function setTheme(next) {
    root.setAttribute("data-theme", next);
    const label = next === "dark" ? "Light" : "Dark";
    if (phoneToggle) phoneToggle.textContent = label;
  }

  function toggleTheme() {
    const cur = root.getAttribute("data-theme") || "light";
    setTheme(cur === "light" ? "dark" : "light");
  }

  function pathFromPoints(pts, w, h, pad) {
    const min = Math.min(...pts) - 2;
    const max = Math.max(...pts) + 2;
    const span = Math.max(1, max - min);
    const step = (w - pad * 2) / Math.max(1, pts.length - 1);
    return pts
      .map((v, i) => {
        const x = pad + i * step;
        const y = pad + (1 - (v - min) / span) * (h - pad * 2);
        return `${i === 0 ? "M" : "L"}${x.toFixed(1)} ${y.toFixed(1)}`;
      })
      .join(" ");
  }

  function renderPeriod(key) {
    const s = series[key] || series.week;
    if (periodLabel) periodLabel.textContent = s.label;
    if (chartAxis) {
      chartAxis.innerHTML = s.axis.map((t) => `<span>${t}</span>`).join("");
    }
    const d = pathFromPoints(s.points, 320, 120, 10);
    if (chartLine) chartLine.setAttribute("d", d);
    if (chartArea) {
      chartArea.setAttribute(
        "d",
        `${d} L310 110 L10 110 Z`
      );
    }
  }

  phoneToggle?.addEventListener("click", toggleTheme);
  railToggle?.addEventListener("click", toggleTheme);

  period?.querySelectorAll(".seg-btn").forEach((btn) => {
    btn.addEventListener("click", () => {
      period.querySelectorAll(".seg-btn").forEach((b) => b.classList.remove("active"));
      btn.classList.add("active");
      renderPeriod(btn.dataset.period);
    });
  });

  setTheme(root.getAttribute("data-theme") || "light");
  renderPeriod("week");
})();
