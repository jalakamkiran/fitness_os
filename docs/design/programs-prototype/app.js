/* Fathom · Agon · Pool swim prototype
   Static, no framework. All data is a demo fixture — nothing here is computed from real swims.
   Vocabulary: Odyssey (journey) · Agon (challenge) · Sounding (starting depth) · Areté (points)
               Depth (tier) · Kleos (achievements) · Streak (plain). */
(() => {
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));
  const fmt = (n) => n.toLocaleString("en-US");
  const mmss = (s) => `${Math.floor(s / 60)}:${String(Math.round(s % 60)).padStart(2, "0")}`;
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  /* ───────────── Demo athlete ───────────── */
  const BASE = { cap: 1000, pace: 123 }; // ~1,000 m non-stop at 2:03 /100 m
  const START = new Date(2026, 9, 12); // Mon Oct 12
  const DOW = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  const MON = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  const label = (d) => `${DOW[d.getDay()]} ${MON[d.getMonth()]} ${d.getDate()}`;
  const addDays = (d, n) => { const x = new Date(d); x.setDate(x.getDate() + n); return x; };
  const dkey = (d) => d.getMonth() * 100 + d.getDate();

  const ALIASES = {
    "base-history": "sounding-history",
    "base-test": "sounding-test",
    "base-self": "sounding-self",
    pass: "kleos",
    progress: "odyssey",
  };

  const DEFAULTS = () => ({
    screen: "create",
    clock: "plan", // plan | slipped
    stepDown: false,
    load: "heavy", // heavy | clear
    game: true,
    theme: document.documentElement.dataset.theme || "light",
    warnOn: true,
    choreDone: false,
    skipped: null,
    adjusted: null,
    segDone: [false, false, false],
    testPhase: "prescribed", // prescribed | synced
    route: "history", // history | test | self  (decided behind the scenes in product)
    synced: false, // today's swim synced from the watch
    sessTab: "course", // course | session
    create: { dist: 1200, time: 1440, weeks: 3, spw: 3 },
    self: { dist: 1000, time: 1230, when: "2 weeks ago" },
  });
  let state = DEFAULTS();

  /* ───────────── Course content (warm-up / main / cool-down) ───────────── */
  const SESSION_PLAN = {
    kicker: "Mon Oct 26 · Training 6 of 7",
    title: "Trial-pace broken swim",
    sub: "3 × 400 at 2:00 /100 m",
    distance: 1800,
    est: "~44 min",
    pace: "2:00",
    focus: "Even splits",
    why: "<b>Why this set:</b> three 400s with 30 s rest rehearse 1,200 m at trial pace while keeping each rep inside what you can hold today. Main-set volume ≈ trial distance, rest ≤ :30, and +100 m per block.",
    segments: [
      { key: "warm", name: "Warm-up", m: 400, min: "~9 min", sets: [
        { reps: "1 × 200", desc: "Easy freestyle", note: "RPE 3 · loosen shoulders", pace: "2:15", rest: "—" },
        { reps: "4 × 50", desc: "Catch-up drill / swim, alternate", note: "Odd lengths drill · even lengths swim", pace: "—", rest: ":15" },
      ] },
      { key: "main", name: "Main set", m: 1200, min: "~26 min", sets: [
        { reps: "3 × 400", desc: "Freestyle, steady at trial pace", note: "RPE 6 · hold even, no fast first 100", pace: "2:00", rest: ":30" },
      ] },
      { key: "cool", name: "Cool-down", m: 200, min: "~5 min", sets: [
        { reps: "1 × 100", desc: "Easy freestyle", note: "Breathe every 2 strokes", pace: "2:20", rest: "—" },
        { reps: "1 × 100", desc: "Easy choice, mix in backstroke", note: "Shake out arms", pace: "—", rest: "—" },
      ] },
    ],
  };
  const SESSION_SLIP = {
    kicker: "Mon Nov 2 · Reshaped after Trial 2",
    title: "Long steady swim",
    sub: "800 non-stop + 2 × 200",
    distance: 1800,
    est: "~45 min",
    pace: "2:05",
    focus: "Build the long swim",
    why: "<b>Why this set:</b> pace eased after 800 m last time, so this block adds non-stop volume before the retry: one longer continuous swim, then a short pace rehearsal.",
    segments: [
      { key: "warm", name: "Warm-up", m: 400, min: "~9 min", sets: [
        { reps: "1 × 200", desc: "Easy freestyle", note: "RPE 3", pace: "2:15", rest: "—" },
        { reps: "4 × 50", desc: "Catch-up drill / swim, alternate", note: "Odd lengths drill · even lengths swim", pace: "—", rest: ":15" },
      ] },
      { key: "main", name: "Main set", m: 1200, min: "~27 min", sets: [
        { reps: "1 × 800", desc: "Non-stop freestyle, steady", note: "RPE 5–6 · count strokes per length, keep them flat", pace: "2:05", rest: ":45" },
        { reps: "2 × 200", desc: "Freestyle at trial pace", note: "RPE 6 · finish stronger than you start", pace: "2:00", rest: ":30" },
      ] },
      { key: "cool", name: "Cool-down", m: 200, min: "~5 min", sets: [
        { reps: "1 × 200", desc: "Easy, any stroke", note: "Slow it right down", pace: "2:20", rest: "—" },
      ] },
    ],
  };

  /* ───────────── Session data (post-sync demo) ───────────── */
  // rows: seg 0 warm · 1 main · 2 cool. sec includes rest. pace is moving pace per 100 m.
  const ACT_PLAN = {
    synced: "Synced from GT5 · 07:12",
    rows: [
      { seg: 0, name: "Easy freestyle", dist: 200, sec: 268, pace: "2:14", ps: 134, hr: 118, swolf: 41 },
      { seg: 0, name: "4 × 50 drill / swim", dist: 200, sec: 292, pace: "—", ps: 138, hr: 124, swolf: 44 },
      { seg: 1, name: "400 · rep 1", dist: 400, sec: 512, pace: "2:00", ps: 120, hr: 143, swolf: 39 },
      { seg: 1, name: "400 · rep 2", dist: 400, sec: 510, pace: "2:00", ps: 120, hr: 149, swolf: 38 },
      { seg: 1, name: "400 · rep 3", dist: 400, sec: 478, pace: "1:59", ps: 119, hr: 154, swolf: 38 },
      { seg: 2, name: "Easy freestyle", dist: 100, sec: 140, pace: "2:20", ps: 140, hr: 132, swolf: 41 },
      { seg: 2, name: "Easy choice", dist: 100, sec: 144, pace: "2:24", ps: 144, hr: 121, swolf: 43 },
    ],
    note: "Even splits across all three 400s, with the last rep a second quicker.",
  };
  const ACT_SLIP = {
    synced: "Synced from GT5 · 07:05",
    rows: [
      { seg: 0, name: "Easy freestyle", dist: 200, sec: 268, pace: "2:14", ps: 134, hr: 118, swolf: 41 },
      { seg: 0, name: "4 × 50 drill / swim", dist: 200, sec: 292, pace: "—", ps: 138, hr: 124, swolf: 44 },
      { seg: 1, name: "800 non-stop", dist: 800, sec: 1047, pace: "2:05", ps: 125, hr: 141, swolf: 40 },
      { seg: 1, name: "200 · rep 1", dist: 200, sec: 270, pace: "2:00", ps: 120, hr: 150, swolf: 38 },
      { seg: 1, name: "200 · rep 2", dist: 200, sec: 238, pace: "1:59", ps: 119, hr: 156, swolf: 38 },
      { seg: 2, name: "Easy, any stroke", dist: 200, sec: 286, pace: "2:23", ps: 143, hr: 126, swolf: 42 },
    ],
    note: "The 800 held steady at 2:05, and both 200s came in at trial pace.",
  };

  /* ───────────── Clock data (on plan vs after trial not passed) ───────────── */
  function clockData() {
    if (state.clock === "plan") {
      return {
        today: "Mon Oct 26",
        todayDate: new Date(2026, 9, 26),
        week: "Week 3 of 3",
        capacity: 1100,
        ms: { name: "Trial 2", dist: 1200, spec: "1,200 m non-stop · ≤ 24:00", date: "Sat Oct 31", rel: "in 5 days" },
        rungs: [
          { v: "1,000", s: "Sounding", c: "done" },
          { v: "1,100", s: "Trial 1", c: "done" },
          { v: "1,200", s: "Trial 2", c: "next" },
        ],
        fc: { planned: "Sat Oct 31", now: "Sat Oct 31", delta: 0, status: "On plan", sub: "Matches the course you activated." },
        tl: { span: 21, today: 14, pts: [
          { d: 0, cls: "start", l: "Oct 12", sub: "start", above: false },
          { d: 12, cls: "done", l: "Oct 24", sub: "1,100", above: true },
          { d: 19, cls: "next", l: "Oct 31", sub: "1,200", above: true },
        ] },
        tlDetail: { span: 25, today: 14, pts: [
          { d: 0, cls: "start", l: "Oct 12", sub: "start", above: false },
          { d: 12, cls: "done", l: "Oct 24", sub: "Trial 1", above: true },
          { d: 19, cls: "next", l: "Oct 31", sub: "Trial 2", above: true },
          { d: 23, cls: "ghost", l: "Nov 4", sub: "if retry", above: true },
        ], band: { from: 19, to: 23, text: "Range if Trial 2 needs a retry" } },
        ledger: null,
        block: { text: "Session 1 of 2 before Trial 2", done: 0, total: 2 },
        session: SESSION_PLAN,
        act: ACT_PLAN,
        warn: { title: "Heavy evening yesterday", body: "Badminton Sun 7:30 pm · 74 min · load is high for you (≈ 1.4× your usual). Today’s swim stays on the course." },
        game: { arete: 1090, depth: 5, floor: 1000, cost: 500, streak: 2, best: 2, passes: 3 },
      };
    }
    const step = state.stepDown;
    return {
      today: "Mon Nov 2",
      todayDate: new Date(2026, 10, 2),
      week: step ? "Horizon +11 d" : "Horizon +4 d",
      capacity: 1120,
      ms: step
        ? { name: "Step · 1,150 m", dist: 1150, spec: "1,150 m non-stop · ≤ 23:00", date: "Wed Nov 4", rel: "in 2 days" }
        : { name: "Trial 2 · retry", dist: 1200, spec: "1,200 m non-stop · ≤ 24:00", date: "Wed Nov 4", rel: "in 2 days" },
      rungs: step
        ? [
            { v: "1,000", s: "Sounding", c: "done" },
            { v: "1,100", s: "Trial 1", c: "done" },
            { v: "1,150", s: "Step", c: "next" },
            { v: "1,200", s: "Trial 2", c: "" },
          ]
        : [
            { v: "1,000", s: "Sounding", c: "done" },
            { v: "1,100", s: "Trial 1", c: "done" },
            { v: "1,200", s: "Trial 2", c: "next" },
          ],
      fc: step
        ? { planned: "Sat Oct 31", now: "Wed Nov 11", delta: 11, status: "Moved +11 d", sub: "Step Nov 4, then the Trial 2 retry Nov 11." }
        : { planned: "Sat Oct 31", now: "Wed Nov 4", delta: 4, status: "Moved +4 d", sub: "Retry after one reshaped session." },
      tl: step
        ? { span: 32, today: 21, pts: [
            { d: 0, cls: "start", l: "Oct 12", sub: "start", above: false },
            { d: 12, cls: "done", l: "Oct 24", sub: "1,100", above: true },
            { d: 19, cls: "ghost", l: "", sub: "", above: true },
            { d: 23, cls: "next", l: "Nov 4", sub: "1,150", above: true },
            { d: 30, cls: "next", l: "Nov 11", sub: "1,200", above: true },
          ] }
        : { span: 25, today: 21, pts: [
            { d: 0, cls: "start", l: "Oct 12", sub: "start", above: false },
            { d: 12, cls: "done", l: "Oct 24", sub: "1,100", above: true },
            { d: 19, cls: "ghost", l: "Oct 31", sub: "1,200", above: true },
            { d: 23, cls: "next", l: "Nov 4", sub: "1,200", above: true },
          ] },
      ledger: {
        text: step
          ? "<b>Trial 2 not cleared</b> Oct 31 · 1,120 m of 1,200 m. You chose a 1,150 m step first, so the goal forecast moves to Nov 11."
          : "<b>Trial 2 not cleared</b> Oct 31 · 1,120 m of 1,200 m. Retry set for Nov 4, after one reshaped session.",
      },
      block: { text: "Session 1 of 1 before the retry", done: 0, total: 1 },
      session: SESSION_SLIP,
      act: ACT_SLIP,
      warn: { title: "Strength yesterday", body: "Strength Sun 9:00 am · 52 min · load is high for you (≈ 1.3× your usual). Today’s swim stays on the course." },
      game: { arete: 1480, depth: 5, floor: 1000, cost: 500, streak: 3, best: 3, passes: 3 },
    };
  }
  // The slipped timeline detail reuses the compact one with ghost markers.
  const detailTl = (d) => d.tlDetail || { ...d.tl };

  /* ───────────── DOM refs ───────────── */
  const phone = $("#phone");
  const scroll = $("#scroll");
  const ctaBar = $("#ctaBar");
  const toastEl = $("#toast");
  const backdrop = $("#sheetBackdrop");
  const kleosEl = $("#s-kleos");

  const SCREENS = {
    create: { el: "s-create", title: "New Agon", sub: "Step 1 of 3 · Pool swim", tabs: false, back: null },
    sounding: { el: "s-sounding", title: "Sounding", sub: "Step 2 of 3", tabs: false, back: "create" },
    "sounding-history": { el: "s-result", title: "Sounding", sub: "Step 2 of 3", tabs: false, back: "create" },
    "sounding-test": { el: "s-result", title: "Sounding", sub: "Step 2 of 3 · Test swim", tabs: false, back: "create" },
    "sounding-self": { el: "s-result", title: "Sounding", sub: "Step 2 of 3 · Your swim", tabs: false, back: "create" },
    home: { el: "s-home", title: "Agon · Pool", sub: () => `1,200 m · ${clockData().week}`, tabs: true, tab: "home", back: null },
    session: { el: "s-session", title: "Today", sub: () => clockData().today, tabs: true, tab: "session", back: "home" },
    odyssey: { el: "s-odyssey", title: "Odyssey", sub: () => `The Odyssey · ${clockData().week}`, tabs: true, tab: "odyssey", back: "home" },
    forecast: { el: "s-forecast", title: "Forecast", sub: "Agon · Pool swim", tabs: true, tab: "home", back: "home" },
    kleos: { el: null, chrome: false, tabs: false, overlay: true },
    fail: { el: "s-fail", chrome: false, tabs: false },
  };
  const ORDER = ["create", "sounding", "sounding-history", "sounding-test", "sounding-self", "home", "session", "kleos", "fail", "odyssey", "forecast"];

  /* ───────────── Helpers ───────────── */
  let toastTimer;
  function toast(msg) {
    toastEl.textContent = msg;
    toastEl.classList.add("show");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => toastEl.classList.remove("show"), 2800);
  }
  function openSheet(id) {
    $(`#${id}`).classList.add("open");
    $(`#${id}`).setAttribute("aria-hidden", "false");
    backdrop.classList.add("open");
  }
  function closeSheets() {
    $$(".sheet.open").forEach((s) => { s.classList.remove("open"); s.setAttribute("aria-hidden", "true"); });
    backdrop.classList.remove("open");
  }
  const gameTag = (html) => `<span class="game-only">${html}</span>`;
  let anim = false; // true only for the render triggered by navigating to a screen

  const sparkSvg = (arr, cls = "") => {
    const mn = Math.min(...arr), mx = Math.max(...arr);
    const pts = arr.map((v, i) => [4 + (i * 192) / (arr.length - 1), 28 - ((v - mn) / (mx - mn || 1)) * 22]);
    return `<svg class="spark ${cls}" viewBox="0 0 200 34" preserveAspectRatio="none" aria-hidden="true"><path d="M${pts.map((p) => p.map((n) => n.toFixed(1)).join(" ")).join(" L")}"/><circle cx="${pts[pts.length - 1][0]}" cy="${pts[pts.length - 1][1]}" r="3.2"/></svg>`;
  };

  /* ───────────── 1 · Create Agon ───────────── */
  function renderCreate() {
    const c = state.create;
    const pace = c.time / (c.dist / 100);
    $("#inDist").innerHTML = `${fmt(c.dist)}<span class="unit"> m</span>`;
    $("#inTime").textContent = mmss(c.time);
    $("#paceHint").textContent = `${mmss(pace)} /100 m`;
    $("#timeFoot").textContent = `Your pace now · ${mmss(BASE.pace)} /100 m on a ~1,000 m non-stop swim`;

    $("#chipsDist").innerHTML = [800, 1000, 1200, 1500]
      .map((d) => `<button type="button" class="${c.dist === d ? "on" : ""}" data-act="dist" data-v="${d}">${fmt(d)}</button>`).join("");
    $("#segWeeks").innerHTML = [2, 3, 4, 6, 8, 12]
      .map((w) => `<button type="button" class="${c.weeks === w ? "on" : ""}" data-act="weeks" data-v="${w}" role="radio" aria-checked="${c.weeks === w}">${w}<small>wk</small></button>`).join("");
    $("#segSpw").innerHTML = [2, 3, 4, 5]
      .map((n) => `<button type="button" class="${c.spw === n ? "on" : ""}" data-act="spw" data-v="${n}" role="radio" aria-checked="${c.spw === n}">${n}<small>× / wk</small></button>`).join("");

    const end = new Date(START); end.setDate(end.getDate() + c.weeks * 7 - 1);
    $("#horizonHint").textContent = `Mon Oct 12 → ${label(end)}`;
    $("#spwHint").textContent = `Streak holds at ${Math.ceil(c.spw / 2)} of ${c.spw}`;

    const gain = (c.dist - BASE.cap) / BASE.cap;
    const wDist = gain <= 0 ? 2 : Math.max(2, Math.ceil((gain / 0.2) * 2.5));
    const paceGain = ((BASE.pace - pace) / BASE.pace) * 100;
    const wPace = paceGain <= 0 ? 2 : Math.max(2, Math.ceil(paceGain / 0.9));
    const need = Math.max(wDist, wPace);
    const fits = c.weeks >= need;
    const trials = Math.max(1, Math.round(c.weeks / 1.5));
    const rungs = [];
    for (let i = 1; i <= trials; i++) rungs.push(gain <= 0 ? c.dist : Math.round((BASE.cap + (c.dist - BASE.cap) * (i / trials)) / 50) * 50);
    const ladder = [BASE.cap, ...rungs].filter((v, i, a) => i === 0 || v !== a[i - 1]).map(fmt).join(" → ");
    const longPole = wPace > wDist ? "pace" : "distance";
    const sessions = c.weeks * c.spw;

    $("#createRead").className = `read-card ${fits ? "" : "warn"}`;
    $("#createRead").innerHTML = `
      <p class="kicker">Your Agon at a glance</p>
      <p class="read-line">${fmt(c.dist)} m in ${mmss(c.time)} · ${mmss(pace)} /100 m · ${c.weeks} wk · ${c.spw}×/wk</p>
      <div class="read-grid">
        <div><p>Distance</p><strong>${gain > 0 ? "+" + Math.round(gain * 100) + "%" : "hold"}</strong></div>
        <div><p>Pace</p><strong>${paceGain > 0 ? "−" + Math.max(1, Math.round(BASE.pace - pace)) + " s" : "same"}</strong></div>
        <div><p>Sessions</p><strong>${sessions}<small class="dim"> · ${trials} trial${trials > 1 ? "s" : ""}</small></strong></div>
      </div>
      <p class="verdict">Ladder <b class="mono">${ladder} m</b></p>
      <span class="verdict-badge">${fits ? "Fits your horizon" : "Horizon looks short"}</span>
      <p class="verdict">${fits
        ? `Estimate: distance needs ~${wDist} wk, pace ~${wPace} wk. The ${c.dist === 1200 ? "1,200 m trial" : "last trial"} is the main job; the time target rides along.`
        : `Estimate: <b>~${need} weeks</b>, with <b>${longPole}</b> as the longest piece (distance ~${wDist} wk, pace ~${wPace} wk). You can still create it; your forecast will show the gap.`}</p>
      ${fits ? "" : `<button type="button" class="btn-inline accent" data-act="weeks" data-v="${Math.min(need, 12)}" style="justify-self:start">Use ${Math.min(need, 12)} weeks</button>`}
      <p class="reward-line game-only"><i></i><span>Each trial earns <b>Areté</b> · progress points. Clearing one unlocks <b>Kleos</b>.</span></p>
    `;
  }

  /* ───────────── 2 · Sounding · building ───────────── */
  const SOUND_LINES = ["Reading your recent pool swims", "Finding your starting depth", "Setting your course"];
  let soundTimers = [];
  function clearSoundTimers() { soundTimers.forEach(clearTimeout); soundTimers = []; }
  function startSounding() {
    clearSoundTimers();
    const line = $("#soundLine");
    const dots = $$(".sound-dots i");
    const set = (i) => {
      line.classList.remove("swap"); void line.offsetWidth; line.classList.add("swap");
      line.textContent = SOUND_LINES[i];
      dots.forEach((d, j) => d.classList.toggle("on", j <= i));
    };
    set(0);
    soundTimers.push(setTimeout(() => state.screen === "sounding" && set(1), 1150));
    soundTimers.push(setTimeout(() => state.screen === "sounding" && set(2), 2300));
    soundTimers.push(setTimeout(() => state.screen === "sounding" && go(`sounding-${state.route}`), 3500));
  }

  /* ───────────── 2a / 2b / 2c · Sounding result ───────────── */
  function courseCard(checkIn) {
    return `
    <section class="card cap-card">
      <div class="layer-head"><span class="layer-tag cap">Your course</span><span class="mono tiny dim">Mon · Wed · Sat</span></div>
      <div class="ladder-prop" style="margin-top:6px">
        <div class="lp-row"><span class="d">Mon Oct 12</span><b>${checkIn ? "Check-in swim" : "First session"}</b>${checkIn ? `<span class="tent">fine-tunes</span>` : `<span class="t">1,700 m</span>`}</div>
        <div class="lp-row trial"><span class="d">Sat Oct 24</span><b>Trial 1 · 1,100 m</b><span class="t"></span></div>
        <div class="lp-row trial"><span class="d">Sat Oct 31</span><b>Trial 2 · 1,200 m ≤ 24:00</b><span class="t"></span></div>
      </div>
      <p class="tiny dim" style="margin:6px 0 0">7 training days + 2 trials, each with warm-up, main set and cool-down. Dates move only if a trial isn’t passed or is delayed.</p>
    </section>`;
  }
  function readingCard(k3, foot) {
    return `
    <section class="card evidence">
      <div class="layer-head"><span class="layer-tag cap">Starting depth</span><span class="mono tiny dim">Sounding</span></div>
      <div class="ev-grid">${k3.map((k) => `<div><p>${k[0]}</p><strong>${k[1]}<small>${k[2]}</small></strong></div>`).join("")}</div>
      ${foot ? `<p class="threshold">${foot}</p>` : ""}
    </section>`;
  }
  function renderResult() {
    const mode = state.screen.replace("sounding-", "");
    const bar = `<div class="step-bar" aria-hidden="true"><span class="on"></span><span class="on"></span><span></span></div>`;
    let h = bar;

    if (mode === "history") {
      h += `
        <div class="sound-head"><p class="kicker k-cap">Sounding complete</p><h2>Your starting depth</h2>
          <p class="dim">We found a strong starting point from your recent pool swims.</p></div>
        ${readingCard([["Non-stop", "1,000", " m"], ["Pace", "2:03", " /100"], ["Swims", "14", " / 8 wk"]], "Based on your last 8 weeks of pool swimming. Your course starts right where you are.")}
        ${courseCard(false)}`;
    }

    if (mode === "test") {
      const synced = state.testPhase === "synced";
      h += `
        <div class="sound-head"><p class="kicker k-cap">Sounding</p><h2>${synced ? "Test swim found" : "One test swim sets your course"}</h2>
          <p class="dim">${synced ? "We matched your swim from this morning." : "A single steady swim gives us your starting depth. It takes about 35 minutes."}</p></div>
        <section class="card">
          <div class="layer-head"><span class="layer-tag cap">The test</span><span class="mono tiny dim">~35 min</span></div>
          <ul class="test-recipe" style="margin-top:6px">
            <li><span class="mono">Warm-up</span><span>Easy freestyle, mix in drills</span><b>300 m</b></li>
            <li class="key"><span class="mono">Test</span><span>Swim non-stop at a steady, comfortable effort. Stop only when you need to (up to 1,200 m).</span><b>no rest</b></li>
            <li><span class="mono">Cool-down</span><span>Easy, any stroke</span><b>200 m</b></li>
          </ul>
          <p class="tiny dim" style="margin:8px 0 0">Continuous swimming gives the clearest read of where you are.</p>
        </section>
        ${synced
          ? `<div class="sync-sim done"><i></i><span>Synced from GT5 · <b>1,000 m non-stop</b> · 20:30 · 2:03 /100 m</span></div>
             ${readingCard([["Non-stop", "1,000", " m"], ["Pace", "2:03", " /100"], ["Source", "1", " test swim"]], "Your course fine-tunes itself after your first block.")}
             ${courseCard(false)}`
          : `<div class="sync-sim"><i></i><span>Waiting for your watch to sync the test swim. <button type="button" class="link-btn" data-act="sync-sim" style="padding:0 2px">Simulate sync (demo)</button></span></div>`}`;
    }

    if (mode === "self") {
      const s = state.self;
      const sp = s.time / (s.dist / 100);
      h += `
        <div class="sound-head"><p class="kicker k-cap">Sounding</p><h2>Your best recent swim</h2>
          <p class="dim">Enter your best recent continuous pool swim — the more accurate, the better your course.</p></div>
        <div class="sr-grid">
          <section class="card field"><span class="field-label">Longest non-stop</span>
            <div class="mini-stepper"><button type="button" data-act="sr-dist" data-dir="-1" aria-label="Less">−</button><output>${fmt(s.dist)}<small> m</small></output><button type="button" data-act="sr-dist" data-dir="1" aria-label="More">+</button></div></section>
          <section class="card field"><span class="field-label">Time for it</span>
            <div class="mini-stepper"><button type="button" data-act="sr-time" data-dir="-1" aria-label="Faster">−</button><output>${mmss(s.time)}</output><button type="button" data-act="sr-time" data-dir="1" aria-label="Slower">+</button></div></section>
        </div>
        <section class="card field">
          <span class="field-label">When was that?</span>
          <div class="sr-when">${["This week", "2 weeks ago", "This month", "Older"].map((w) => `<button type="button" class="${s.when === w ? "on" : ""}" data-act="sr-when" data-v="${w}">${w}</button>`).join("")}</div>
          <p class="field-foot mono" style="margin:0">Pace · ${mmss(sp)} /100 m</p>
        </section>
        ${courseCard(true)}
        <p class="tiny dim" style="margin:0 4px">Your first session is a short check-in set, so your course can tune itself to how you swim today.</p>`;
    }
    $("#s-result").innerHTML = h;
  }

  /* ───────────── 3 · Agon home ───────────── */
  function timelineHtml(tl, animate) {
    const pct = (d) => (d / tl.span) * 100;
    const t = pct(tl.today);
    const T = 1.3; // draw duration (s)
    return `<div class="timeline ${animate ? "anim" : ""}" role="img" aria-label="Forecast timeline, today at day ${tl.today}">
      <div class="tl-line"></div>
      ${tl.band ? `<div class="tl-band" style="left:${pct(tl.band.from)}%;width:${pct(tl.band.to - tl.band.from)}%"><span>${tl.band.text}</span></div>` : ""}
      <div class="tl-fc" style="left:${t}%"></div>
      <div class="tl-fill" style="width:${t}%"></div>
      <div class="tl-head" style="left:${t}%"></div>
      ${tl.pts.map((p) => `<div class="tl-pt ${p.cls} ${p.above ? "above" : ""}" style="left:${pct(p.d)}%;--pd:${((p.d / tl.today) * T).toFixed(2)}s"><i></i>${p.l ? `<label><b>${p.l}</b>${p.sub}</label>` : ""}</div>`).join("")}
      <div class="tl-today" style="left:${t}%"><label>Today</label></div>
    </div>`;
  }
  function structHtml(s) {
    const tot = s.segments.reduce((a, g) => a + g.m, 0);
    const w = s.segments.map((g) => `${((g.m / tot) * 100).toFixed(1)}fr`);
    return `<div class="struct" aria-label="Course structure">
      <div class="struct-bar" style="--w1:${w[0]};--w2:${w[1]};--w3:${w[2]}">${s.segments.map((g) => `<i class="${g.key}"></i>`).join("")}</div>
      <div class="struct-labels">${s.segments.map((g) => `<div><b>${g.name}</b><span>${fmt(g.m)} m</span></div>`).join("")}</div></div>`;
  }
  function warnHtml(d, where) {
    if (!state.warnOn) return "";
    if (state.load === "clear") return `<div class="clear-line"><i></i>Your other workouts look light. Nothing to flag today.</div>`;
    return `<div class="warn-banner" role="note">
      <div class="w-top"><span class="w-ico">!</span><p><b>${d.warn.title}</b>${d.warn.body} <span class="mono tiny">Soft warning · you decide.</span></p></div>
      <div class="w-actions">
        <button type="button" data-act="keep-swim">Keep swim</button>
        <button type="button" data-act="skip">Skip · recovery</button>
        ${where === "session" ? `<button type="button" data-act="adjust">Adjust</button>` : ""}
      </div></div>`;
  }
  function choreState() {
    if (state.skipped) return { t: "Skipped · rest", c: "done" };
    if (state.synced) return { t: "Done · synced", c: "done" };
    if (state.choreDone) return { t: state.adjusted ? "Done · adjusted" : "Done", c: "done" };
    return { t: "Due today", c: "" };
  }
  const passDots = (n) => `<span class="pass-dots">${[0, 1, 2].map((i) => `<i class="${i < n ? "" : "off"}"></i>`).join("")}</span>`;

  function renderHome() {
    const d = clockData();
    const s = d.session;
    const need = d.ms.dist - BASE.cap;
    const pct = Math.max(0, Math.min(100, ((d.capacity - BASE.cap) / need) * 100));
    const gap = d.ms.dist - d.capacity;
    const cs = choreState();
    const g = d.game;
    const toNext = g.floor + g.cost - g.arete;
    const cols = d.rungs.map((r, i) => (i ? "1fr auto" : "auto")).join(" ");

    $("#s-home").innerHTML = `
      <div class="prog-title">
        <div>
          <p class="kicker">Agon · Pool swim</p>
          <h1>1,200 m in 24:00</h1>
          <div class="chips"><span class="chip">${d.week}</span><span class="chip">3×/week</span><span class="chip">Mon · Wed · Sat</span></div>
        </div>
      </div>

      <section class="card cap-card ms-card" aria-label="Next milestone">
        <div class="ms-top">
          <div>
            <span class="layer-tag cap">Next milestone</span>
            <p class="ms-name">${d.ms.name}<small>${d.ms.spec}</small></p>
          </div>
          <div class="ms-when"><b>${d.ms.date}</b><span>${d.ms.rel}</span></div>
        </div>
        <div class="rungs" style="grid-template-columns:${cols}" role="img" aria-label="Ladder: ${d.rungs.map((r) => r.v).join(", ")} metres">
          ${d.rungs.map((r, i) => `${i ? `<div class="rung-line ${r.c === "done" ? "done" : d.rungs[i - 1].c === "done" ? "dash" : ""}"></div>` : ""}<div class="rung ${r.c}"><i></i><b>${r.v}</b><span>${r.s}</span></div>`).join("")}
        </div>
        <div class="evidence-bar">
          <div class="bar flat"><i style="width:${pct}%"></i></div>
          <div class="labels"><span>1,000 start</span><span>longest <b>${fmt(d.capacity)} m</b></span><span>${fmt(d.ms.dist)}</span></div>
        </div>
        <div class="ms-foot">
          <p><b>${gap} m</b> to go · ${d.block.text}</p>
          <button type="button" class="link-btn" data-act="delay" style="padding:2px 4px">Delay trial</button>
        </div>
      </section>

      <section class="card cap-card fc-card" aria-label="Goal forecast">
        <div class="fc-head">
          <div>
            <span class="layer-tag cap">Goal forecast</span>
            <p class="fc-date">${d.fc.now}<small>${d.fc.delta ? "was " + d.fc.planned : "as planned"}</small></p>
          </div>
          <span class="delta ${d.fc.delta ? "slip" : ""}">${d.fc.status}</span>
        </div>
        ${timelineHtml(d.tl, anim)}
        ${d.ledger ? `<div class="ledger"><span class="why">Why dates moved</span><p>${d.ledger.text}</p></div>` : ""}
        <div class="fc-foot">
          <p class="tiny dim">${d.ledger ? "" : d.fc.sub + " "}The forecast updates only when a trial moves.</p>
          <button type="button" class="chev-btn" data-go="forecast">Forecast detail<span aria-hidden="true">›</span></button>
        </div>
      </section>

      ${warnHtml(d, "home")}

      <section class="card course-card chore" aria-label="Today’s course">
        <div class="chore-top">
          <div>
            <span class="layer-tag cap">Today’s course · ${d.today}</span>
            <h3>${s.title}<small>${s.sub} · ${fmt(s.distance)} m · ${s.est}</small></h3>
          </div>
          <span class="chore-state ${cs.c}">${cs.t}</span>
        </div>
        ${structHtml(s)}
        <p class="focus"><b>Focus</b>${s.focus}</p>
        <div class="chore-actions">
          <button type="button" class="btn primary" data-go="session" data-tab="${state.synced ? "session" : "course"}">${state.synced ? "Review swim" : state.choreDone || state.skipped ? "View course" : "Open today’s course"}</button>
          <button type="button" class="btn" data-act="skip" ${state.choreDone || state.skipped || state.synced ? "disabled" : ""}>Skip</button>
        </div>
      </section>

      <div class="toggle-row">
        <div><h4>Soft warning on heavy days</h4><p>Reads badminton, strength and runs. It only flags; it never moves your swim.</p></div>
        <button class="toggle ${state.warnOn ? "on" : ""}" type="button" data-act="toggle-warn" aria-pressed="${state.warnOn}" aria-label="Soft warning on heavy other load"><span></span></button>
      </div>

      <button type="button" class="odyssey-card game-only" data-go="odyssey" aria-label="Your Odyssey">
        <div><p>Streak</p><strong>${g.streak}<small> wk</small></strong><span>weeks in a row</span></div>
        <div><p>Areté</p><strong>${fmt(g.arete)}</strong><span>progress points</span></div>
        <div><p>Depth</p><strong>${g.depth}</strong><span>${toNext} to Depth ${g.depth + 1}</span></div>
      </button>

      <button type="button" class="link-btn center" data-act="rules">How your dates work</button>`;
  }

  /* ───────────── 4 · Today · Session | Course ───────────── */
  const hrSeries = (rows) => {
    // 15 s grid; heart rate lags toward each row's average with a gentle drift and ripple.
    const out = [];
    let hr = 98, t = 0;
    rows.forEach((r, ri) => {
      const n = Math.max(2, Math.round(r.sec / 15));
      for (let i = 0; i < n; i++, t += 15) {
        const target = r.hr + (i / n) * 5 + Math.sin((t + ri * 40) / 38) * 2.4;
        hr += (target - hr) * (1 - Math.exp(-15 / 55));
        out.push([t, hr, r.seg]);
      }
    });
    return out;
  };
  function hrChartHtml(act, animate) {
    const ser = hrSeries(act.rows);
    const W = 326, H = 150, L = 26, R = 6, T = 22, B = 22;
    const tmax = ser[ser.length - 1][0] + 15;
    const lo = 90, hi = 170;
    const x = (t) => L + (t / tmax) * (W - L - R);
    const y = (v) => T + (1 - (v - lo) / (hi - lo)) * (H - T - B);
    const pts = ser.map((p) => [x(p[0]), y(p[1])]);
    const path = "M" + pts.map((p) => p.map((n) => n.toFixed(1)).join(" ")).join(" L");
    const area = `${path} L${x(tmax - 15).toFixed(1)} ${H - B} L${L} ${H - B} Z`;
    // segment bands
    const bands = [0, 1, 2].map((sg) => {
      const idx = ser.filter((p) => p[2] === sg).map((p) => p[0]);
      const a = idx[0], b = idx[idx.length - 1] + 15;
      return { a, b, name: ["Warm-up", "Main", "Cool-down"][sg], sg };
    });
    const avg = Math.round(ser.reduce((s, p) => s + p[1], 0) / ser.length);
    const mx = ser.reduce((m, p) => (p[1] > m[1] ? p : m), ser[0]);
    const mm = Math.round(tmax / 60);
    return {
      avg, max: Math.round(mx[1]),
      html: `<svg viewBox="0 0 ${W} ${H}" class="hr-svg ${animate ? "anim" : ""}" role="img" aria-label="Heart rate across the swim, average ${avg} beats per minute, peak ${Math.round(mx[1])}">
        <defs><linearGradient id="hrFill" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="var(--accent)" stop-opacity="0.32"/><stop offset="1" stop-color="var(--accent)" stop-opacity="0"/></linearGradient></defs>
        ${bands.map((b) => `<rect class="hr-band b${b.sg}" x="${x(b.a).toFixed(1)}" y="${T - 8}" width="${(x(b.b) - x(b.a)).toFixed(1)}" height="${H - T - B + 8}"/>`).join("")}
        ${[100, 130, 160].map((v) => `<line class="hr-grid" x1="${L}" x2="${W - R}" y1="${y(v)}" y2="${y(v)}"/><text class="hr-ax" x="${L - 5}" y="${y(v) + 3}" text-anchor="end">${v}</text>`).join("")}
        <path class="hr-area" d="${area}" fill="url(#hrFill)"/>
        <path class="hr-line" d="${path}" pathLength="1"/>
        <circle class="hr-max" cx="${x(mx[0]).toFixed(1)}" cy="${y(mx[1]).toFixed(1)}" r="3.6"/>
        ${bands.map((b) => `<text class="hr-band-l" x="${((x(b.a) + x(b.b)) / 2).toFixed(1)}" y="${T - 12}" text-anchor="middle">${b.name}</text>`).join("")}
        <text class="hr-ax" x="${L}" y="${H - 6}">0</text>
        <text class="hr-ax" x="${W - R}" y="${H - 6}" text-anchor="end">${mm} min</text>
      </svg>`,
    };
  }
  function renderSessionTab(d) {
    const act = d.act;
    if (!state.synced) {
      return `
      <section class="card wait-card">
        <div class="wait-ring" aria-hidden="true"><i></i><i></i><i></i></div>
        <h3>Your swim data lands here after sync</h3>
        <p class="dim small">Heart rate, pace, SWOLF and laps appear once your watch syncs today’s pool swim. Your course is waiting in the Course tab.</p>
        <button type="button" class="btn" data-act="sync-swim" style="margin-top:4px">Simulate sync (demo)</button>
      </section>`;
    }
    const rows = act.rows;
    const dist = rows.reduce((a, r) => a + r.dist, 0);
    const sec = rows.reduce((a, r) => a + r.sec, 0);
    const hr = hrChartHtml(act, anim);
    const paceSer = rows.flatMap((r) => Array(Math.max(1, r.dist / 100)).fill(r.ps));
    const swolfSer = rows.flatMap((r) => Array(Math.max(1, r.dist / 100)).fill(0).map((_, i) => r.swolf + ((i * 7 + r.dist) % 3) - 1));
    const avgPace = Math.round(rows.filter((r) => r.pace !== "—").reduce((a, r) => a + r.ps * r.dist, 0) / rows.filter((r) => r.pace !== "—").reduce((a, r) => a + r.dist, 0));
    const avgSwolf = Math.round(rows.reduce((a, r) => a + r.swolf * r.dist, 0) / dist);
    const segName = ["Warm-up", "Main set", "Cool-down"];
    let lastSeg = -1;
    const tr = rows.map((r) => {
      const head = r.seg !== lastSeg ? `<tr class="seg-row-h"><td colspan="6">${segName[r.seg]}</td></tr>` : "";
      lastSeg = r.seg;
      return `${head}<tr><td>${r.name}</td><td>${fmt(r.dist)}</td><td>${mmss(r.sec)}</td><td>${r.pace}</td><td>${r.hr}</td><td>${r.swolf}</td></tr>`;
    }).join("");
    return `
      <div class="sync-strip"><i></i><span>${act.synced} · matched to today’s course</span></div>

      <section class="card sess-kpis" aria-label="Swim summary">
        <div><p>Distance</p><strong>${fmt(dist)}<small> m</small></strong></div>
        <div><p>Time</p><strong>${mmss(sec)}</strong></div>
        <div><p>Avg pace</p><strong>${mmss(avgPace)}<small> /100</small></strong></div>
      </section>

      <section class="card cap-card" aria-label="Heart rate">
        <div class="layer-head"><span class="layer-tag cap">Heart rate</span><span class="mono tiny dim">avg ${hr.avg} · peak ${hr.max} bpm</span></div>
        <div class="hr-chart">${hr.html}</div>
        <p class="tiny dim" style="margin:6px 0 0">Demo data · rises through the main set and settles in the cool-down.</p>
      </section>

      <div class="spark-pair">
        <section class="card cap-card">
          <div class="layer-head"><span class="layer-tag cap">Pace</span><span class="mono tiny dim">per 100 m</span></div>
          <p class="spark-val">${mmss(avgPace)}<small> avg</small></p>
          ${sparkSvg(paceSer.map((v) => -v))}
        </section>
        <section class="card cap-card">
          <div class="layer-head"><span class="layer-tag cap">SWOLF</span><span class="mono tiny dim">per 100 m</span></div>
          <p class="spark-val">${avgSwolf}<small> avg</small></p>
          ${sparkSvg(swolfSer.map((v) => -v), "alt")}
        </section>
      </div>

      <section class="card cap-card laps" aria-label="Laps">
        <div class="layer-head"><span class="layer-tag cap">Laps</span><span class="mono tiny dim">demo data</span></div>
        <div class="laps-scroll"><table>
          <thead><tr><th>Set</th><th>m</th><th>Time</th><th>/100</th><th>HR</th><th>SWOLF</th></tr></thead>
          <tbody>${tr}</tbody>
        </table></div>
        <p class="dim small" style="margin:8px 0 0">${act.note}</p>
      </section>`;
  }
  function renderCourseTab(d) {
    const s = d.session;
    const done = state.choreDone || state.synced;
    const segs = s.segments.map((seg, i) => {
      const dn = state.segDone[i] || done;
      return `<section class="card seg-card ${seg.key === "main" ? "main" : ""} ${dn ? "done" : ""}">
        <div class="seg-head">
          <button type="button" class="seg-check" data-act="seg" data-i="${i}" aria-label="Mark ${seg.name} done" aria-pressed="${dn}"><svg viewBox="0 0 16 16"><path d="M3 8.5l3.2 3.2L13 4.8"/></svg></button>
          <p class="seg-title">${seg.name}<small>${seg.min}</small></p>
          <div class="seg-tot">${fmt(seg.m)} m<small>${seg.sets.length} set${seg.sets.length > 1 ? "s" : ""}</small></div>
        </div>
        <ul class="sets">${seg.sets.map((st) => `<li>
          <span class="reps">${st.reps}</span>
          <span class="desc">${st.desc}<span class="note">${st.note}</span></span>
          <span class="tgt">${st.pace !== "—" ? `<b>${st.pace}</b> /100<br>` : ""}rest ${st.rest}</span></li>`).join("")}</ul>
      </section>`;
    }).join("");
    return `
      <section class="card sess-hero">
        <div class="sess-meta">
          <div><p>Distance</p><strong>${fmt(s.distance)} m</strong></div>
          <div><p>Est. time</p><strong>${s.est}</strong></div>
          <div><p>Main pace</p><strong>${s.pace}<small class="dim" style="font-size:11px"> /100</small></strong></div>
        </div>
        ${state.adjusted ? `<span class="chip warm" style="width:fit-content">Adjusted · ${state.adjusted}</span>` : ""}
        <p class="focus"><b>Focus</b>${s.focus}</p>
      </section>

      ${warnHtml(d, "session")}
      ${segs}

      <section class="card why-card">${s.why}</section>

      <div class="match-note ${done ? "done" : ""}"><i></i>
        <span>${state.synced
          ? `Matched to your watch swim. Open the Session tab for heart rate, pace and laps${gameTag(" · +120 Areté")}.`
          : state.choreDone
            ? `Marked done by you. A matching watch swim can still replace this later${gameTag(" for the higher Areté")}.`
            : `Waiting for your next synced pool swim — it will match this course automatically${gameTag(" · Areté awarded on match")}. <button type="button" class="link-btn" data-act="sync-swim" style="padding:0 2px">Simulate sync (demo)</button>`}</span></div>`;
  }
  function renderSession() {
    const d = clockData();
    const s = d.session;
    const tab = state.sessTab;
    $("#s-session").innerHTML = `
      <div class="sess-title">
        <span class="layer-tag cap">${s.kicker}</span>
        <h1>${s.title}</h1>
        <p class="sub">${s.sub}</p>
      </div>
      <div class="seg-tabs" role="tablist" aria-label="Today view">
        <button type="button" role="tab" aria-selected="${tab === "session"}" class="${tab === "session" ? "on" : ""}" data-act="sess-tab" data-v="session">Session</button>
        <button type="button" role="tab" aria-selected="${tab === "course"}" class="${tab === "course" ? "on" : ""}" data-act="sess-tab" data-v="course">Course</button>
      </div>
      <div class="tab-pane">${tab === "session" ? renderSessionTab(d) : renderCourseTab(d)}</div>`;

    const done = state.choreDone || state.skipped || state.synced;
    if (tab !== "course" || state.synced) { ctaBar.innerHTML = ""; return; }
    ctaBar.innerHTML = state.skipped
      ? `<button type="button" class="btn block" data-act="undo-skip">Undo skip<small>${state.skipped} · counts as rest</small></button>`
      : `<button type="button" class="btn primary block" data-act="mark-done" ${state.choreDone ? "disabled" : ""}>${state.choreDone ? "Done" : "Mark session done"}<small>${state.choreDone ? "Dates and Streak unaffected" : "You confirm this swim"}</small></button>
         <div class="row"><button type="button" class="btn" data-act="adjust" ${done ? "disabled" : ""}>Adjust</button><button type="button" class="btn" data-act="skip" ${done ? "disabled" : ""}>Skip</button></div>`;
  }

  /* ───────────── 8 · Forecast detail ───────────── */
  function buildCalendar(d) {
    const slip = state.clock === "slipped";
    const step = state.stepDown;
    const today = d.todayDate;
    const trials = new Map();
    trials.set(dkey(new Date(2026, 9, 24)), { kind: "pass", n: "T1" });
    let last;
    if (!slip) { trials.set(dkey(new Date(2026, 9, 31)), { kind: "next", n: "T2" }); last = new Date(2026, 9, 31); }
    else {
      trials.set(dkey(new Date(2026, 9, 31)), { kind: "miss", n: "T2" });
      if (step) { trials.set(dkey(new Date(2026, 10, 4)), { kind: "next", n: "Step" }); trials.set(dkey(new Date(2026, 10, 11)), { kind: "next", n: "T2" }); last = new Date(2026, 10, 11); }
      else { trials.set(dkey(new Date(2026, 10, 4)), { kind: "next", n: "T2" }); last = new Date(2026, 10, 4); }
    }
    const weeks = [];
    for (let cur = new Date(START); cur <= last; cur = addDays(cur, 7)) {
      const row = [];
      for (let i = 0; i < 7; i++) {
        const dt = addDays(cur, i);
        let cls = "rest", mark = "";
        const pr = trials.get(dkey(dt));
        if (pr) { cls = `trial ${pr.kind}`; mark = pr.n; }
        else if ([1, 3, 6].includes(dt.getDay()) && dt <= last) {
          cls = dt < today ? "done" : dt.getTime() === today.getTime() ? "today" : "sched";
        }
        if (dt.getTime() === today.getTime() && !pr) cls = "today";
        row.push({ dt, cls, mark });
      }
      weeks.push(row);
    }
    return weeks;
  }
  function renderForecast() {
    const d = clockData();
    const weeks = buildCalendar(d);
    const slip = state.clock === "slipped";
    const tl = detailTl(d);
    const rows = slip
      ? [
          ["Sounding", "Oct 12", "Starting depth 1,000 m", "done"],
          ["Trial 1", "Oct 24", "1,100 m · passed", "done"],
          ["Trial 2", "Oct 31", "1,120 m of 1,200 m · not passed", "miss"],
          ...(state.stepDown
            ? [["Step", "Nov 4", "1,150 m non-stop ≤ 23:00", "next"], ["Trial 2 · retry", "Nov 11", "1,200 m ≤ 24:00", "next"]]
            : [["Trial 2 · retry", "Nov 4", "1,200 m ≤ 24:00", "next"]]),
        ]
      : [
          ["Sounding", "Oct 12", "Starting depth 1,000 m", "done"],
          ["Trial 1", "Oct 24", "1,100 m · passed", "done"],
          ["Trial 2", "Oct 31", "1,200 m ≤ 24:00", "next"],
        ];
    const movers = slip
      ? [
          ["Trial 2 retry", "If it isn’t passed, the next attempt is at least 48 h later and the forecast moves with it."],
          ["Smaller step", "You can swap in a 1,150 m step first. That moves the goal to Nov 11."],
          ["Skipping or shortening", "Never moves your dates."],
        ]
      : [
          ["Trial 2 not cleared", "The next attempt is at least 48 h later. The forecast would move to about Wed Nov 4."],
          ["Delaying a trial", "Moves Trial 2 and the forecast by the same number of days."],
          ["Skipping or shortening", "Never moves your dates. A week with 2 of 3 sessions still counts."],
        ];
    $("#s-forecast").innerHTML = `
      <div class="fd-hero">
        <p class="kicker k-cap">Goal forecast · 1,200 m ≤ 24:00</p>
        <p class="fd-date">${d.fc.now}</p>
        <div class="fd-row"><span class="delta ${d.fc.delta ? "slip" : ""}">${d.fc.status}</span><span class="dim small">${d.fc.delta ? "Originally " + d.fc.planned : "Same as the course you activated"}</span></div>
      </div>

      <section class="card cap-card" aria-label="Timeline">
        <div class="layer-head"><span class="layer-tag cap">Timeline</span><span class="mono tiny dim">Oct 12 → ${d.fc.now.split(" ").slice(1).join(" ")}</span></div>
        <div class="tl-wrap">${timelineHtml({ ...tl, band: slip ? null : tl.band }, anim)}</div>
        ${slip ? "" : `<p class="tiny dim" style="margin:6px 0 0">Shaded range: where the goal would land if Trial 2 needs one retry.</p>`}
      </section>

      <section class="card cap-card" aria-label="Calendar">
        <div class="layer-head"><span class="layer-tag cap">Course calendar</span><span class="mono tiny dim">Mon · Wed · Sat</span></div>
        <div class="cal">
          <div class="cal-h"><span></span>${["M", "T", "W", "T", "F", "S", "S"].map((l) => `<span>${l}</span>`).join("")}</div>
          ${weeks.map((w, wi) => `<div class="cal-r"><b>Wk ${wi + 1}</b>${w.map((c, ci) => `<i class="cd ${c.cls}" style="--n:${wi * 7 + ci}" title="${label(c.dt)}">${c.mark || c.dt.getDate()}</i>`).join("")}</div>`).join("")}
        </div>
        <ul class="cal-key">
          <li><i class="cd done"></i>Session done</li>
          <li><i class="cd sched"></i>Scheduled</li>
          <li><i class="cd trial pass"></i>Trial cleared</li>
          <li><i class="cd trial next"></i>Next trial</li>
          ${slip ? `<li><i class="cd trial miss"></i>Not cleared</li>` : ""}
        </ul>
      </section>

      <section class="card cap-card" aria-label="Milestones">
        <div class="layer-head"><span class="layer-tag cap">Milestones</span><span class="mono tiny dim">${rows.length} on the course</span></div>
        <ul class="ms-list">${rows.map((r) => `<li class="${r[3]}"><span class="node"></span><div><b>${r[0]}</b><p>${r[2]}</p></div><span class="when mono">${r[1]}</span></li>`).join("")}</ul>
      </section>

      <section class="card cap-card" aria-label="What moves this date">
        <div class="layer-head"><span class="layer-tag cap">What moves this date</span></div>
        <ul class="movers">${movers.map((m) => `<li><b>${m[0]}</b><span>${m[1]}</span></li>`).join("")}</ul>
      </section>

      <p class="tiny dim" style="margin:0 4px">The forecast starts from your Sounding and updates after each trial. Everyday sessions, skips and heavy days don’t change it.</p>`;
  }

  /* ───────────── 7 · Odyssey ───────────── */
  const KLEOS_ICON = {
    wave: `<path d="M12 28q4-5 8 0t8 0t8 0"/><path d="M14 20q3.5-4 7 0t7 0"/>`,
    ruler: `<path d="M12 34V14m0 0l-3 3m3-3l3 3M20 34h16M20 26h12M20 18h8"/>`,
    steady: `<path d="M10 30c4-8 7-8 11 0s7 8 11 0 4-6 6-6"/>`,
    goal: `<circle cx="24" cy="24" r="10"/><circle cx="24" cy="24" r="4"/>`,
    voyage: `<path d="M24 12v22M24 12l9 10H24M14 34h20"/>`,
    four: `<path d="M12 33l7-10 6 6 11-15"/>`,
  };
  const kleosTile = (k) => `<${k.on ? `button type="button" data-act="kleos-open" data-k="${k.id}"` : "div"} class="k-tile ${k.on ? "on" : "off"}" ${k.on ? `aria-label="${k.name}, unlocked ${k.when}"` : `aria-label="${k.name}, locked"`}>
      <span class="k-ico"><svg viewBox="0 0 48 48" aria-hidden="true"><circle cx="24" cy="24" r="21"/>${KLEOS_ICON[k.icon]}</svg></span>
      <b>${k.name}</b><span>${k.sub}</span><em class="mono">${k.on ? k.when : "Locked"}</em></${k.on ? "button" : "div"}>`;

  function renderOdyssey() {
    const d = clockData();
    const plan = state.clock === "plan";
    const g = d.game;
    const toNext = g.floor + g.cost - g.arete;
    const depthPct = ((g.arete - g.floor) / g.cost) * 100;
    const step = state.stepDown;

    const ladder = plan
      ? [
          { c: "done", t: "1,000 m", p: "Sounding · from your pool history", w: "Oct 9" },
          { c: "done", t: "Trial 1 · 1,100 m", p: "Passed non-stop · 22:10", w: "Oct 24" },
          { c: "next", t: "Trial 2 · 1,200 m ≤ 24:00", p: "5 days out · forecast on plan", w: "Oct 31" },
        ]
      : [
          { c: "done", t: "1,000 m", p: "Sounding · from your pool history", w: "Oct 9" },
          { c: "done", t: "Trial 1 · 1,100 m", p: "Passed non-stop · 22:10", w: "Oct 24" },
          { c: "", t: "Trial 2 · 1,200 m", p: "Not passed · 1,120 m non-stop", w: "<s>Oct 31</s>" + (step ? "Nov 11" : "Nov 4") },
          ...(step ? [{ c: "next", t: "Step · 1,150 m", p: "Added by you after the attempt", w: "Nov 4" }] : []),
        ];
    if (!plan && !step) ladder[2].c = "next";
    const ledgerRows = plan
      ? [["Oct 25", "Full week 2", "+50"], ["Oct 24", "Trial 1 · attempt, pass, longest swim", "+400"], ["Oct 21", "Session · synced, full course", "+120"], ["Oct 19", "Session · synced, full course", "+120"], ["Oct 17", "Session · synced, full course", "+120"]]
      : [["Nov 1", "Full week 3", "+50"], ["Oct 31", "Trial 2 · attempt", "+100"], ["Oct 28", "Session · synced, full course", "+120"], ["Oct 26", "Session · synced, full course", "+120"], ["Oct 25", "Full week 2", "+50"]];
    const weeks = plan
      ? [{ n: "Wk 1", dots: ["f", "h", "f"], t: "Full" }, { n: "Wk 2", dots: ["f", "f", "f"], t: "Full" }, { n: "Wk 3", dots: ["p", "p", "p"], t: "In progress", cur: true }]
      : [{ n: "Wk 2", dots: ["f", "f", "f"], t: "Full" }, { n: "Wk 3", dots: ["f", "f", "f"], t: "Full" }, { n: "Wk 4", dots: ["p", "p", "p"], t: "In progress", cur: true }];
    const hab = plan
      ? { val: "5 of 5", dots: ["", "half", "", "", "", "trial"], l1: ["Shortened", "1 · counted 0.6"], l2: ["Skipped", "0"] }
      : { val: "2 of 2", dots: ["", "", "trial"], l1: ["Trial attempt", "1 · logged"], l2: ["Skipped", "0"] };
    const vol = plan
      ? { v: "1,100", bar: 50, l1: ["Next trial gap", "100 m"], l2: ["Week 2 distance", "5,050 / 5,100 m"] }
      : { v: "1,120", bar: step ? 80 : 60, l1: ["Next step gap", step ? "30 m" : "80 m"], l2: ["Week 3 distance", "5,320 / 5,400 m"] };
    const eff = plan
      ? { v: "1.14", d: "+0.06 vs block 1", band: "Improving", good: true, spark: [1.08, 1.09, 1.11, 1.12, 1.14], l1: ["Pace fade · Trial 1", "1.6%"], l2: ["Matched intervals", "14 · 5 sessions"] }
      : { v: "1.15", d: "+0.07 vs block 1", band: "Eases late", good: false, spark: [1.09, 1.11, 1.12, 1.14, 1.15], l1: ["Pace fade · Trial 2", "7.4%"], l2: ["Matched intervals", "19 · 7 sessions"] };
    const focus = plan
      ? { f: "Even splits", t: "Pace eased only 1.6% on Trial 1. Hold 2:00 through the third 400 on Mon and Wed." }
      : { f: "Build the long swim", t: "Longest non-stop is 1,120 m against a 1,200 m trial, and pace eased 7.4% after 800 m." };
    const kleos = [
      { id: "first", on: true, name: "First Mark", sub: "Cleared Trial 1 · 1,100 m", when: "Oct 24", icon: "wave" },
      { id: "long", on: true, name: "Longest Swim", sub: "1,100 m non-stop, your best yet", when: "Oct 24", icon: "ruler" },
      { id: "voy", on: true, name: "First Voyage", sub: "Your first Agon session", when: "Oct 12", icon: "voyage" },
      { id: "steady", on: true, name: "Steady Course", sub: "Two weeks in a row", when: "Oct 25", icon: "steady" },
      { id: "goal", on: false, name: "Goal Swim", sub: "Clear Trial 2 · 1,200 m ≤ 24:00", icon: "goal" },
      { id: "four", on: false, name: "Four Weeks", sub: "Streak of four weeks", icon: "four" },
    ];
    const route = [1, 2, 3, 4, 5, 6, 7].map((n) => `<li class="${n < g.depth ? "done" : n === g.depth ? "now" : ""}"><i></i><b>${n}</b></li>`).join("");

    $("#s-odyssey").innerHTML = `
      <div class="pg-title"><p class="kicker">The Odyssey · your journey</p><h1>Odyssey</h1></div>

      <section class="card reward-card od-hero game-only" aria-label="Depth and Areté">
        <div class="od-top">
          <div><p class="k-bronze">Depth</p><p class="od-depth">${g.depth}</p></div>
          <div class="od-arete">
            <button type="button" class="info-btn" data-act="arete-info" aria-label="What is Areté?"><span class="k-bronze">Areté</span><i>i</i></button>
            <p class="od-points">${fmt(g.arete)}</p>
            <p class="dim tiny">progress points · lifetime</p>
          </div>
        </div>
        <ol class="route" aria-label="Depth route, you are at Depth ${g.depth}">${route}</ol>
        <div class="bar reward"><i data-w="${depthPct}" style="width:${depthPct}%"></i></div>
        <p class="tiny dim" style="margin:0">${toNext} Areté to Depth ${g.depth + 1} · a new route opens in your Odyssey.</p>
      </section>

      <section class="card cap-card" aria-label="Agon milestones">
        <div class="layer-head"><span class="layer-tag cap">Agon · Pool swim</span><span class="mono tiny dim">${d.fc.status}</span></div>
        <ul class="ladder-v">
          ${ladder.map((r) => `<li class="${r.c}"><span class="node"></span><div><b>${r.t}</b><p>${r.p}</p></div><span class="when">${r.w}</span></li>`).join("")}
        </ul>
        ${d.ledger ? `<div class="ledger" style="margin-top:12px"><span class="why">Why dates moved</span><p>${d.ledger.text}</p></div>` : ""}
      </section>

      <section class="card reward-card game-only" aria-label="Kleos">
        <div class="layer-head"><span class="layer-tag habit">Kleos</span><span class="mono tiny dim">${kleos.filter((k) => k.on).length} of ${kleos.length} unlocked</span></div>
        <div class="k-grid">${kleos.map(kleosTile).join("")}</div>
      </section>

      <section class="card reward-card game-only" aria-label="Streak">
        <div class="layer-head"><span class="layer-tag habit">Streak</span><span class="mono tiny dim">Mon–Sun</span></div>
        <div class="streak-big"><strong>${g.streak}</strong><span>weeks in a row</span></div>
        <div class="streak-weeks">${weeks.map((w) => `<div class="wk ${w.cur ? "cur" : ""}"><p>${w.n}</p><div class="dots">${w.dots.map((x) => `<i class="${x}"></i>`).join("")}</div><b>${w.t}</b></div>`).join("")}</div>
        <div class="streak-meta">
          <span>A week counts with <b>2 of 3</b> sessions</span>
          <span>Rest passes <b>${g.passes} of 3</b> ${passDots(g.passes)}</span>
          <span>Best <b>${g.best}</b></span>
        </div>
      </section>

      <section class="card reward-card game-only" aria-label="Areté history">
        <div class="layer-head"><span class="layer-tag habit">Areté · recent</span><span class="mono tiny dim">never goes down</span></div>
        <ul class="xp-ledger">${ledgerRows.map((r) => `<li><span class="d">${r[0]}</span><span>${r[1]}</span><b>${r[2]}</b></li>`).join("")}</ul>
      </section>

      <div class="kicker" style="margin:6px 2px 0">Pool Agon scorecards · three, no combined score</div>
      <div class="score-grid">
        <section class="card score cap-card" aria-label="Consistency scorecard">
          <div class="score-top"><div><h3>Consistency</h3><p class="q">Am I showing up?</p></div><span class="band good">Steady</span></div>
          <div class="score-val"><strong>${hab.val}<small> sessions</small></strong><span>this block</span></div>
          <div class="chore-dots">${hab.dots.map((c) => `<i class="${c}"></i>`).join("")}</div>
          <div class="score-lines"><div><span>${hab.l1[0]}</span><b>${hab.l1[1]}</b></div><div><span>${hab.l2[0]}</span><b>${hab.l2[1]}</b></div></div>
        </section>
        <section class="card score cap-card" aria-label="Distance scorecard">
          <div class="score-top"><div><h3>Distance</h3><p class="q">Am I building capacity?</p></div><span class="band">${plan ? "On ramp" : "Building"}</span></div>
          <div class="score-val"><strong>${vol.v}<small> m</small></strong><span>longest non-stop</span></div>
          <div class="evidence-bar"><div class="bar flat"><i style="width:${vol.bar}%"></i></div><div class="labels"><span>1,000</span><span>next ${fmt(d.ms.dist)}</span></div></div>
          <div class="score-lines"><div><span>${vol.l1[0]}</span><b>${vol.l1[1]}</b></div><div><span>${vol.l2[0]}</span><b>${vol.l2[1]}</b></div></div>
        </section>
        <section class="card score cap-card" aria-label="Efficiency scorecard">
          <div class="score-top"><div><h3>Efficiency</h3><p class="q">Swimming smarter or fresher?</p></div><span class="band ${eff.good ? "good" : ""}">${eff.band}</span></div>
          <div class="score-val"><strong>${eff.v}<small> m / stroke</small></strong><span>${eff.d}</span></div>
          ${sparkSvg(eff.spark)}
          <div class="score-lines"><div><span>${eff.l1[0]}</span><b>${eff.l1[1]}</b></div><div><span>${eff.l2[0]}</span><b>${eff.l2[1]}</b></div></div>
          <p class="tiny dim" style="margin:0">Distance per stroke at matched pace (2:00 ±5%, 100 m+). SWOLF is secondary because glide can flatter it.</p>
        </section>
      </div>

      <section class="focus-strip" aria-label="Focus line">
        <span class="kicker k-cap">Next course focus</span>
        <span class="f">${focus.f}</span>
        <p>${focus.t}</p>
        <p><b>Scorecards inform emphasis.</b> They never gate or delay a trial.</p>
      </section>

      <div class="toggle-row">
        <div><h4>Hide Areté, Depth and Streak</h4><p>Milestones and scorecards stay. Nothing is lost; it’s just quiet.</p></div>
        <button class="toggle ${state.game ? "" : "on"}" type="button" data-act="toggle-game" aria-pressed="${!state.game}" aria-label="Hide the Odyssey layer"><span></span></button>
      </div>`;
  }

  /* ───────────── 5 · Kleos celebration ───────────── */
  function buildLaurel() {
    const cx = 110, cy = 112, R = 86, N = 10;
    const leaf = (a, r, rx, ry, i) => {
      const rad = (a * Math.PI) / 180;
      const x = cx + r * Math.cos(rad), y = cy + r * Math.sin(rad);
      return `<g transform="translate(${x.toFixed(1)} ${y.toFixed(1)}) rotate(${a.toFixed(1)})"><ellipse class="leaf" style="--i:${i}" rx="${rx}" ry="${ry}"/></g>`;
    };
    let g = "";
    const arc = (a1, a2, sweep) => {
      const r = R - 7, p = (a) => [cx + r * Math.cos((a * Math.PI) / 180), cy + r * Math.sin((a * Math.PI) / 180)];
      const s = p(a1), e = p(a2);
      return `<path class="stem" pathLength="1" d="M${s[0].toFixed(1)} ${s[1].toFixed(1)} A${r} ${r} 0 0 ${sweep} ${e[0].toFixed(1)} ${e[1].toFixed(1)}"/>`;
    };
    g += arc(98, 262, 1) + arc(82, -82, 0);
    for (let i = 0; i < N; i++) {
      const a = 105 + (i / (N - 1)) * 150;
      g += leaf(a, R, 4.8, 12.5, i) + leaf(180 - a, R, 4.8, 12.5, i);
      if (i < N - 1) {
        const a2 = a + 7.5;
        g += leaf(a2, R + 11, 3.4, 8.8, i + 0.5) + leaf(180 - a2, R + 11, 3.4, 8.8, i + 0.5);
      }
    }
    $("#kLaurel").innerHTML = g;
  }
  function buildBubbles() {
    const el = $("#kBubbles");
    let h = "";
    for (let i = 0; i < 16; i++) {
      const left = 6 + ((i * 53) % 88), size = 3 + ((i * 7) % 6), dur = 7 + ((i * 5) % 7), delay = -((i * 3.1) % 9);
      h += `<i style="left:${left}%;width:${size}px;height:${size}px;animation-duration:${dur}s;animation-delay:${delay}s"></i>`;
    }
    el.innerHTML = h;
  }
  function playKleos() {
    const game = state.game;
    $("#kKicker").textContent = game ? "Kleos unlocked" : "Milestone reached";
    $("#kTitle").textContent = game ? "First Mark" : "Trial 1 passed";
    kleosEl.classList.remove("play");
    void kleosEl.offsetWidth;
    kleosEl.classList.add("play");
    const el = $("#kArete");
    if (reduceMotion || !game) { el.textContent = "+400"; return; }
    el.textContent = "+0";
    const delay = 1250, dur = 1100;
    setTimeout(() => {
      const t0 = performance.now();
      (function tick(now) {
        if (state.screen !== "kleos") return;
        const t = Math.min(1, (now - t0) / dur);
        el.textContent = "+" + Math.round(400 * (1 - Math.pow(1 - t, 3)));
        if (t < 1) requestAnimationFrame(tick);
      })(t0);
    }, delay);
  }

  /* ───────────── 6 · Trial not passed · split chart ───────────── */
  function renderSplit() {
    const splits = [121, 120, 121, 121, 121, 120, 122, 121, 126, 131, 133, 135]; // s / 100 m; last is the 20 m remainder
    const W = 294, H = 120, L = 6, R = 6, T = 14, B = 22;
    const lo = 114, hi = 140;
    const x = (i) => L + (i * (W - L - R)) / (splits.length - 1);
    const y = (v) => T + ((v - lo) / (hi - lo)) * (H - T - B);
    const pts = splits.map((v, i) => [x(i), y(v)]);
    const path = "M" + pts.map((p) => p.map((n) => n.toFixed(1)).join(" ")).join(" L");
    const tgtY = y(120);
    $("#splitChart").innerHTML = `<svg viewBox="0 0 ${W} ${H}" role="img" aria-label="Pace per 100 m: steady at 2:01 until 800 m, then easing to about 2:13">
      <rect class="fade-zone" x="${x(7.5)}" y="${T - 6}" width="${W - R - x(7.5)}" height="${H - T - B + 12}" rx="4"/>
      <line class="tgt-line" x1="${L}" x2="${W - R}" y1="${tgtY}" y2="${tgtY}"/>
      <text x="${x(4.2)}" y="${tgtY - 5}">target 2:00</text>
      <text x="${W - R}" y="9" text-anchor="end">faster ↑</text>
      <path class="pace-line" d="${path}"/>
      ${pts.map((p, i) => `<circle class="pt ${i >= 8 ? "slow" : ""}" cx="${p[0].toFixed(1)}" cy="${p[1].toFixed(1)}" r="${i === 7 || i === pts.length - 1 ? 3.6 : 2.6}"/>`).join("")}
      <text x="${x(0)}" y="${y(121) + 15}">2:01</text>
      <text x="${x(11) - 22}" y="${y(135) + 15}">2:15</text>
      <text x="${x(7.5)}" y="${H - 6}" text-anchor="middle">800 m</text>
      <text x="${x(0)}" y="${H - 6}">100 m</text>
      <text x="${x(11)}" y="${H - 6}" text-anchor="end">1,120 m</text>
    </svg>`;
  }

  /* ───────────── Navigation / chrome ───────────── */
  function setCta() {
    const s = state.screen;
    let html = "";
    if (s === "create") html = `<button type="button" class="btn primary block" data-go="sounding">Chart my Agon<small>We’ll take a sounding of your recent pool swims</small></button>`;
    else if (s === "sounding-history") html = `<button type="button" class="btn primary block" data-act="activate">Activate Agon<small>Starting depth set ${gameTag("· +50 Areté · progress points")}</small></button>`;
    else if (s === "sounding-test") html = state.testPhase === "synced"
      ? `<button type="button" class="btn primary block" data-act="activate">Activate Agon<small>Test swim matched ${gameTag("· +150 Areté · progress points")}</small></button>`
      : `<button type="button" class="btn primary block" data-act="start-test">Start test swim<small>Open Swim on your watch · non-stop</small></button><button type="button" class="link-btn center" data-go="sounding-self">Enter a recent swim instead</button>`;
    else if (s === "sounding-self") html = `<button type="button" class="btn primary block" data-act="activate">Build my course<small>Your first session fine-tunes it</small></button>`;
    else if (s === "session") return; // renderSession owns it
    ctaBar.innerHTML = html;
  }

  function applyChrome() {
    const meta = SCREENS[state.screen];
    const chrome = meta.chrome !== false;
    phone.dataset.chrome = chrome ? "header" : "none";
    phone.dataset.tabs = meta.tabs ? "on" : "off";
    const hasCta = ["create", "sounding-history", "sounding-test", "sounding-self"].includes(state.screen)
      || (state.screen === "session" && state.sessTab === "course" && !state.synced);
    phone.dataset.cta = hasCta ? "on" : "off";
    ctaBar.classList.toggle("on", hasCta);
    if (chrome) {
      $("#hdrTitle").textContent = meta.title;
      $("#hdrSub").textContent = typeof meta.sub === "function" ? meta.sub() : meta.sub;
      $("#btnBack").style.visibility = meta.back ? "visible" : "hidden";
    }
    $$(".tab").forEach((t) => t.classList.toggle("active", t.dataset.go === meta.tab));
    $$("#flowList button").forEach((b) => b.classList.toggle("active", b.dataset.go === state.screen));
    kleosEl.classList.toggle("active", state.screen === "kleos");
    kleosEl.setAttribute("aria-hidden", state.screen === "kleos" ? "false" : "true");
  }

  function renderCurrent() {
    const sc = state.screen;
    if (sc === "create") renderCreate();
    if (sc.startsWith("sounding-")) renderResult();
    if (sc === "home") renderHome();
    if (sc === "session") renderSession();
    if (sc === "odyssey") renderOdyssey();
    if (sc === "forecast") renderForecast();
    if (sc === "fail") renderSplit();
    setCta();
    applyChrome();
  }

  function go(id, opts = {}) {
    id = ALIASES[id] || id;
    if (!SCREENS[id]) return;
    closeSheets();
    clearSoundTimers();
    state.screen = id;
    if (id === "session") {
      if (opts.tab) state.sessTab = opts.tab;
      else state.sessTab = state.synced ? "session" : "course";
    }
    $$(".screen").forEach((s) => s.classList.remove("active"));
    anim = true;
    renderCurrent();
    anim = false;
    if (SCREENS[id].el) $(`#${SCREENS[id].el}`).classList.add("active");
    scroll.scrollTop = 0;
    if (id === "kleos") playKleos();
    if (id === "sounding") startSounding();
    if (!opts.silent) history.replaceState(null, "", `#${id}`);
    $("#railStatus").textContent = RAIL_NOTES[id] || "";
  }

  const RAIL_NOTES = {
    create: "Intake needs distance, target time, horizon and sessions/week. Try 22:00 or 1,500 m to see the horizon note.",
    sounding: "Building state with a lead-line sounding. Auto-resolves to the route chosen in the rail after ~3.5 s.",
    "sounding-history": "Strong history: no test needed. The athlete just sees a starting point and a course.",
    "sounding-test": "Light history: one non-stop test swim. Use “Simulate sync (demo)” in the phone.",
    "sounding-self": "Self-entry: plain ask for the best recent continuous swim. First session becomes a check-in.",
    home: "Next milestone, animated goal forecast, today’s course. Flip clock / other load from the rail.",
    session: "Session | Course. Course opens from Agon; Session opens post-sync (rail control). Tab inside the phone anytime.",
    kleos: "Full-screen Kleos moment: laurel, ripples, Areté count-up. Respects reduced motion. Skippable.",
    fail: "Facts first, no shame. Dates move; Areté, Streak and Depth don’t. Pick retry or a smaller step.",
    odyssey: "Depth, Areté, Kleos and Streak above; three pool scorecards below. Tap First Mark to replay the moment.",
    forecast: "Forecast detail: timeline, course calendar, milestones and what moves the date.",
  };

  function syncRail() {
    $$("[data-clock]").forEach((b) => b.classList.toggle("active", b.dataset.clock === state.clock));
    $$("[data-load]").forEach((b) => b.classList.toggle("active", b.dataset.load === state.load));
    $$("[data-route]").forEach((b) => b.classList.toggle("active", b.dataset.route === state.route));
    $$("[data-synced]").forEach((b) => b.classList.toggle("active", (b.dataset.synced === "on") === state.synced));
    $$("[data-game-btn]").forEach((b) => b.classList.toggle("active", (b.dataset.gameBtn === "on") === state.game));
    $$("[data-theme-btn]").forEach((b) => b.classList.toggle("active", b.dataset.themeBtn === state.theme));
  }
  function setClock(c) {
    state.clock = c;
    state.choreDone = false; state.skipped = null; state.adjusted = null; state.segDone = [false, false, false]; state.synced = false;
    if (c === "plan") state.stepDown = false;
    syncRail();
    renderCurrent();
  }
  function setLoad(l) { state.load = l; syncRail(); renderCurrent(); }
  function setGame(on) {
    state.game = on;
    document.body.dataset.game = on ? "on" : "off";
    syncRail();
    renderCurrent();
  }
  function setTheme(t) {
    state.theme = t;
    document.documentElement.dataset.theme = t;
    syncRail();
  }
  function setSynced(on) {
    state.synced = on;
    syncRail();
    go("session", { tab: on ? "session" : "course" });
  }

  /* ───────────── Actions ───────────── */
  const stepTime = (v, dir) => Math.max(60, v + dir * 30);
  const ACTIONS = {
    dist: (el) => { state.create.dist = +el.dataset.v; renderCreate(); },
    weeks: (el) => { state.create.weeks = +el.dataset.v; renderCreate(); },
    spw: (el) => { state.create.spw = +el.dataset.v; renderCreate(); },
    "sr-dist": (el) => { state.self.dist = Math.max(200, Math.min(2000, state.self.dist + 100 * +el.dataset.dir)); renderResult(); },
    "sr-time": (el) => { state.self.time = Math.max(120, state.self.time + 15 * +el.dataset.dir); renderResult(); },
    "sr-when": (el) => { state.self.when = el.dataset.v; renderResult(); },
    "sync-sim": () => { state.testPhase = "synced"; renderCurrent(); toast("Matched your pool swim from this morning as the test."); },
    "start-test": () => toast("Test queued. Start a pool swim on your watch and swim non-stop."),
    activate: () => {
      state.clock = "plan"; state.stepDown = false; state.synced = false;
      syncRail();
      go("home");
      toast(state.game ? "Agon active · starting depth set · +50 Areté" : "Agon active · starting depth set");
    },
    "toggle-warn": () => { state.warnOn = !state.warnOn; renderCurrent(); },
    "toggle-game": () => setGame(!state.game),
    "keep-swim": () => toast("Keeping the swim. Nothing changes on your course."),
    rules: () => openSheet("sheetRules"),
    "arete-info": () => openSheet("sheetArete"),
    delay: () => openSheet("sheetDelay"),
    skip: () => openSheet("sheetSkip"),
    adjust: () => openSheet("sheetAdjust"),
    seg: (el) => { const i = +el.dataset.i; state.segDone[i] = !state.segDone[i]; renderSession(); },
    "sess-tab": (el) => { state.sessTab = el.dataset.v; anim = true; renderCurrent(); anim = false; },
    "sync-swim": () => {
      state.synced = true; state.sessTab = "session";
      syncRail();
      anim = true; renderCurrent(); anim = false;
      toast(state.game ? "Swim synced · matched to today’s course · +120 Areté" : "Swim synced · matched to today’s course");
    },
    "mark-done": () => {
      state.choreDone = true;
      renderCurrent();
      toast(state.game ? "Done · +70 Areté. Dates and Streak unaffected." : "Marked done. Dates unaffected.");
    },
    "undo-skip": () => { state.skipped = null; renderCurrent(); },
    "kleos-open": (el) => { if (el.dataset.k === "first") go("kleos"); else toast("Kleos · " + $("b", el).textContent); },
  };

  document.addEventListener("click", (e) => {
    const goEl = e.target.closest("[data-go]");
    if (goEl) { go(goEl.dataset.go, goEl.dataset.tab ? { tab: goEl.dataset.tab } : {}); return; }
    const act = e.target.closest("[data-act]");
    if (act && ACTIONS[act.dataset.act]) { ACTIONS[act.dataset.act](act); return; }
    const stepBtn = e.target.closest("[data-step]");
    if (stepBtn) {
      const dir = +stepBtn.dataset.dir;
      if (stepBtn.dataset.step === "dist") state.create.dist = Math.max(400, Math.min(3000, state.create.dist + dir * 100));
      else state.create.time = stepTime(state.create.time, dir);
      renderCreate();
      return;
    }
    const clock = e.target.closest("[data-clock]");
    if (clock) { setClock(clock.dataset.clock); return; }
    const load = e.target.closest("[data-load]");
    if (load) { setLoad(load.dataset.load); return; }
    const route = e.target.closest("[data-route]");
    if (route) { state.route = route.dataset.route; syncRail(); toast(`Sounding route · ${route.textContent}`); return; }
    const syn = e.target.closest("[data-synced]");
    if (syn) { setSynced(syn.dataset.synced === "on"); return; }
    const gb = e.target.closest("[data-game-btn]");
    if (gb) { setGame(gb.dataset.gameBtn === "on"); return; }
    const th = e.target.closest("[data-theme-btn]");
    if (th) { setTheme(th.dataset.themeBtn); return; }
    const reason = e.target.closest("[data-reason]");
    if (reason) {
      state.skipped = reason.dataset.reason;
      closeSheets();
      renderCurrent();
      toast(`Skipped · ${reason.dataset.reason}. Dates${state.game ? " and Streak" : ""} unchanged.`);
      return;
    }
    const adj = e.target.closest("[data-adjust]");
    if (adj) {
      state.adjusted = adj.dataset.adjust; state.choreDone = true;
      closeSheets();
      renderCurrent();
      toast(state.game ? "Adjusted · counts as done (+60 Areté)" : "Adjusted · counts as done");
      return;
    }
    if (e.target.closest("[data-close-sheet]") || e.target === backdrop) closeSheets();
  });

  $("#btnBack").addEventListener("click", () => { const b = SCREENS[state.screen].back; if (b) go(b); });
  $("#btnConfirmDelay").addEventListener("click", () => { closeSheets(); toast(state.game ? "Demo: Trial 2 → Nov 4 (+4 d). Areté, Streak and Depth unchanged." : "Demo: Trial 2 → Nov 4 (+4 d)."); });

  // Trial not passed → choices land on the moved clock
  $("#btnRetry").addEventListener("click", () => { state.stepDown = false; setClock("slipped"); go("home"); toast("Retry set for Wed Nov 4. Areté, Streak and Depth unchanged."); });
  $("#btnStepDown").addEventListener("click", () => { setClock("slipped"); state.stepDown = true; go("home"); toast("Step of 1,150 m on Nov 4 · goal forecast Nov 11."); });
  $("#btnLater").addEventListener("click", () => { state.stepDown = false; setClock("slipped"); go("home"); toast("Held the Nov 4 retry. Change it anytime from the milestone card."); });

  $("#btnNext").addEventListener("click", () => {
    const i = ORDER.indexOf(state.screen);
    go(ORDER[(i + 1) % ORDER.length]);
  });
  $("#btnReset").addEventListener("click", () => {
    const theme = state.theme;
    state = DEFAULTS();
    state.theme = theme;
    document.body.dataset.game = "on";
    syncRail();
    go("create");
  });
  document.addEventListener("keydown", (e) => {
    if (e.target.matches("input, textarea")) return;
    const i = ORDER.indexOf(state.screen);
    if (e.key === "ArrowRight") go(ORDER[Math.min(ORDER.length - 1, i + 1)]);
    if (e.key === "ArrowLeft") go(ORDER[Math.max(0, i - 1)]);
    if (e.key === "Escape") closeSheets();
  });

  /* ───────────── Boot ───────────── */
  buildLaurel();
  buildBubbles();
  // Optional deep-link flags: ?theme=dark &clock=slipped &synced=1 &game=off &route=test
  const qp = new URLSearchParams(location.search);
  if (qp.get("theme") === "dark") setTheme("dark");
  if (qp.get("clock") === "slipped") { state.clock = "slipped"; if (qp.get("step") === "1") state.stepDown = true; }
  if (qp.get("synced") === "1") state.synced = true;
  if (qp.get("game") === "off") setGame(false);
  if (["test", "self"].includes(qp.get("route"))) state.route = qp.get("route");
  syncRail();
  const initial = ALIASES[location.hash.replace("#", "")] || location.hash.replace("#", "");
  go(SCREENS[initial] ? initial : "create", { silent: !SCREENS[initial] });
})();
