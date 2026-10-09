(() => {
  const root = document.documentElement;
  const phone = document.getElementById("phone");

  const states = {
    rest: {
      hoursLabel: "14h",
      meter: 58,
      homeSub: "",
      heroLede: "",
      heroNote: "",
      sleepVisible: true,
      sleepDur: "7h 12m",
      sleepNote: "Solid window · feel logged",
      sessions: [],
      contrib: [
        {
          title: "Strength · yesterday",
          meta: "Ended 20:10",
          hours: "16h",
          source: "watch",
        },
      ],
      insufficient: false,
    },
    stack: {
      hoursLabel: "28h",
      meter: 72,
      homeSub: "",
      heroLede: "",
      heroNote: "",
      sleepVisible: true,
      sleepDur: "6h 40m",
      sleepNote: "Short night · feel logged",
      sessions: [
        {
          id: "swim",
          title: "Pool swim",
          meta: "06:42 · continuous build",
          stat: "2,150 m",
          recovery: "12h",
          source: "estimated",
          hot: false,
        },
        {
          id: "strength",
          title: "Strength",
          meta: "18:20 · full body",
          stat: "52 min",
          recovery: "16h",
          source: "watch",
          hot: true,
        },
      ],
      contrib: [
        {
          title: "Pool swim",
          meta: "06:42",
          hours: "12h",
          source: "estimated",
        },
        {
          title: "Strength",
          meta: "18:20",
          hours: "16h",
          source: "watch",
        },
      ],
      insufficient: false,
    },
    zero: {
      hoursLabel: "0h",
      meter: 0,
      homeSub: "",
      heroLede: "",
      heroNote: "",
      sleepVisible: true,
      sleepDur: "7h 50m",
      sleepNote: "Full night · feel logged",
      sessions: [],
      contrib: [],
      insufficient: false,
    },
    nosleep: {
      hoursLabel: "9h",
      meter: 38,
      homeSub: "",
      heroLede: "",
      heroNote: "",
      sleepVisible: false,
      sleepDur: "—",
      sleepNote: "",
      sessions: [],
      contrib: [
        {
          title: "Badminton · yesterday",
          meta: "Evening session",
          hours: "11h",
          source: "watch",
        },
      ],
      insufficient: false,
    },
    empty: {
      hoursLabel: "—",
      meter: 0,
      homeSub: "",
      heroLede: "",
      heroNote: "",
      sleepVisible: false,
      sleepDur: "—",
      sleepNote: "",
      sessions: [],
      contrib: [],
      insufficient: true,
    },
  };

  let currentState = "rest";
  let currentTab = "home";
  let detailSession = null;

  function setTheme() {
    const next = root.getAttribute("data-theme") === "dark" ? "light" : "dark";
    root.setAttribute("data-theme", next);
    document.getElementById("themeToggle").textContent =
      next === "dark" ? "Light" : "Dark";
  }

  function renderSessions(sessions) {
    const list = document.getElementById("sessionList");
    const empty = document.getElementById("sessionsEmpty");
    list.innerHTML = "";
    if (!sessions.length) {
      empty.classList.remove("is-hidden");
      return;
    }
    empty.classList.add("is-hidden");
    sessions.forEach((s) => {
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "session-card";
      btn.innerHTML = `
        <span class="session-ico" style="${
          s.hot
            ? "background: color-mix(in srgb, var(--hot) 12%, var(--bg)); color: var(--hot);"
            : ""
        }" aria-hidden="true">●</span>
        <span>
          <p class="session-title">${s.title}</p>
          <p class="session-meta">${s.meta}</p>
        </span>
        <span class="session-stat">${s.stat}<span class="session-rec">Rec ${s.recovery}</span></span>
      `;
      btn.addEventListener("click", () => openDetail(s));
      list.appendChild(btn);
    });
  }

  function renderContrib(rows) {
    const el = document.getElementById("contribList");
    if (!rows.length) {
      el.innerHTML =
        '<p class="placeholder-copy">No session contributions in lookback · leftover may still tick from prior days.</p>';
      return;
    }
    el.innerHTML = rows
      .map(
        (r) => `
      <div class="contrib-row">
        <div>
          <p class="contrib-title">${r.title}</p>
          <p class="contrib-meta">${r.meta}</p>
        </div>
        <div>
          <p class="contrib-hours">${r.hours}</p>
          <span class="contrib-src">${r.source}</span>
        </div>
      </div>`
      )
      .join("");
  }

  function applyHours(s) {
    const home = document.getElementById("homeHours");
    const homeVal = document.getElementById("homeHoursValue");
    const homeSub = document.getElementById("homeHoursSub");
    const homeMeter = document.getElementById("homeMeter");
    const hero = document.getElementById("recoveryHero");
    const heroVal = document.getElementById("heroValue");
    const heroLede = document.getElementById("heroLede");
    const heroNote = document.getElementById("heroNote");
    const heroMeter = document.getElementById("heroMeter");

    home.classList.toggle("is-empty", s.insufficient);
    hero.classList.toggle("is-empty", s.insufficient);
    homeVal.textContent = s.hoursLabel;
    heroVal.textContent = s.hoursLabel;
    homeVal.classList.toggle("is-dash", s.insufficient);
    heroVal.classList.toggle("is-dash", s.insufficient);
    homeSub.textContent = s.homeSub;
    homeSub.hidden = !s.homeSub;
    heroLede.textContent = s.heroLede;
    heroLede.hidden = !s.heroLede;
    heroNote.textContent = s.heroNote;
    heroNote.hidden = !s.heroNote;
    homeMeter.style.width = `${s.meter}%`;
    heroMeter.style.width = `${s.meter}%`;
  }

  function applySleep(s) {
    const card = document.getElementById("sleepCard");
    card.classList.toggle("is-hidden", !s.sleepVisible);
    document.getElementById("sleepDur").textContent = s.sleepDur;
    document.getElementById("sleepNote").textContent = s.sleepNote;
    document.getElementById("recSleepDur").textContent = s.sleepVisible
      ? s.sleepDur
      : "—";
  }

  function render() {
    const s = states[currentState];
    phone.dataset.state = currentState;
    phone.dataset.tab = currentTab;
    applyHours(s);
    applySleep(s);
    renderSessions(s.sessions);
    renderContrib(s.contrib);

    document.querySelectorAll("[data-panel]").forEach((panel) => {
      const name = panel.getAttribute("data-panel");
      const show =
        currentTab === "detail"
          ? name === "detail"
          : name === currentTab;
      panel.hidden = !show;
    });

    document.querySelectorAll(".tab[data-nav]").forEach((t) => {
      t.classList.toggle("is-on", t.dataset.nav === currentTab);
    });
  }

  function openDetail(session) {
    detailSession = session;
    currentTab = "detail";
    document.getElementById("detailTitle").textContent = session.title;
    document.getElementById("detailMeta").textContent = session.meta;
    document.getElementById("detailRecovery").textContent = session.recovery;
    document.getElementById("detailSource").textContent = session.source;
    render();
  }

  document.getElementById("themeToggle").addEventListener("click", setTheme);

  document.getElementById("stateBtns").addEventListener("click", (e) => {
    const btn = e.target.closest("button[data-state]");
    if (!btn) return;
    currentState = btn.dataset.state;
    if (currentTab === "detail") currentTab = "home";
    document.querySelectorAll("#stateBtns button").forEach((b) => {
      b.classList.toggle("is-on", b === btn);
    });
    render();
  });

  document.querySelector(".tabbar").addEventListener("click", (e) => {
    const tab = e.target.closest(".tab[data-nav]");
    if (!tab || tab.disabled) return;
    currentTab = tab.dataset.nav;
    detailSession = null;
    render();
  });

  document.querySelector(".subtabs").addEventListener("click", (e) => {
    const btn = e.target.closest(".subtab");
    if (!btn) return;
    document.querySelectorAll(".subtab").forEach((t) => {
      t.classList.toggle("is-on", t === btn);
    });
    document.querySelectorAll(".subpanel").forEach((p) => {
      p.hidden = p.dataset.subpanel !== btn.dataset.sub;
    });
  });

  document.getElementById("backFromDetail").addEventListener("click", () => {
    currentTab = "home";
    detailSession = null;
    render();
  });

  render();
})();
