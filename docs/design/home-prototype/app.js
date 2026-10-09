(() => {
  const root = document.documentElement;
  const tip = document.getElementById("nodeTip");
  const phoneToggle = document.getElementById("themeToggle");
  const railToggle = document.getElementById("themeToggleRail");

  function setTheme(next) {
    root.setAttribute("data-theme", next);
    const label = next === "dark" ? "Light" : "Dark";
    if (phoneToggle) phoneToggle.textContent = label;
  }

  function toggleTheme() {
    const cur = root.getAttribute("data-theme") || "light";
    setTheme(cur === "light" ? "dark" : "light");
  }

  phoneToggle?.addEventListener("click", toggleTheme);
  railToggle?.addEventListener("click", toggleTheme);

  document.querySelectorAll(".node").forEach((node) => {
    node.addEventListener("click", () => {
      tip.textContent = node.dataset.tip || "Interval";
    });
  });

  setTheme(root.getAttribute("data-theme") || "light");

  /* ── Agon dock: swim icon is live when an Agon runs, dashed when not started ── */
  const dock = document.getElementById("dockSwim");
  const cap = document.getElementById("dockCap");
  const note = document.getElementById("agonNote");
  function setAgon(state) {
    document.body.dataset.agon = state;
    const running = state === "active";
    if (dock) {
      dock.href = running ? "../programs-prototype/#home" : "../programs-prototype/#create";
      dock.setAttribute("aria-label", running ? "Agon · Pool swim, running. Open" : "Agon · Pool swim, not started. Start an Agon");
    }
    if (cap) cap.textContent = running ? "Wk 3 · live" : "Tap to start";
    if (note) {
      note.innerHTML = running
        ? 'Tap the swim icon → <a href="../programs-prototype/#home">programs-prototype/#home</a>. The Odyssey strip opens <a href="../programs-prototype/#odyssey">#odyssey</a>.'
        : 'Tap the swim icon → <a href="../programs-prototype/#create">programs-prototype/#create</a> (Create Agon). The Odyssey strip opens <a href="../programs-prototype/#odyssey">#odyssey</a>.';
    }
    document.querySelectorAll("[data-agon-btn]").forEach((b) => b.classList.toggle("active", b.dataset.agonBtn === state));
  }
  document.querySelectorAll("[data-agon-btn]").forEach((b) => b.addEventListener("click", () => setAgon(b.dataset.agonBtn)));
  const q = new URLSearchParams(location.search).get("agon");
  setAgon(q === "none" ? "none" : "active");
})();
