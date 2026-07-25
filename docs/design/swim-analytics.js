(() => {
  /**
   * Fixture: progressive fade set (#11-class) plus invent-guard noise laps
   * so Product Head "filter by default" can be demonstrated.
   */
  const RAW = [
    { i: 1, dist: 25, dur: 22, strokes: 34, swolf: 46, rest: 18 },
    { i: 2, dist: 25, dur: 23, strokes: 35, swolf: 47, rest: 20 },
    { i: 3, dist: 3, dur: 2, strokes: 2, swolf: 4, rest: 0, garbage: true, why: "incomplete length" },
    { i: 4, dist: 25, dur: 24, strokes: 36, swolf: 49, rest: 22 },
    { i: 5, dist: 25, dur: 25, strokes: 37, swolf: 51, rest: 24 },
    { i: 6, dist: 25, dur: 1, strokes: 180, swolf: 181, rest: 0, garbage: true, why: "outlier strokes" },
    { i: 7, dist: 25, dur: 26, strokes: 39, swolf: 53, rest: 26 },
    { i: 8, dist: 25, dur: 27, strokes: 40, swolf: 55, rest: 28 },
    { i: 9, dist: 25, dur: 28, strokes: 42, swolf: 58, rest: 30 },
    { i: 10, dist: 25, dur: 23, strokes: 41, swolf: 57, rest: 0 },
  ];

  const SESSION = {
    id: 11,
    when: "Tue 22 Jul · 06:42",
    poolM: 25,
    stroke: "Freestyle",
    distanceM: 200,
    durationSec: 198,
    diagnoses: [
      {
        id: "fatigue_onset",
        priority: true,
        tag: "P0 · fatigue",
        title: "Pace decay through the set",
        body: "Pace rose through working lengths. Late intervals cost more time for the same 25m.",
      },
      {
        id: "efficiency_decline",
        priority: true,
        tag: "P0 · efficiency",
        title: "SWOLF climbed with pace",
        body: "Technique slipped under load — not just heart-rate fatigue.",
      },
      {
        id: "stroke_creep",
        priority: false,
        tag: "signal",
        title: "Stroke count crept up",
        body: "Shorter pull / higher turnover as the set wore on.",
      },
    ],
    /** Allow-listed recs (Bible pipeline) — reasoner only ranks these. */
    recommendations: [
      {
        id: "shorter_sets",
        title: "Shorter sets with full recovery",
        detail: "Cut continuous volume; hold pace with longer rest until SWOLF stabilizes.",
        sourceDiagnosisIds: ["fatigue_onset"],
      },
      {
        id: "technique_before_volume",
        title: "Technique before volume",
        detail: "Prioritize stroke quality over distance until mid-set SWOLF holds.",
        sourceDiagnosisIds: ["efficiency_decline", "fatigue_onset"],
      },
      {
        id: "stroke_count_drill",
        title: "Stroke-count awareness drill",
        detail: "Easy 25s counting strokes; match early-set count before adding speed.",
        sourceDiagnosisIds: ["stroke_creep", "efficiency_decline"],
      },
      {
        id: "log_another_session",
        title: "Log another controlled swim",
        detail: "Repeat a controlled set so trend diagnoses can confirm.",
        sourceDiagnosisIds: [],
      },
    ],
  };

  const root = document.documentElement;
  const main = document.getElementById("main");
  const meta = document.getElementById("sessionMeta");
  let includeGarbage = false;
  /** @type {null | { source: string, summary: string, ordered: string[], rationale: Record<string,string>, notes: string }} */
  let reasonerResult = null;
  let reasonerBusy = false;

  function cssVar(name, fallback) {
    const v = getComputedStyle(root).getPropertyValue(name).trim();
    return v || fallback;
  }

  function paceSec100(iv) {
    return Math.round((iv.dur / iv.dist) * 100);
  }

  function fmtPace(sec) {
    const m = Math.floor(sec / 60);
    const s = sec % 60;
    return `${m}:${String(s).padStart(2, "0")}`;
  }

  function fmtDur(sec) {
    const m = Math.floor(sec / 60);
    const s = sec % 60;
    return `${m}:${String(s).padStart(2, "0")}`;
  }

  function bindTheme(btn) {
    if (!btn) return;
    btn.addEventListener("click", () => {
      const next = root.getAttribute("data-theme") === "dark" ? "light" : "dark";
      root.setAttribute("data-theme", next);
      document.querySelectorAll("#themeToggle, #themeTogglePhone").forEach((b) => {
        b.textContent = next === "dark" ? "Light" : "Dark";
      });
      render();
    });
  }
  bindTheme(document.getElementById("themeToggle"));
  bindTheme(document.getElementById("themeTogglePhone"));

  function activeIntervals() {
    return includeGarbage ? RAW : RAW.filter((r) => !r.garbage);
  }

  function displayIndex(row) {
    // Stable device index for sync; visual label uses sequential among active
    return row.i;
  }

  meta.textContent = `${SESSION.when} · ${SESSION.poolM}m · ${SESSION.stroke}`;

  const tipLayer = document.createElement("div");
  tipLayer.className = "sa-tooltip";
  tipLayer.id = "saTip";
  document.getElementById("phone").appendChild(tipLayer);

  function showTip(clientX, clientY, html) {
    const tip = document.getElementById("saTip");
    const phone = document.getElementById("phone").getBoundingClientRect();
    tip.innerHTML = html;
    tip.classList.add("show");
    const x = Math.min(clientX - phone.left + 12, phone.width - 140);
    const y = Math.max(8, clientY - phone.top - 56);
    tip.style.left = `${x}px`;
    tip.style.top = `${y}px`;
  }
  function hideTip() {
    document.getElementById("saTip")?.classList.remove("show");
  }

  function resizeCanvas(canvas) {
    const dpr = window.devicePixelRatio || 1;
    const w = canvas.clientWidth || canvas.parentElement.clientWidth;
    const h = 132;
    canvas.width = Math.round(w * dpr);
    canvas.height = Math.round(h * dpr);
    const ctx = canvas.getContext("2d");
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    return { ctx, w, h };
  }

  function padRange(vals, pad = 0.12) {
    const min = Math.min(...vals);
    const max = Math.max(...vals);
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

  function drawBars(canvasId, values, labels, opts) {
    const canvas = document.getElementById(canvasId);
    if (!canvas) return;
    const { ctx, w, h } = resizeCanvas(canvas);
    const top = 16;
    const bottom = h - 22;
    const left = 8;
    const right = w - 8;
    const { min, max } = padRange(values, 0.08);
    const n = values.length;
    const gap = 6;
    const bw = (right - left - gap * (n - 1)) / n;
    const hotFrom = opts.hotFrom ?? Math.floor(n * 0.75);

    ctx.clearRect(0, 0, w, h);
    ctx.strokeStyle = cssVar("--line", "#d8ddd9");
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(left, bottom);
    ctx.lineTo(right, bottom);
    ctx.stroke();

    const hits = [];
    values.forEach((v, i) => {
      const x = left + i * (bw + gap);
      const y = yMap(v, min, max, top, bottom);
      ctx.fillStyle = opts.colors?.[i] || barColor(i, n, hotFrom);
      ctx.beginPath();
      const r = 4;
      ctx.moveTo(x, bottom);
      ctx.lineTo(x, y + r);
      ctx.quadraticCurveTo(x, y, x + r, y);
      ctx.lineTo(x + bw - r, y);
      ctx.quadraticCurveTo(x + bw, y, x + bw, y + r);
      ctx.lineTo(x + bw, bottom);
      ctx.closePath();
      ctx.fill();
      ctx.fillStyle = cssVar("--muted", "#6b736f");
      ctx.font = '10px "IBM Plex Mono", monospace';
      ctx.textAlign = "center";
      ctx.fillText(labels[i], x + bw / 2, h - 6);
      hits.push({ x, w: bw, i, v });
    });

    canvas.onpointermove = (e) => {
      const rect = canvas.getBoundingClientRect();
      const px = e.clientX - rect.left;
      const hit = hits.find((h) => px >= h.x && px <= h.x + h.w);
      if (!hit) return hideTip();
      showTip(
        e.clientX,
        e.clientY,
        `<div class="t-title">${labels[hit.i]}</div><div class="t-mono">${opts.fmt(hit.v)}</div>`
      );
    };
    canvas.onpointerleave = hideTip;
  }

  function drawLineArea(canvasId, values, labels, opts) {
    const canvas = document.getElementById(canvasId);
    if (!canvas) return;
    const { ctx, w, h } = resizeCanvas(canvas);
    const top = 16;
    const bottom = h - 22;
    const left = 12;
    const right = w - 12;
    const { min, max } = padRange(values);
    const n = values.length;
    const xs = values.map((_, i) => left + (i * (right - left)) / Math.max(1, n - 1));
    const ys = values.map((v) => yMap(v, min, max, top, bottom));
    const accent = cssVar("--accent", "#19B7B0");

    ctx.clearRect(0, 0, w, h);
    const grad = ctx.createLinearGradient(0, top, 0, bottom);
    grad.addColorStop(0, accent + "55");
    grad.addColorStop(1, accent + "00");
    ctx.beginPath();
    ctx.moveTo(xs[0], bottom);
    xs.forEach((x, i) => ctx.lineTo(x, ys[i]));
    ctx.lineTo(xs[n - 1], bottom);
    ctx.closePath();
    ctx.fillStyle = grad;
    ctx.fill();

    ctx.beginPath();
    xs.forEach((x, i) => (i === 0 ? ctx.moveTo(x, ys[i]) : ctx.lineTo(x, ys[i])));
    ctx.strokeStyle = accent;
    ctx.lineWidth = 2.25;
    ctx.stroke();

    xs.forEach((x, i) => {
      ctx.beginPath();
      ctx.arc(x, ys[i], 3.5, 0, Math.PI * 2);
      ctx.fillStyle = i >= n - 2 ? cssVar("--hot", "#E85D4C") : accent;
      ctx.fill();
      ctx.fillStyle = cssVar("--muted", "#6b736f");
      ctx.font = '10px "IBM Plex Mono", monospace';
      ctx.textAlign = "center";
      ctx.fillText(labels[i], x, h - 6);
    });

    canvas.onpointermove = (e) => {
      const rect = canvas.getBoundingClientRect();
      const px = e.clientX - rect.left;
      let best = 0;
      let bestD = Infinity;
      xs.forEach((x, i) => {
        const d = Math.abs(x - px);
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
  }

  /** Product Head: normalized 0–1 scales; rising pace = deterioration (hot), rising SWOLF = amber. */
  function drawOverlay(canvasId, paceVals, swolfVals, labels) {
    const canvas = document.getElementById(canvasId);
    if (!canvas) return;
    const { ctx, w, h } = resizeCanvas(canvas);
    const top = 22;
    const bottom = h - 22;
    const left = 12;
    const right = w - 12;
    const n = paceVals.length;
    const xs = paceVals.map((_, i) => left + (i * (right - left)) / Math.max(1, n - 1));

    function norm(arr) {
      const { min, max } = padRange(arr, 0);
      return arr.map((v) => (v - min) / Math.max(1e-6, max - min));
    }
    const np = norm(paceVals); // higher pace sec = slower = worse
    const ns = norm(swolfVals);

    ctx.clearRect(0, 0, w, h);
    const accent = cssVar("--accent", "#19B7B0");
    const amber = cssVar("--amber", "#D97706");
    const hot = cssVar("--hot", "#E85D4C");
    const muted = cssVar("--muted", "#6b736f");

    // guide: top = worse (normalized)
    ctx.fillStyle = muted;
    ctx.font = '9px "IBM Plex Mono", monospace';
    ctx.textAlign = "left";
    ctx.fillText("worse ↑", left, 12);
    ctx.fillText("better ↓", left, bottom + 14);

    function strokeSeries(normed, color, width) {
      ctx.beginPath();
      normed.forEach((v, i) => {
        const y = top + (1 - v) * (bottom - top);
        i === 0 ? ctx.moveTo(xs[i], y) : ctx.lineTo(xs[i], y);
      });
      ctx.strokeStyle = color;
      ctx.lineWidth = width;
      ctx.stroke();
    }
    strokeSeries(np, hot, 2.2);
    strokeSeries(ns, amber, 2.0);

    ctx.fillStyle = hot;
    ctx.fillText("pace (↑=slower)", left + 52, 12);
    ctx.fillStyle = amber;
    ctx.fillText("swolf", left + 148, 12);

    xs.forEach((x, i) => {
      ctx.fillStyle = muted;
      ctx.textAlign = "center";
      ctx.fillText(labels[i], x, h - 6);
    });

    canvas.onpointermove = (e) => {
      const rect = canvas.getBoundingClientRect();
      const px = e.clientX - rect.left;
      let best = 0;
      let bestD = Infinity;
      xs.forEach((x, i) => {
        const d = Math.abs(x - px);
        if (d < bestD) {
          bestD = d;
          best = i;
        }
      });
      if (bestD > 28) return hideTip();
      const paceDelta = best === 0 ? 0 : paceVals[best] - paceVals[0];
      const trend =
        paceDelta > 2 ? "deteriorating" : paceDelta < -2 ? "improving" : "holding";
      showTip(
        e.clientX,
        e.clientY,
        `<div class="t-title">${labels[best]} · ${trend}</div>
         <div class="t-mono">pace ${fmtPace(paceVals[best])} · SWOLF ${swolfVals[best]}</div>`
      );
    };
    canvas.onpointerleave = hideTip;
  }

  function render() {
    const iv = activeIntervals();
    const paces = iv.map(paceSec100);
    const labels = iv.map((r, idx) => `I${idx + 1}`);
    const garbageCount = RAW.filter((r) => r.garbage).length;
    const paceFirst = paces[0];
    const paceLate = paces[Math.max(0, paces.length - 2)];
    const paceDecayPct = Math.round(((paceLate - paceFirst) / paceFirst) * 100);
    const swolfDelta = iv[Math.max(0, iv.length - 2)].swolf - iv[0].swolf;
    const avgPace = Math.round(paces.reduce((a, b) => a + b, 0) / paces.length);
    const avgSwolf = Math.round(iv.reduce((a, b) => a + b.swolf, 0) / iv.length);

    main.innerHTML = `
      <section class="sa-block">
        <p class="sa-kicker">Session identity</p>
        <div class="sa-identity">
          <h2>${SESSION.stroke}</h2>
          <span class="sa-distance">${SESSION.distanceM} m</span>
          <p class="sa-when">${SESSION.when} · pool ${SESSION.poolM}m · ${fmtDur(SESSION.durationSec)} moving</p>
        </div>
        <div class="sa-p0">
          <div class="signal">
            <span class="label">Avg pace</span>
            <span class="value">${fmtPace(avgPace)}</span>
            <span class="hint">/100m</span>
          </div>
          <div class="signal">
            <span class="label">Avg SWOLF</span>
            <span class="value">${avgSwolf}</span>
            <span class="hint">Δ ${swolfDelta >= 0 ? "+" : ""}${swolfDelta}</span>
          </div>
          <div class="signal">
            <span class="label">Pace decay</span>
            <span class="value">${paceDecayPct >= 0 ? "+" : ""}${paceDecayPct}%</span>
            <span class="hint">first→late</span>
          </div>
        </div>
        <label class="sa-filter">
          <input type="checkbox" id="garbageToggle" ${includeGarbage ? "checked" : ""} />
          Include filtered laps <span class="mono">(${garbageCount} hidden by invent-guard)</span>
        </label>
      </section>

      <section class="sa-block" id="chartsBlock">
        <p class="sa-kicker">Session charts · synced to table</p>
        <div class="sa-chart-card">
          <div class="chart-head">
            <h3>Pace by interval</h3>
            <span class="caption">s/100m · higher = slower</span>
          </div>
          <div class="chart-canvas-wrap"><canvas id="cPace" height="132"></canvas></div>
        </div>
        <div class="sa-chart-card">
          <div class="chart-head">
            <h3>SWOLF</h3>
            <span class="caption">time + strokes · lower better</span>
          </div>
          <div class="chart-canvas-wrap"><canvas id="cSwolf" height="132"></canvas></div>
        </div>
        <div class="sa-chart-card">
          <div class="chart-head">
            <h3>Strokes per length</h3>
            <span class="caption">count · spike = churn</span>
          </div>
          <div class="chart-canvas-wrap"><canvas id="cStrokes" height="132"></canvas></div>
        </div>
        <div class="sa-chart-card">
          <div class="chart-head">
            <h3>Pace + SWOLF</h3>
            <span class="caption">0–1 normalized · ↑ = worse</span>
          </div>
          <div class="chart-canvas-wrap"><canvas id="cOverlay" height="132"></canvas></div>
        </div>
        <div class="sa-empty-hr">Heart rate — hidden (no sample stream on this session)</div>
      </section>

      <section class="sa-block">
        <p class="sa-kicker">Interval table · same lap set as charts</p>
        <div class="sa-table-wrap">
          <table class="sa-table">
            <thead>
              <tr>
                <th>#</th>
                <th>Dev</th>
                <th>Dist</th>
                <th>Time</th>
                <th>Pace</th>
                <th>Stk</th>
                <th>SWOLF</th>
                <th>Rest</th>
              </tr>
            </thead>
            <tbody>
              ${iv
                .map((row, idx) => {
                  const p = paceSec100(row);
                  const paceCls = p >= paceFirst + 8 ? "hot" : p >= paceFirst + 4 ? "warn" : "";
                  const swCls =
                    row.swolf >= iv[0].swolf + 10
                      ? "hot"
                      : row.swolf >= iv[0].swolf + 5
                        ? "warn"
                        : "";
                  const rowCls = row.garbage ? "garbage" : "";
                  return `<tr class="${rowCls}" data-dev="${displayIndex(row)}">
                    <td>I${idx + 1}</td>
                    <td class="mono">${displayIndex(row)}</td>
                    <td>${row.dist}</td>
                    <td>${row.dur}s</td>
                    <td class="${paceCls}">${fmtPace(p)}</td>
                    <td>${row.strokes}</td>
                    <td class="${swCls}">${row.swolf}</td>
                    <td>${row.rest ? row.rest + "s" : "—"}</td>
                  </tr>`;
                })
                .join("")}
            </tbody>
          </table>
        </div>
        ${
          includeGarbage
            ? `<p class="sa-filter-note">Showing ${garbageCount} filtered laps (amber rows) — charts/table/P0 use the same set.</p>`
            : `<p class="sa-filter-note">Invent-guard hiding ${garbageCount} garbage laps from P0, charts, and table.</p>`
        }
      </section>

      <section class="sa-block">
        <p class="sa-kicker">Diagnoses</p>
        <div class="sa-dx">
          ${SESSION.diagnoses
            .map(
              (d) => `<article class="dx ${d.priority ? "priority" : ""}">
              <span class="tag">${d.tag}</span>
              <h4>${d.title}</h4>
              <p>${d.body}</p>
            </article>`
            )
            .join("")}
        </div>
      </section>

      <section class="sa-block sa-reasoner">
        <p class="sa-kicker">Recommendations + reasoner</p>
        <p class="sa-reasoner-sub">Allow-listed actions · tap to rank (offline demo · Qwen3 in app)</p>
        <div class="sa-recs">
          ${SESSION.recommendations
            .map((r) => {
              const rank = reasonerResult
                ? reasonerResult.ordered.indexOf(r.id) + 1
                : 0;
              const rationale = reasonerResult?.rationale[r.id];
              return `<article class="rec ${rank === 1 ? "top" : ""}" data-rec="${r.id}">
                ${rank ? `<span class="rank">#${rank}</span>` : ""}
                <h4>${r.title}</h4>
                <p>${r.detail}</p>
                <p class="rec-meta mono">via ${
                  r.sourceDiagnosisIds.length
                    ? r.sourceDiagnosisIds.join(", ")
                    : "meta"
                }${rationale ? ` · ${rationale}` : ""}</p>
              </article>`;
            })
            .join("")}
        </div>
        <div class="sa-reasoner-actions">
          <button type="button" class="sa-run-reasoner" id="runReasoner" ${
            reasonerBusy ? "disabled" : ""
          }>
            ${reasonerBusy ? "Running…" : reasonerResult ? "Re-run reasoner" : "Run reasoner"}
          </button>
          <span class="sa-reasoner-hint mono">On demand · never auto</span>
        </div>
        ${
          reasonerResult
            ? `<div class="sa-takeaway">
                <h3>Reasoner · ${reasonerResult.source}</h3>
                <p>${reasonerResult.summary}</p>
                <p class="sa-filter-note">${reasonerResult.notes}</p>
              </div>`
            : `<p class="sa-filter-note">Diagnoses map to allow-listed recs above. Reasoner ranks them — it does not invent new actions.</p>`
        }
      </section>
    `;

    document.getElementById("garbageToggle")?.addEventListener("change", (e) => {
      includeGarbage = e.target.checked;
      render();
    });

    document.getElementById("runReasoner")?.addEventListener("click", () => {
      runReasonerDemo();
    });

    const strokeVals = iv.map((r) => r.strokes);
    const swolfVals = iv.map((r) => r.swolf);
    const barColors = iv.map((r, i) =>
      r.garbage ? cssVar("--amber", "#D97706") : barColor(i, iv.length, Math.floor(iv.length * 0.75))
    );

    drawBars("cPace", paces, labels, {
      fmt: (v) => `${fmtPace(v)} /100m`,
      colors: barColors,
    });
    drawLineArea("cSwolf", swolfVals, labels, { fmt: (v) => `SWOLF ${v}` });
    drawBars("cStrokes", strokeVals, labels, {
      fmt: (v) => `${v} strokes`,
      colors: barColors,
    });
    drawOverlay("cOverlay", paces, swolfVals, labels);
  }

  /** Offline-style ranker demo (mirrors Flutter offline reasoner). */
  function runReasonerDemo() {
    reasonerBusy = true;
    render();
    // Brief delay so the CTA feels like an explicit run, not a static block.
    setTimeout(() => {
      const dxIds = new Set(SESSION.diagnoses.map((d) => d.id));
      const severity = {
        fatigue_onset: 40,
        efficiency_decline: 40,
        stroke_creep: 15,
      };
      const scored = SESSION.recommendations.map((r) => {
        let s = 0;
        const reasons = [];
        for (const id of r.sourceDiagnosisIds) {
          if (!dxIds.has(id)) continue;
          s += 20 + (severity[id] || 10);
          reasons.push(id);
        }
        if (r.id === "log_another_session") s -= 15;
        return {
          id: r.id,
          s,
          why: reasons.length
            ? `Driven by ${reasons.join(", ")}`
            : "Mapped from session evidence",
        };
      });
      scored.sort((a, b) => b.s - a.s);
      const top = scored.slice(0, 3);
      const titles = Object.fromEntries(
        SESSION.recommendations.map((r) => [r.id, r.title])
      );
      reasonerResult = {
        source: "offline",
        summary: `Priority: ${top.map((t) => titles[t.id]).join(" → ")}. Focus on the top item before adding volume.`,
        ordered: scored.map((t) => t.id),
        rationale: Object.fromEntries(scored.map((t) => [t.id, t.why])),
        notes: "Offline reasoner (rules). In the app: Qwen3 0.6B if installed, else this ranker.",
      };
      reasonerBusy = false;
      render();
      document.getElementById("runReasoner")?.scrollIntoView({
        block: "nearest",
        behavior: "smooth",
      });
    }, 420);
  }

  render();
  window.addEventListener("resize", () => render());
})();
