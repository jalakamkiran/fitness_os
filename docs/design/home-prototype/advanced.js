(() => {
  const TIPS = [
    {
      id: "scatter",
      title: "DPS × stroke rate",
      body: "Each point is an interval plotted by distance-per-stroke vs tempo. Speed is roughly DPS × rate — the ‘mountain’ TritonWear describes.",
      good: "Stay in the mint band (sweet spot). Late points drifting down-right mean you’re spinning faster but slipping.",
    },
    {
      id: "band",
      title: "Pace vs CSS band",
      body: "Critical Swim Speed sets a threshold corridor. The chart asks whether this set stayed on-plan or drifted.",
      good: "Most points inside the band. Breaking above late = aerobic fade or pacing error.",
    },
    {
      id: "si",
      title: "Stroke index",
      body: "Stroke index combines speed and DPS into one efficiency×speed score used in elite dashboards.",
      good: "Hold SI across the main set. A steep drop is a skill leak under load — shorten before adding volume.",
    },
    {
      id: "overlay2",
      title: "Session overlay",
      body: "Same test shape across days (TrainingPeaks-style compare). Exposes progress that averages hide.",
      good: "Newer line flatter/faster than older. Use for 8×100 / CSS checks, not random free swims.",
    },
    {
      id: "radar",
      title: "Session radar",
      body: "Compresses the session into a profile: pace hold, efficiency, consistency, volume, recovery readiness.",
      good: "Look for the dent — that’s the single axis to coach next, not five equal problems.",
    },
    {
      id: "phases",
      title: "UW / turn / swim",
      body: "Phase splits need trustworthy underwater & turn sensors (TritonWear IMU class).",
      good: "Don’t invent from LPv2 interval rows. Ship only when GT5 evidence supports it.",
    },
  ];

  const tour = document.getElementById("tour");
  const tipList = document.getElementById("tipList");
  let idx = 0;

  tipList.innerHTML = TIPS.map(
    (t) => `<li><strong>${t.title}:</strong> ${t.body} <em>${t.good}</em></li>`
  ).join("");

  function showTip(i) {
    const t = TIPS[i];
    if (!t) return endTour();
    idx = i;
    document.getElementById("tourStep").textContent = `Tip ${i + 1} / ${TIPS.length}`;
    document.getElementById("tourTitle").textContent = t.title;
    document.getElementById("tourBody").textContent = t.body;
    document.getElementById("tourGood").textContent = t.good;
    tour.hidden = false;
    document.querySelectorAll(".chart-card").forEach((el) => {
      el.classList.toggle("focus", el.dataset.tipId === t.id);
    });
  }

  function endTour() {
    tour.hidden = true;
    localStorage.setItem("fos.advTour.v1", "done");
    document.querySelectorAll(".chart-card").forEach((el) => el.classList.remove("focus"));
  }

  document.getElementById("tourNext")?.addEventListener("click", () => showTip(idx + 1));
  document.getElementById("tourSkip")?.addEventListener("click", endTour);
  document.getElementById("replayTour")?.addEventListener("click", () => {
    localStorage.removeItem("fos.advTour.v1");
    showTip(0);
  });
  document.querySelectorAll("[data-open-tip]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const i = TIPS.findIndex((t) => t.id === btn.getAttribute("data-open-tip"));
      if (i >= 0) showTip(i);
    });
  });

  if (localStorage.getItem("fos.advTour.v1") !== "done") {
    setTimeout(() => showTip(0), 300);
  }
})();
