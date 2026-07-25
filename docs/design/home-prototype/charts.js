(() => {
  const TIPS = [
    {
      id: "pace",
      title: "Pace by interval",
      body: "Each bar is how long that interval took, normalized to pace (s/100m). Rising bars mean you slowed as the set went on.",
      good: "Good: flat or slightly negative split. Red/amber late bars = fatigue onset.",
    },
    {
      id: "swolf",
      title: "SWOLF",
      body: "SWOLF = time for the length + stroke count. Same idea as golf: lower score usually means more efficient swimming.",
      good: "Good: SWOLF holds or drops while pace holds. Rising SWOLF with rising pace = fading technique under load.",
    },
    {
      id: "strokes",
      title: "Strokes per interval",
      body: "Stroke count is a distance-per-stroke proxy. Fewer strokes at the same pace usually means a longer, cleaner pull.",
      good: "Good: stable or falling count without slowing down. Spikes often mean slip, spin, or broken rhythm.",
    },
    {
      id: "overlay",
      title: "Pace + SWOLF overlay",
      body: "Two signals on one timeline so you can tell ‘tired but efficient’ from ‘still moving but getting sloppy’.",
      good: "Watch the crossover: when both climb together, shorten sets before adding volume.",
    },
    {
      id: "hr",
      title: "Heart rate",
      body: "HR shows physiological cost. Useful only with a real sample stream from the watch.",
      good: "Fathom hides this chart when samples are missing — no decorative empty graphs.",
    },
  ];

  const tour = document.getElementById("tour");
  const stepEl = document.getElementById("tourStep");
  const titleEl = document.getElementById("tourTitle");
  const bodyEl = document.getElementById("tourBody");
  const goodEl = document.getElementById("tourGood");
  const tipList = document.getElementById("tipList");
  let idx = 0;

  tipList.innerHTML = TIPS.map(
    (t) =>
      `<li><strong>${t.title}:</strong> ${t.body} <em>${t.good}</em></li>`
  ).join("");

  function showTip(i) {
    const t = TIPS[i];
    if (!t) return endTour();
    idx = i;
    stepEl.textContent = `Tip ${i + 1} / ${TIPS.length}`;
    titleEl.textContent = t.title;
    bodyEl.textContent = t.body;
    goodEl.textContent = t.good;
    tour.hidden = false;
    document
      .querySelectorAll(".chart-card")
      .forEach((el) => el.classList.toggle("focus", el.dataset.tipId === t.id));
  }

  function endTour() {
    tour.hidden = true;
    localStorage.setItem("fos.chartTour.v1", "done");
    document
      .querySelectorAll(".chart-card")
      .forEach((el) => el.classList.remove("focus"));
  }

  document.getElementById("tourNext")?.addEventListener("click", () => {
    showTip(idx + 1);
  });
  document.getElementById("tourSkip")?.addEventListener("click", endTour);
  document.getElementById("replayTour")?.addEventListener("click", () => {
    localStorage.removeItem("fos.chartTour.v1");
    showTip(0);
  });

  document.querySelectorAll("[data-open-tip]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const id = btn.getAttribute("data-open-tip");
      const i = TIPS.findIndex((t) => t.id === id);
      if (i >= 0) showTip(i);
    });
  });

  if (localStorage.getItem("fos.chartTour.v1") !== "done") {
    setTimeout(() => showTip(0), 350);
  }
})();
