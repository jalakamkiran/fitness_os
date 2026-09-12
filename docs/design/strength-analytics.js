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
