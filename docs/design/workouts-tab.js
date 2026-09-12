(() => {
  const root = document.documentElement;
  const phoneToggle = document.getElementById("themeToggle");
  const railToggle = document.getElementById("themeToggleRail");
  const sportTabs = document.getElementById("sportTabs");
  const swimPanel = document.getElementById("swimPanel");
  const strengthPanel = document.getElementById("strengthPanel");
  const emptyRun = document.getElementById("emptyRun");

  function setTheme(next) {
    root.setAttribute("data-theme", next);
    const label = next === "dark" ? "Light" : "Dark";
    if (phoneToggle) phoneToggle.textContent = label;
  }

  function toggleTheme() {
    const cur = root.getAttribute("data-theme") || "light";
    setTheme(cur === "light" ? "dark" : "light");
  }

  function showSport(sport) {
    sportTabs?.querySelectorAll(".sport-tab").forEach((btn) => {
      const on = btn.dataset.sport === sport;
      btn.classList.toggle("active", on);
      btn.setAttribute("aria-selected", on ? "true" : "false");
    });
    const isSwim = sport === "swim";
    const isRun = sport === "run";
    const isStrength = sport === "strength";
    swimPanel?.classList.toggle("hide", !isSwim);
    strengthPanel?.classList.toggle("hide", !isStrength);
    emptyRun?.classList.toggle("show", isRun);
  }

  phoneToggle?.addEventListener("click", toggleTheme);
  railToggle?.addEventListener("click", toggleTheme);

  sportTabs?.querySelectorAll(".sport-tab").forEach((btn) => {
    btn.addEventListener("click", () => showSport(btn.dataset.sport));
  });

  setTheme(root.getAttribute("data-theme") || "light");
  showSport("swim");
})();
