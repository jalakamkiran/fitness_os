(() => {
  const phone = document.getElementById("phone");
  const themeToggle = document.getElementById("themeToggle");
  const root = document.documentElement;

  document.querySelectorAll("[data-mode]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const mode = btn.getAttribute("data-mode");
      if (!mode || !phone) return;
      phone.setAttribute("data-mode", mode);
      btn.parentElement?.querySelectorAll("button").forEach((b) => b.classList.remove("active"));
      btn.classList.add("active");
    });
  });

  document.querySelectorAll("[data-sessions]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const sessions = btn.getAttribute("data-sessions");
      if (!sessions || !phone) return;
      phone.setAttribute("data-sessions", sessions);
      btn.parentElement?.querySelectorAll("button").forEach((b) => b.classList.remove("active"));
      btn.classList.add("active");
    });
  });

  themeToggle?.addEventListener("click", () => {
    const next = root.getAttribute("data-theme") === "dark" ? "light" : "dark";
    root.setAttribute("data-theme", next);
    themeToggle.textContent = next === "dark" ? "Light" : "Dark";
  });

  document.getElementById("choreCta")?.addEventListener("click", () => {
    window.alert("Prototype: one-tap into today’s Programs course (no Programs hub hop).");
  });
})();
