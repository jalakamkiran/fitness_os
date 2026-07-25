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
})();
