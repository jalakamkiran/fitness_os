(() => {
  /**
   * Coach-led pool swim detail PoL — Fathom tokens + plan IA (2026-10-09).
   * Landscape expands inside the phone (device rotate), not a page-level modal.
   * Intervals: collapsible sets with horizontal length/rest bars.
   */

  function makeLaps(n, opts = {}) {
    const { fade = true, garbageAt = [], restGaps = true } = opts;
    const laps = [];
    for (let i = 1; i <= n; i++) {
      const t = fade ? (i - 1) / Math.max(n - 1, 1) : 0;
      const dur = Math.round(22 + t * 8 + (i % 3 === 0 ? 1 : 0));
      const strokes = Math.round(34 + t * 6);
      const dist = 25;
      const swolf = dur + strokes;
      const paceSecPer100m = Math.round((dur / dist) * 100);
      const rest = restGaps && i < n ? 15 + (i % 4) * 2 : 0;
      laps.push({
        i,
        dist,
        dur,
        strokes,
        swolf,
        paceSecPer100m,
        rest,
        garbage: false,
      });
    }
    for (const g of garbageAt) {
      if (g.index >= 1 && g.index <= laps.length) {
        Object.assign(laps[g.index - 1], {
          garbage: true,
          why: g.why || "filtered",
          dist: g.dist ?? 3,
          dur: g.dur ?? 2,
          strokes: g.strokes ?? 2,
          swolf: g.swolf ?? 4,
          paceSecPer100m: null,
        });
      }
    }
    return laps;
  }

  /** Group athlete laps into Warmup / Main / Cool (or Block N for dense). */
  function buildSets(session) {
    if (session.sets) return session.sets;
    const laps = session.laps;
    const n = laps.length;
    if (n <= 4) {
      return [{ id: "main", label: "Main set", kind: "main", effort: "Steady", lapIndexes: laps.map((_, i) => i) }];
    }
    if (n <= 24) {
      const w = Math.max(2, Math.floor(n * 0.2));
      const c = Math.max(2, Math.floor(n * 0.15));
      const m = n - w - c;
      return [
        { id: "warmup", label: "Warmup", kind: "warmup", effort: "Easy", lapIndexes: range(0, w) },
        { id: "main", label: "Main set", kind: "main", effort: "Endurance", lapIndexes: range(w, w + m) },
        { id: "cool", label: "Cool down", kind: "cool", effort: "Easy", lapIndexes: range(w + m, n) },
      ];
    }
    // Dense (25+): equal-ish blocks for scannability
    const block = Math.ceil(n / 4);
    const sets = [];
    for (let b = 0, start = 0; start < n; b++, start += block) {
      const end = Math.min(n, start + block);
      sets.push({
        id: `block${b + 1}`,
        label: `Block ${b + 1}`,
        kind: b === 0 ? "warmup" : b === 3 ? "cool" : "block",
        effort: b === 0 ? "Build" : b === 3 ? "Fade watch" : "Main effort",
        lapIndexes: range(start, end),
      });
    }
    return sets;
  }

  function range(a, b) {
    const out = [];
    for (let i = a; i < b; i++) out.push(i);
    return out;
  }

  const FIXTURES = {
    typical: {
      id: 94,
      sport: "Pool swim",
      when: "Thu 8 Oct · 06:42",
      poolM: 25,
      stroke: "Freestyle",
      durationSec: 1180,
      movingSec: 920,
      hr: { avg: 142, max: 168, locked: true },
      story: "Efficient early, then pace and SWOLF slipped after the third block.",
      chips: [
        { label: "Pace", delta: "+4s/100", dir: "down" },
        { label: "SWOLF", delta: "+3", dir: "down" },
        { label: "Volume", delta: "same", dir: "flat" },
      ],
      tip: {
        title: "Shorter sets with full recovery",
        why: "Hold early-set pace with longer rest until SWOLF stabilizes mid-set.",
        diagnosisId: "fatigue_onset",
      },
      findings: [
        {
          id: "efficiency_decline",
          title: "Technique cost rose with fatigue",
          body: "SWOLF climbed alongside pace — not just slower turns.",
        },
        {
          id: "stroke_creep",
          title: "Stroke count crept up",
          body: "Higher turnover late; match early-set stroke count before adding speed.",
        },
      ],
      laps: makeLaps(16, { garbageAt: [{ index: 7, why: "incomplete length" }] }),
    },
    dense: {
      id: 101,
      sport: "Pool swim",
      when: "Wed 7 Oct · 18:10",
      poolM: 25,
      stroke: "Freestyle",
      durationSec: 2840,
      movingSec: 2100,
      hr: { avg: 138, max: 162, locked: true },
      story: "Steady middle, with late fade across a long continuous set.",
      chips: [
        { label: "Pace", delta: "+2s/100", dir: "down" },
        { label: "SWOLF", delta: "+1", dir: "down" },
        { label: "Volume", delta: "+400m", dir: "up" },
      ],
      tip: {
        title: "Break the set before the fade",
        why: "Insert a full recovery after interval ~25 so late lengths stay honest.",
        diagnosisId: "fatigue_onset",
      },
      findings: [
        {
          id: "pacing_uneven",
          title: "Uneven middle block",
          body: "Intervals 12–20 swung more than the openers.",
        },
      ],
      laps: makeLaps(40, {
        garbageAt: [
          { index: 14, why: "outlier strokes", strokes: 180, dur: 1, dist: 25, swolf: 181 },
        ],
      }),
    },
    thin: {
      id: 12,
      sport: "Pool swim",
      when: "Mon 5 Oct · 07:05",
      poolM: 25,
      stroke: "Freestyle",
      durationSec: 640,
      movingSec: 520,
      hr: { avg: 136, max: 155, locked: true },
      story: "A solid first logged set in this pool — early lengths were the cleanest.",
      chips: [],
      tip: {
        title: "Repeat a controlled set",
        why: "One more comparable swim unlocks pace and SWOLF comparisons.",
        diagnosisId: "keep_steady",
      },
      findings: [],
      laps: makeLaps(8, { fade: false }),
    },
    nohr: {
      id: 88,
      sport: "Pool swim",
      when: "Sun 4 Oct · 09:20",
      poolM: 25,
      stroke: "Freestyle",
      durationSec: 980,
      movingSec: 780,
      hr: null,
      story: "Pace held through the main set; rest was honest between lengths.",
      chips: [
        { label: "Pace", delta: "−1s/100", dir: "up" },
        { label: "SWOLF", delta: "−2", dir: "up" },
      ],
      tip: {
        title: "Keep the mid-set rhythm",
        why: "You already matched early SWOLF — repeat that block before adding volume.",
        diagnosisId: "keep_steady",
      },
      findings: [],
      laps: makeLaps(12),
    },
    escape: {
      id: 33,
      sport: "Pool swim",
      when: "Sat 3 Oct · 08:00",
      poolM: 25,
      stroke: "Mixed",
      durationSec: 210,
      movingSec: 180,
      hr: null,
      story: "Short session — not enough paced intervals for a coaching tip.",
      chips: [],
      tip: null,
      tipEscape: "Not enough interval data for a coaching tip yet. KPIs and available lengths still show below.",
      findings: [],
      laps: makeLaps(3, { fade: false, restGaps: false }),
    },
    openwater: {
      id: 8,
      sport: "Open water",
      when: "Fri 2 Oct · 16:40",
      poolM: null,
      stroke: "Freestyle",
      durationSec: 1920,
      movingSec: 1920,
      hr: { avg: 148, max: 171, locked: true },
      story: "Sustained effort with a late push — open-water coaching narratives stay light in v1.",
      chips: [],
      tip: {
        title: "Log a comparable OW swim",
        why: "One more open-water session unlocks focus-relative comparisons.",
        diagnosisId: "keep_steady",
      },
      findings: [],
      laps: makeLaps(10, { fade: true, restGaps: false }).map((l, idx) => ({
        ...l,
        dist: 100,
        dur: 95 + idx * 2,
        paceSecPer100m: 95 + idx * 2,
        strokes: 40 + (idx % 3),
        swolf: null,
      })),
    },
  };

  const root = document.documentElement;
  const body = document.body;
  const main = document.getElementById("main");
  const headerTitle = document.getElementById("headerTitle");
  const headerMeta = document.getElementById("headerMeta");
  const fixtureSelect = document.getElementById("fixtureSelect");
  const digDeeper = document.getElementById("digDeeper");
  const landscape = document.getElementById("landscape");
  const landChart = document.getElementById("landChart");
  const landSeries = document.getElementById("landSeries");
  const landScrub = document.getElementById("landScrub");
  const landClose = document.getElementById("landClose");
  const landTitle = document.getElementById("landTitle");
  const landMeta = document.getElementById("landMeta");
  const phoneHint = document.getElementById("phoneHint");

  let state = {
    fixtureKey: "typical",
    series: "pace",
    findingsOpen: false,
    openSets: { main: true },
    selectedInterval: null,
  };

  /** Keep session ref for landscape without re-render race */
  let currentSession = null;
  let currentSeriesList = [];

  function fmtDur(sec) {
    const m = Math.floor(sec / 60);
    const s = sec % 60;
    return `${m}:${String(s).padStart(2, "0")}`;
  }

  function fmtPace(sec) {
    if (sec == null || !(sec > 0)) return "—";
    const m = Math.floor(sec / 60);
    const s = Math.round(sec % 60);
    return `${m}:${String(s).padStart(2, "0")}`;
  }

  function athleteLaps(session) {
    return session.laps.filter((l) => !l.garbage);
  }

  function distanceM(session) {
    return athleteLaps(session).reduce((a, l) => a + (l.dist || 0), 0);
  }

  function avgPace(session) {
    const laps = athleteLaps(session).filter((l) => l.paceSecPer100m > 0);
    if (!laps.length) return null;
    return Math.round(laps.reduce((a, l) => a + l.paceSecPer100m, 0) / laps.length);
  }

  function avgSwolf(session) {
    const laps = athleteLaps(session).filter((l) => l.swolf != null);
    if (!laps.length) return null;
    return Math.round(laps.reduce((a, l) => a + l.swolf, 0) / laps.length);
  }

  function durationHonesty(session) {
    const { movingSec, durationSec } = session;
    if (movingSec > 0 && movingSec <= durationSec) {
      return {
        primary: fmtDur(movingSec),
        hint: `swim · ${fmtDur(durationSec - movingSec)} rest`,
      };
    }
    return { primary: fmtDur(durationSec), hint: null };
  }

  function seriesValue(lap, series) {
    if (series === "pace") return lap.paceSecPer100m;
    if (series === "swolf") return lap.swolf;
    if (series === "strokes") return lap.strokes;
    if (series === "hr") return lap.hrProxy;
    return null;
  }

  function attachHrProxy(session) {
    if (!session.hr?.locked) return session;
    const laps = session.laps.map((l, idx) => {
      if (l.garbage) return l;
      const t = idx / Math.max(session.laps.length - 1, 1);
      const hr = Math.round(session.hr.avg - 8 + t * (session.hr.max - session.hr.avg + 8));
      return { ...l, hrProxy: hr };
    });
    return { ...session, laps };
  }

  function availableSeries(session) {
    const laps = athleteLaps(session);
    const out = ["pace"];
    if (laps.some((l) => l.swolf != null)) out.push("swolf");
    if (laps.some((l) => l.strokes != null)) out.push("strokes");
    if (session.hr?.locked) out.push("hr");
    return out;
  }

  /** —— Canvas charts from swim-analytics.js (fade bars, area lines, tooltips) —— */
  function cssVar(name, fallback) {
    const v = getComputedStyle(root).getPropertyValue(name).trim();
    return v || fallback;
  }

  function showTip(clientX, clientY, html) {
    const tip = document.getElementById("saTip");
    const phone = document.getElementById("phone");
    if (!tip || !phone) return;
    tip.hidden = false;
    tip.innerHTML = html;
    tip.classList.add("show");
    const box = phone.getBoundingClientRect();
    const x = Math.min(Math.max(8, clientX - box.left + 12), box.width - 148);
    const y = Math.max(8, clientY - box.top - 56);
    tip.style.left = `${x}px`;
    tip.style.top = `${y}px`;
  }

  function hideTip() {
    const tip = document.getElementById("saTip");
    if (!tip) return;
    tip.classList.remove("show");
    tip.hidden = true;
  }

  function resizeCanvas(canvas, height) {
    const dpr = window.devicePixelRatio || 1;
    const w = canvas.clientWidth || canvas.parentElement.clientWidth || 320;
    const h = height || canvas.clientHeight || 148;
    canvas.width = Math.round(w * dpr);
    canvas.height = Math.round(h * dpr);
    const ctx = canvas.getContext("2d");
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    return { ctx, w, h };
  }

  function padRange(vals, pad = 0.12) {
    const clean = vals.filter((v) => v != null && Number.isFinite(v));
    const min = Math.min(...clean);
    const max = Math.max(...clean);
    const span = Math.max(1, max - min);
    return { min: min - span * pad, max: max + span * pad };
  }

  function yMap(v, min, max, top, bottom) {
    return top + ((max - v) / (max - min)) * (bottom - top);
  }

  function barColor(i, n, hotFrom) {
    const accent = cssVar("--accent", "#19B7B0");
    const amber = cssVar("--amber", "#D97706");
    const hot = cssVar("--hot", "#E85D4C");
    if (i >= hotFrom) return hot;
    if (i >= Math.floor(n * 0.55)) return amber;
    return accent;
  }

  function thinLabelIndexes(n, dense) {
    if (dense || n <= 10) return [...Array(n)].map((_, i) => i);
    if (n <= 18) return [0, 3, 7, 11, n - 1].filter((i, idx, a) => a.indexOf(i) === idx);
    const step = Math.ceil(n / 6);
    const ticks = [];
    for (let i = 0; i < n; i += step) ticks.push(i);
    if (ticks[ticks.length - 1] !== n - 1) ticks.push(n - 1);
    return ticks;
  }

  function seriesCaption(series) {
    if (series === "pace") return "s/100m · higher = slower";
    if (series === "swolf") return "time + strokes · lower better";
    if (series === "strokes") return "count · spike = churn";
    if (series === "hr") return "bpm · locked stream";
    return series;
  }

  function seriesTitle(series) {
    if (series === "pace") return "Pace by interval";
    if (series === "swolf") return "SWOLF";
    if (series === "strokes") return "Strokes per length";
    if (series === "hr") return "Heart rate";
    return series;
  }

  function chartShellHtml(canvasId, series, { tall = false } = {}) {
    return `
      <div class="sc-chart-card">
        <div class="chart-head">
          <h4>${seriesTitle(series)}</h4>
          <span class="caption">${seriesCaption(series)}</span>
        </div>
        <div class="sc-chart-canvas-wrap ${tall ? "tall" : ""}">
          <canvas id="${canvasId}" height="${tall ? 248 : 148}"></canvas>
        </div>
      </div>
    `;
  }

  function paintSeriesChart(canvasId, session, series, { tall = false, denseLabels = false } = {}) {
    const canvas = document.getElementById(canvasId);
    if (!canvas) return;
    const laps = athleteLaps(session);
    const values = laps.map((l) => seriesValue(l, series));
    const labels = laps.map((l) => `I${l.i}`);
    const plottable = values.filter((v) => v != null && v > 0);
    if (!plottable.length) {
      const { ctx, w, h } = resizeCanvas(canvas, tall ? 248 : 148);
      ctx.clearRect(0, 0, w, h);
      ctx.fillStyle = cssVar("--ink-faint", "#8a97a6");
      ctx.font = '12px "Manrope", sans-serif';
      ctx.fillText(`No ${series} series`, 16, h / 2);
      return;
    }

    const useBars = series === "pace" || series === "strokes";
    if (useBars) {
      drawBars(canvas, values, labels, {
        tall,
        denseLabels,
        fmt: (v) => (series === "pace" ? `${fmtPace(v)} /100m` : `${v} strokes`),
        colors: values.map((v, i) =>
          v == null || !(v > 0) ? "transparent" : barColor(i, values.length, Math.floor(values.length * 0.75))
        ),
        onSelect: (i, v) => {
          if (v == null) return;
          state.selectedInterval = laps[i].i;
          if (landScrub) {
            landScrub.querySelector("span").textContent = `Interval ${laps[i].i}`;
            landScrub.querySelector("strong").textContent =
              series === "pace" ? `${fmtPace(v)}/100` : String(v);
          }
        },
      });
    } else {
      drawLineArea(canvas, values, labels, {
        tall,
        denseLabels,
        color: series === "hr" ? cssVar("--hot", "#E85D4C") : cssVar("--accent", "#19B7B0"),
        fmt: (v) => (series === "hr" ? `${v} bpm` : `SWOLF ${v}`),
        onSelect: (i, v) => {
          if (v == null) return;
          state.selectedInterval = laps[i].i;
          if (landScrub) {
            landScrub.querySelector("span").textContent = `Interval ${laps[i].i}`;
            landScrub.querySelector("strong").textContent =
              series === "hr" ? `${v} bpm` : String(v);
          }
        },
      });
    }
  }

  function drawBars(canvas, values, labels, opts) {
    const { ctx, w, h } = resizeCanvas(canvas, opts.tall ? 248 : 148);
    const top = 18;
    const bottom = h - 22;
    const left = 10;
    const right = w - 10;
    const clean = values.filter((v) => v != null && v > 0);
    const { min, max } = padRange(clean, 0.08);
    const n = values.length;
    const gap = n > 28 ? 2 : n > 16 ? 4 : 6;
    const bw = Math.max(3, (right - left - gap * (n - 1)) / n);
    const labelIdx = new Set(thinLabelIndexes(n, opts.denseLabels));

    ctx.clearRect(0, 0, w, h);
    ctx.strokeStyle = cssVar("--line", "#d8ddd9");
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(left, bottom);
    ctx.lineTo(right, bottom);
    ctx.stroke();

    // y guides
    ctx.fillStyle = cssVar("--ink-faint", "#8a97a6");
    ctx.font = '9px "IBM Plex Mono", monospace';
    ctx.textAlign = "left";
    ctx.fillText(opts.fmt ? opts.fmt(max) : String(Math.round(max)), left, top + 2);

    const hits = [];
    values.forEach((v, i) => {
      const x = left + i * (bw + gap);
      if (v == null || !(v > 0)) {
        hits.push({ x, w: bw, i, v: null });
        return;
      }
      const y = yMap(v, min, max, top, bottom);
      const selected = state.selectedInterval != null && labels[i] === `I${state.selectedInterval}`;
      ctx.fillStyle = opts.colors?.[i] || barColor(i, n, Math.floor(n * 0.75));
      ctx.beginPath();
      const r = Math.min(5, bw / 2);
      ctx.moveTo(x, bottom);
      ctx.lineTo(x, y + r);
      ctx.quadraticCurveTo(x, y, x + r, y);
      ctx.lineTo(x + bw - r, y);
      ctx.quadraticCurveTo(x + bw, y, x + bw, y + r);
      ctx.lineTo(x + bw, bottom);
      ctx.closePath();
      ctx.fill();
      if (selected) {
        ctx.strokeStyle = cssVar("--ink", "#142033");
        ctx.lineWidth = 1.5;
        ctx.stroke();
      }
      if (labelIdx.has(i)) {
        ctx.fillStyle = cssVar("--ink-faint", "#8a97a6");
        ctx.font = '10px "IBM Plex Mono", monospace';
        ctx.textAlign = "center";
        ctx.fillText(labels[i], x + bw / 2, h - 6);
      }
      hits.push({ x, w: bw, i, v });
    });

    canvas.onpointermove = (e) => {
      const rect = canvas.getBoundingClientRect();
      const px = e.clientX - rect.left;
      const hit = hits.find((h) => px >= h.x && px <= h.x + h.w);
      if (!hit || hit.v == null) return hideTip();
      showTip(
        e.clientX,
        e.clientY,
        `<div class="t-title">${labels[hit.i]}</div><div class="t-mono">${opts.fmt(hit.v)}</div>`
      );
    };
    canvas.onpointerleave = hideTip;
    canvas.onclick = (e) => {
      const rect = canvas.getBoundingClientRect();
      const px = e.clientX - rect.left;
      const hit = hits.find((h) => px >= h.x && px <= h.x + h.w);
      if (!hit || hit.v == null) return;
      opts.onSelect?.(hit.i, hit.v);
      paintSeriesChart(canvas.id, currentSession, state.series, {
        tall: opts.tall,
        denseLabels: opts.denseLabels,
      });
    };
  }

  function drawLineArea(canvas, values, labels, opts) {
    const { ctx, w, h } = resizeCanvas(canvas, opts.tall ? 248 : 148);
    const top = 18;
    const bottom = h - 22;
    const left = 14;
    const right = w - 14;
    const cleanIdx = values.map((v, i) => (v != null && v > 0 ? i : -1)).filter((i) => i >= 0);
    const clean = cleanIdx.map((i) => values[i]);
    const { min, max } = padRange(clean);
    const n = values.length;
    const xs = values.map((_, i) => left + (i * (right - left)) / Math.max(1, n - 1));
    const color = opts.color || cssVar("--accent", "#19B7B0");
    const labelIdx = new Set(thinLabelIndexes(n, opts.denseLabels));

    ctx.clearRect(0, 0, w, h);
    if (cleanIdx.length < 2) {
      ctx.fillStyle = cssVar("--ink-faint", "#8a97a6");
      ctx.font = '12px "Manrope", sans-serif';
      ctx.fillText("Not enough points", 16, h / 2);
      return;
    }

    const grad = ctx.createLinearGradient(0, top, 0, bottom);
    // accent + alpha via color-mix fallback
    grad.addColorStop(0, color);
    grad.addColorStop(1, "transparent");

    ctx.beginPath();
    ctx.moveTo(xs[cleanIdx[0]], bottom);
    cleanIdx.forEach((i) => {
      const y = yMap(values[i], min, max, top, bottom);
      ctx.lineTo(xs[i], y);
    });
    ctx.lineTo(xs[cleanIdx[cleanIdx.length - 1]], bottom);
    ctx.closePath();
    ctx.globalAlpha = 0.28;
    ctx.fillStyle = color;
    ctx.fill();
    ctx.globalAlpha = 1;

    ctx.beginPath();
    cleanIdx.forEach((i, k) => {
      const y = yMap(values[i], min, max, top, bottom);
      k === 0 ? ctx.moveTo(xs[i], y) : ctx.lineTo(xs[i], y);
    });
    ctx.strokeStyle = color;
    ctx.lineWidth = 2.25;
    ctx.stroke();

    cleanIdx.forEach((i, k) => {
      const y = yMap(values[i], min, max, top, bottom);
      ctx.beginPath();
      ctx.arc(xs[i], y, 3.5, 0, Math.PI * 2);
      ctx.fillStyle = k >= cleanIdx.length - 2 ? cssVar("--hot", "#E85D4C") : color;
      ctx.fill();
      if (labelIdx.has(i)) {
        ctx.fillStyle = cssVar("--ink-faint", "#8a97a6");
        ctx.font = '10px "IBM Plex Mono", monospace';
        ctx.textAlign = "center";
        ctx.fillText(labels[i], xs[i], h - 6);
      }
    });

    canvas.onpointermove = (e) => {
      const rect = canvas.getBoundingClientRect();
      const px = e.clientX - rect.left;
      let best = cleanIdx[0];
      let bestD = Infinity;
      cleanIdx.forEach((i) => {
        const d = Math.abs(xs[i] - px);
        if (d < bestD) {
          bestD = d;
          best = i;
        }
      });
      if (bestD > 28) return hideTip();
      showTip(
        e.clientX,
        e.clientY,
        `<div class="t-title">${labels[best]}</div><div class="t-mono">${opts.fmt(values[best])}</div>`
      );
    };
    canvas.onpointerleave = hideTip;
    canvas.onclick = (e) => {
      const rect = canvas.getBoundingClientRect();
      const px = e.clientX - rect.left;
      let best = cleanIdx[0];
      let bestD = Infinity;
      cleanIdx.forEach((i) => {
        const d = Math.abs(xs[i] - px);
        if (d < bestD) {
          bestD = d;
          best = i;
        }
      });
      if (bestD > 36) return;
      opts.onSelect?.(best, values[best]);
    };
  }

  function chipHtml(chips) {
    if (!chips.length) return "";
    return `
      <div class="sc-chips" aria-label="Comparisons">
        ${chips
          .map(
            (c) => `
          <span class="sc-chip ${c.dir}">
            ${c.label}
            <span class="delta">${c.delta}</span>
          </span>`
          )
          .join("")}
      </div>
    `;
  }

  function tipHtml(session) {
    if (session.tip) {
      return `
        <section class="sc-tip" aria-label="Primary tip">
          <p class="kicker">Next session</p>
          <h3>${session.tip.title}</h3>
          <p>${session.tip.why}</p>
        </section>
      `;
    }
    return `
      <section class="sc-tip is-escape" aria-label="Tip unavailable">
        <p class="kicker">Coaching tip</p>
        <h3>Tip unavailable</h3>
        <p>${session.tipEscape || "Not enough interval data for a coaching tip."}</p>
      </section>
    `;
  }

  function kpiHtml(session) {
    const dist = distanceM(session);
    const dur = durationHonesty(session);
    const pace = avgPace(session);
    const swolf = avgSwolf(session);
    const secondary = [];
    if (pace != null) secondary.push({ label: "Avg pace", value: `${fmtPace(pace)}/100` });
    if (swolf != null) secondary.push({ label: "Avg SWOLF", value: String(swolf) });
    if (session.hr?.locked) {
      secondary.push({ label: "Avg HR", value: `${session.hr.avg}` });
      secondary.push({ label: "Max HR", value: `${session.hr.max}` });
    }

    return `
      <section class="sc-kpis" aria-label="Session KPIs">
        <div class="sc-kpi-primary">
          <div class="cell">
            <span class="label">Distance</span>
            <span class="value">${dist}<span style="font-size:0.7em;color:var(--ink-dim)"> m</span></span>
            ${session.poolM ? `<span class="hint">${session.poolM}m pool · ${session.stroke}</span>` : `<span class="hint">${session.stroke}</span>`}
          </div>
          <div class="cell">
            <span class="label">Duration</span>
            <span class="value">${dur.primary}</span>
            ${dur.hint ? `<span class="hint">${dur.hint}</span>` : ""}
          </div>
        </div>
        ${
          secondary.length
            ? `<div class="sc-kpi-secondary">${secondary
                .map(
                  (s) => `
              <span class="item"><span class="label">${s.label}</span><span class="value">${s.value}</span></span>`
                )
                .join("")}</div>`
            : ""
        }
      </section>
    `;
  }

  function jumpsHtml(session) {
    const links = [{ href: "#sc-charts", label: "Charts" }];
    if (athleteLaps(session).length) links.push({ href: "#sc-intervals", label: "Intervals" });
    if (session.findings.length) links.push({ href: "#sc-findings", label: "Findings" });
    return `
      <nav class="sc-jumps" aria-label="Jump links">
        ${links.map((l) => `<a href="${l.href}">${l.label}</a>`).join("")}
      </nav>
    `;
  }

  function seriesButtons(seriesList, active) {
    return seriesList
      .map(
        (s) => `
      <button type="button" class="${s === active ? "is-active" : ""}" data-series="${s}" role="tab" aria-selected="${s === active}">
        ${s === "hr" ? "HR" : s.charAt(0).toUpperCase() + s.slice(1)}
      </button>`
      )
      .join("");
  }

  function setSummary(session, set) {
    const laps = set.lapIndexes.map((i) => session.laps[i]).filter((l) => l && !l.garbage);
    const dist = laps.reduce((a, l) => a + l.dist, 0);
    const paces = laps.filter((l) => l.paceSecPer100m > 0).map((l) => l.paceSecPer100m);
    const avg = paces.length ? Math.round(paces.reduce((a, b) => a + b, 0) / paces.length) : null;
    const unit = session.poolM ? `${laps.length} × ${session.poolM || 25}m` : `${laps.length} segments`;
    return {
      line: `${unit} · ${session.stroke}`,
      meta: avg != null ? fmtPace(avg) : fmtDur(laps.reduce((a, l) => a + l.dur, 0)),
      dist,
      count: laps.length,
    };
  }

  function lengthBarsHtml(session, lap, maxDur, maxRest) {
    const pace = lap.paceSecPer100m;
    const sessionAvg = avgPace(session);
    const slow = pace != null && sessionAvg != null && pace > sessionAvg + 3;
    const workPct = Math.max(8, Math.round((lap.dur / (maxDur || 1)) * 100));
    const restPct = lap.rest ? Math.max(6, Math.round((lap.rest / (maxRest || 1)) * 100)) : 0;
    return `
      <div class="sc-length ${lap.garbage ? "is-filtered" : ""}" data-lap="${lap.i}">
        <span class="idx">#${lap.i}</span>
        <div class="sc-length-bars">
          <div class="sc-hbar-track" title="Swim ${fmtDur(lap.dur)}">
            <div class="sc-hbar ${slow ? "slow" : ""}" style="width:${workPct}%"></div>
          </div>
          ${
            lap.rest
              ? `<div class="sc-hbar-track rest" title="Rest ${fmtDur(lap.rest)}">
                   <div class="sc-hbar rest" style="width:${restPct}%"></div>
                 </div>`
              : ""
          }
        </div>
        <span class="time">${fmtDur(lap.dur)}</span>
        ${lap.rest ? `<span class="rest-time">+${fmtDur(lap.rest)}</span>` : ""}
      </div>
    `;
  }

  function intervalsHtml(session) {
    const sets = buildSets(session);
    const showAll = body.getAttribute("data-dig-deeper") === "on";
    const allLaps = session.laps;
    const maxDur = Math.max(...allLaps.filter((l) => showAll || !l.garbage).map((l) => l.dur), 1);
    const maxRest = Math.max(...allLaps.map((l) => l.rest || 0), 1);

    // Default: open main (or first) set
    if (!Object.keys(state.openSets).length) {
      const prefer = sets.find((s) => s.id === "main") || sets[0];
      state.openSets = { [prefer.id]: true };
    }

    const cards = sets
      .map((set) => {
        const sum = setSummary(session, set);
        const open = !!state.openSets[set.id];
        const laps = set.lapIndexes
          .map((i) => allLaps[i])
          .filter((l) => l && (showAll || !l.garbage));
        const filtered = set.lapIndexes.map((i) => allLaps[i]).filter((l) => l?.garbage).length;

        return `
          <article class="sc-set ${open ? "is-open" : ""}" data-set="${set.id}">
            <button type="button" class="sc-set-head" aria-expanded="${open}">
              <span class="sc-set-dot ${set.kind}" aria-hidden="true"></span>
              <span class="sc-set-copy">
                <strong>${set.label}${sum.count ? ` · ${sum.count}x` : ""}</strong>
                <span>${sum.line}</span>
              </span>
              <span class="sc-set-meta">${sum.meta}</span>
              <span class="sc-set-chev" aria-hidden="true">▾</span>
            </button>
            <div class="sc-set-body">
              <div class="sc-set-effort">
                <span>${set.effort} effort</span>
                <span class="tag">${sum.meta}/100 avg</span>
              </div>
              ${laps.map((l) => lengthBarsHtml(session, l, maxDur, maxRest)).join("")}
              ${
                filtered
                  ? `<p class="sc-dev-note">Dev · ${filtered} invent-guard filtered length(s) in this set</p>`
                  : ""
              }
            </div>
          </article>
        `;
      })
      .join("");

    return `
      <section class="sc-section" id="sc-intervals" aria-label="Intervals">
        <div class="sc-section-head">
          <h3>Intervals</h3>
          <span class="caption">${athleteLaps(session).length} lengths · tap to expand</span>
        </div>
        <div class="sc-sets">${cards}</div>
      </section>
    `;
  }

  function findingsHtml(session) {
    if (!session.findings.length) return "";
    const open = state.findingsOpen ? "open" : "";
    return `
      <section class="sc-findings sc-section" id="sc-findings" aria-label="More findings">
        <details ${open} id="findingsDetails">
          <summary>
            More findings
            <span class="count">${session.findings.length}</span>
          </summary>
          ${session.findings
            .map(
              (f) => `
            <div class="sc-finding">
              <h4>${f.title}</h4>
              <p>${f.body}</p>
            </div>`
            )
            .join("")}
        </details>
      </section>
    `;
  }

  function debugHtml(session) {
    return `
      <section class="sc-debug" aria-label="Dig-deeper dump">
        <strong>Dig deeper · pipeline (athlete path hides this)</strong>
        Enrichment: data=ok pace=ok segments=${session.laps.length}<br />
        Sync: ok · Type: ${session.sport === "Open water" ? "8" : "6"} (${session.sport})<br />
        P0 metrics · Evidence → Diagnosis (deterministic)<br />
        metrics: fatigue_onset, efficiency_decline · invent-guard filtered=${session.laps.filter((l) => l.garbage).length}<br />
        Samples / wire index available when dig-deeper on
      </section>
    `;
  }

  function render() {
    const session = attachHrProxy(FIXTURES[state.fixtureKey]);
    const seriesList = availableSeries(session);
    if (!seriesList.includes(state.series)) state.series = seriesList[0];
    currentSession = session;
    currentSeriesList = seriesList;

    const laps = athleteLaps(session);
    const prominent = laps.length >= 10;

    headerTitle.textContent = `${session.sport} · #${session.id}`;
    headerMeta.textContent = session.when;

    main.innerHTML = `
      ${debugHtml(session)}
      <section class="sc-story" aria-label="Session verdict">
        <h2>${session.story}</h2>
        ${chipHtml(session.chips)}
      </section>
      ${tipHtml(session)}
      ${kpiHtml(session)}
      ${jumpsHtml(session)}
      <section class="sc-section" id="sc-charts" aria-label="Charts">
        <div class="sc-section-head">
          <h3>Pace by interval</h3>
          <span class="caption">${session.poolM ? `${session.poolM}m pool` : "Open water"} · ${laps.length} lengths</span>
        </div>
        <div class="sc-series" id="portraitSeries" role="tablist" aria-label="Chart series">
          ${seriesButtons(seriesList, state.series)}
        </div>
        <div id="portraitChart">
          ${chartShellHtml("cPortrait", state.series)}
        </div>
        <button type="button" class="sc-expand ${prominent ? "prominent" : ""}" id="expandBtn">
          <span>
            <strong>${prominent ? "Rotate for expanded analysis" : "Expand in landscape"}</strong>
            <span>${prominent ? `${laps.length} intervals · full-width ticks` : "Phone turns landscape"}</span>
          </span>
          <span class="chev" aria-hidden="true">⛶</span>
        </button>
      </section>
      ${intervalsHtml(session)}
      ${findingsHtml(session)}
    `;

    bindPortrait(session, seriesList);
    requestAnimationFrame(() => paintSeriesChart("cPortrait", session, state.series));
  }

  function bindPortrait(session, seriesList) {
    const seriesEl = document.getElementById("portraitSeries");
    seriesEl?.addEventListener("click", (e) => {
      const btn = e.target.closest("[data-series]");
      if (!btn) return;
      state.series = btn.getAttribute("data-series");
      seriesEl.querySelectorAll("button").forEach((b) => {
        const on = b.getAttribute("data-series") === state.series;
        b.classList.toggle("is-active", on);
        b.setAttribute("aria-selected", on ? "true" : "false");
      });
      document.getElementById("portraitChart").innerHTML = chartShellHtml("cPortrait", state.series);
      requestAnimationFrame(() => paintSeriesChart("cPortrait", session, state.series));
    });

    document.getElementById("expandBtn")?.addEventListener("click", (e) => {
      e.preventDefault();
      openLandscape();
    });

    document.getElementById("findingsDetails")?.addEventListener("toggle", (e) => {
      state.findingsOpen = e.target.open;
    });

    main.querySelectorAll(".sc-set-head").forEach((btn) => {
      btn.addEventListener("click", () => {
        const art = btn.closest(".sc-set");
        const id = art.getAttribute("data-set");
        const next = !art.classList.contains("is-open");
        art.classList.toggle("is-open", next);
        btn.setAttribute("aria-expanded", next ? "true" : "false");
        state.openSets[id] = next;
      });
    });

    main.querySelectorAll(".sc-jumps a").forEach((a) => {
      a.addEventListener("click", (e) => {
        const id = a.getAttribute("href")?.slice(1);
        if (!id) return;
        e.preventDefault();
        if (id === "sc-findings") {
          const det = document.getElementById("findingsDetails");
          if (det) {
            det.open = true;
            state.findingsOpen = true;
          }
        }
        if (id === "sc-intervals") {
          const mainSet = main.querySelector('.sc-set[data-set="main"]') || main.querySelector(".sc-set");
          if (mainSet && !mainSet.classList.contains("is-open")) {
            mainSet.classList.add("is-open");
            const sid = mainSet.getAttribute("data-set");
            state.openSets[sid] = true;
            mainSet.querySelector(".sc-set-head")?.setAttribute("aria-expanded", "true");
          }
        }
        document.getElementById(id)?.scrollIntoView({ behavior: "smooth", block: "start" });
      });
    });
  }

  function paintLandscape() {
    const session = currentSession;
    const seriesList = currentSeriesList;
    if (!session) return;

    const laps = athleteLaps(session);
    landTitle.textContent = `${seriesLabel(state.series)} · expanded`;
    landMeta.textContent = `${session.sport} #${session.id} · ${laps.length} lengths`;
    landSeries.innerHTML = seriesButtons(seriesList, state.series);
    landChart.innerHTML = chartShellHtml("cLandscape", state.series, { tall: true });
    landScrub.querySelector("span").textContent = "Hover or tap to inspect";
    landScrub.querySelector("strong").textContent =
      state.selectedInterval != null ? `Interval ${state.selectedInterval}` : "—";

    landSeries.querySelectorAll("button").forEach((btn) => {
      btn.addEventListener("click", () => {
        state.series = btn.getAttribute("data-series");
        paintLandscape();
        const portraitChart = document.getElementById("portraitChart");
        if (portraitChart) {
          portraitChart.innerHTML = chartShellHtml("cPortrait", state.series);
          requestAnimationFrame(() => paintSeriesChart("cPortrait", session, state.series));
        }
        document.querySelectorAll("#portraitSeries button").forEach((b) => {
          const on = b.getAttribute("data-series") === state.series;
          b.classList.toggle("is-active", on);
          b.setAttribute("aria-selected", on ? "true" : "false");
        });
      });
    });

    requestAnimationFrame(() =>
      paintSeriesChart("cLandscape", session, state.series, { tall: true, denseLabels: true })
    );
  }

  function seriesLabel(s) {
    if (s === "hr") return "HR";
    return s.charAt(0).toUpperCase() + s.slice(1);
  }

  const phoneEl = document.getElementById("phone");
  const phoneSlot = document.querySelector(".phone-slot");

  function fitLandscapeScale() {
    const padX = 24;
    const padY = 96;
    const sx = (window.innerWidth - padX) / 844;
    const sy = (window.innerHeight - padY) / 390;
    const scale = Math.max(0.55, Math.min(1, sx, sy));
    document.documentElement.style.setProperty("--land-scale", String(scale));
    if (phoneEl) {
      phoneEl.style.width = "844px";
      phoneEl.style.height = "390px";
      phoneEl.style.maxHeight = "none";
      phoneEl.style.transform = `scale(${scale})`;
      phoneEl.style.transformOrigin = "center center";
    }
    if (phoneSlot) {
      phoneSlot.style.width = `${844 * scale}px`;
      phoneSlot.style.height = `${390 * scale + 28}px`;
    }
  }

  function clearLandscapePhoneStyles() {
    if (phoneEl) {
      phoneEl.style.width = "";
      phoneEl.style.height = "";
      phoneEl.style.maxHeight = "";
      phoneEl.style.transform = "";
      phoneEl.style.transformOrigin = "";
    }
    if (phoneSlot) {
      phoneSlot.style.width = "";
      phoneSlot.style.height = "";
    }
    document.documentElement.style.removeProperty("--land-scale");
  }

  function openLandscape() {
    landscape.hidden = false;
    body.setAttribute("data-landscape", "on");
    phoneHint.textContent = "Landscape · expanded analysis";
    fitLandscapeScale();
    paintLandscape();
  }

  function closeLandscape() {
    body.setAttribute("data-landscape", "off");
    landscape.hidden = true;
    phoneHint.textContent = "Portrait · coach fold";
    clearLandscapePhoneStyles();
    hideTip();
    // Restore portrait chart selection state
    if (currentSession) {
      const portraitChart = document.getElementById("portraitChart");
      if (portraitChart) {
        portraitChart.innerHTML = chartShellHtml("cPortrait", state.series);
        requestAnimationFrame(() =>
          paintSeriesChart("cPortrait", currentSession, state.series)
        );
      }
      requestAnimationFrame(() => {
        document.getElementById("sc-charts")?.scrollIntoView({ behavior: "smooth", block: "start" });
      });
    }
  }

  function wireTheme(btn) {
    btn?.addEventListener("click", () => {
      const next = root.getAttribute("data-theme") === "dark" ? "light" : "dark";
      root.setAttribute("data-theme", next);
      const label = next === "dark" ? "Light" : "Dark";
      document.querySelectorAll("#themeToggle, #themeTogglePhone").forEach((b) => {
        b.textContent = label;
      });
      // Repaint canvas charts with new token colors
      if (body.getAttribute("data-landscape") === "on" && currentSession) {
        paintSeriesChart("cLandscape", currentSession, state.series, {
          tall: true,
          denseLabels: true,
        });
      } else if (currentSession && document.getElementById("cPortrait")) {
        paintSeriesChart("cPortrait", currentSession, state.series);
      }
    });
  }

  wireTheme(document.getElementById("themeToggle"));
  wireTheme(document.getElementById("themeTogglePhone"));

  fixtureSelect.addEventListener("change", () => {
    state.fixtureKey = fixtureSelect.value;
    state.findingsOpen = false;
    state.series = "pace";
    state.openSets = { main: true };
    state.selectedInterval = null;
    if (body.getAttribute("data-landscape") === "on") closeLandscape();
    render();
  });

  digDeeper.addEventListener("change", () => {
    body.setAttribute("data-dig-deeper", digDeeper.checked ? "on" : "off");
    render();
    if (body.getAttribute("data-landscape") === "on") paintLandscape();
  });

  landClose.addEventListener("click", (e) => {
    e.preventDefault();
    closeLandscape();
  });

  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && body.getAttribute("data-landscape") === "on") closeLandscape();
  });

  window.addEventListener("resize", () => {
    if (body.getAttribute("data-landscape") === "on") {
      fitLandscapeScale();
      if (currentSession) {
        paintSeriesChart("cLandscape", currentSession, state.series, {
          tall: true,
          denseLabels: true,
        });
      }
    } else if (currentSession && document.getElementById("cPortrait")) {
      paintSeriesChart("cPortrait", currentSession, state.series);
    }
  });

  render();
})();
