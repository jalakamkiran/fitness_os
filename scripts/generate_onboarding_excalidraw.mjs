#!/usr/bin/env node
/**
 * Generates Excalidraw (.excalidraw) scenes for Fathom onboarding HLD/LLD.
 * Open any file at https://excalidraw.com → File → Open.
 */
import { writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const OUT = join(__dirname, "..", "docs", "onboarding", "diagrams");
mkdirSync(OUT, { recursive: true });

let seed = 1000;
const nextSeed = () => ++seed;
const uid = (prefix) => `${prefix}-${nextSeed()}`;

const COLORS = {
  stroke: "#1e1e1e",
  title: "#1e1e1e",
  flutter: "#a5d8ff",
  native: "#b2f2bb",
  watch: "#ffc9c9",
  store: "#ffec99",
  feature: "#d0bfff",
  core: "#c3fae8",
  external: "#e9ecef",
  accent: "#74c0fc",
  warn: "#ffe3e3",
  frame: "transparent",
};

function base(extra = {}) {
  return {
    angle: 0,
    strokeColor: COLORS.stroke,
    backgroundColor: "transparent",
    fillStyle: "solid",
    strokeWidth: 2,
    strokeStyle: "solid",
    roughness: 0,
    opacity: 100,
    seed: nextSeed(),
    version: 1,
    versionNonce: nextSeed(),
    isDeleted: false,
    groupIds: [],
    frameId: null,
    boundElements: null,
    updated: Date.now(),
    link: null,
    locked: false,
    ...extra,
  };
}

function rect(id, x, y, w, h, bg, opts = {}) {
  return {
    ...base(),
    id,
    type: "rectangle",
    x,
    y,
    width: w,
    height: h,
    backgroundColor: bg,
    roundness: { type: 3 },
    boundElements: [],
    ...opts,
  };
}

function ellipse(id, x, y, w, h, bg) {
  return {
    ...base(),
    id,
    type: "ellipse",
    x,
    y,
    width: w,
    height: h,
    backgroundColor: bg,
    boundElements: [],
  };
}

function diamond(id, x, y, w, h, bg) {
  return [
    {
      ...base(),
      id,
      type: "diamond",
      x,
      y,
      width: w,
      height: h,
      backgroundColor: bg,
      boundElements: [],
    },
  ];
}

function text(id, x, y, label, opts = {}) {
  const fontSize = opts.fontSize ?? 16;
  const lines = String(label).split("\n");
  const width = opts.width ?? Math.max(...lines.map((l) => l.length)) * (fontSize * 0.55);
  const height = opts.height ?? lines.length * fontSize * 1.25;
  return {
    ...base({ strokeWidth: 1, backgroundColor: "transparent" }),
    id,
    type: "text",
    x,
    y,
    width,
    height,
    text: label,
    originalText: label,
    fontSize,
    fontFamily: 2, // Helvetica — readable for architecture docs
    textAlign: opts.textAlign ?? "center",
    verticalAlign: opts.verticalAlign ?? "middle",
    containerId: opts.containerId ?? null,
    autoResize: true,
    lineHeight: 1.25,
    ...opts,
  };
}

/** Labeled box: rectangle + centered bound text */
function box(id, x, y, w, h, label, bg) {
  const tid = `${id}-t`;
  const r = rect(id, x, y, w, h, bg);
  const t = text(tid, x + 8, y + h / 2 - 12, label, {
    width: w - 16,
    height: Math.max(24, h - 16),
    containerId: id,
    fontSize: label.includes("\n") ? 14 : 16,
  });
  r.boundElements = [{ id: tid, type: "text" }];
  return [r, t];
}

function title(id, x, y, label, size = 28) {
  return text(id, x, y, label, {
    fontSize: size,
    textAlign: "left",
    width: Math.max(200, label.length * size * 0.55),
    height: size * 1.4,
  });
}

function subtitle(id, x, y, label) {
  return text(id, x, y, label, {
    fontSize: 14,
    textAlign: "left",
    strokeColor: "#495057",
    width: Math.max(200, label.length * 8),
    height: 22,
  });
}

function arrow(id, x1, y1, x2, y2, label, opts = {}) {
  const dx = x2 - x1;
  const dy = y2 - y1;
  const els = [];
  const a = {
    ...base({ strokeWidth: opts.strokeWidth ?? 2 }),
    id,
    type: "arrow",
    x: x1,
    y: y1,
    width: dx,
    height: dy,
    points: [
      [0, 0],
      [dx, dy],
    ],
    startArrowhead: opts.startArrowhead ?? null,
    endArrowhead: opts.endArrowhead ?? "arrow",
    startBinding: opts.startBinding ?? null,
    endBinding: opts.endBinding ?? null,
    lastCommittedPoint: null,
  };
  els.push(a);
  if (label) {
    const mx = (x1 + x2) / 2;
    const my = (y1 + y2) / 2;
    els.push(
      text(`${id}-lbl`, mx - label.length * 3.5, my - 22, label, {
        fontSize: 12,
        strokeColor: "#495057",
        width: label.length * 7.5,
        height: 18,
        textAlign: "center",
      }),
    );
  }
  return els;
}

function connect(fromId, toId, fx, fy, tx, ty, label, opts = {}) {
  const id = uid("arr");
  return arrow(
    id,
    fx,
    fy,
    tx,
    ty,
    label,
    {
      startBinding: { elementId: fromId, focus: 0, gap: 4 },
      endBinding: { elementId: toId, focus: 0, gap: 4 },
      ...opts,
    },
  );
}

function frame(id, x, y, w, h, name) {
  return {
    ...base({ strokeWidth: 1, strokeStyle: "dashed", strokeColor: "#868e96" }),
    id,
    type: "frame",
    x,
    y,
    width: w,
    height: h,
    name,
    backgroundColor: "transparent",
  };
}

function scene(elements) {
  return {
    type: "excalidraw",
    version: 2,
    source: "https://excalidraw.com",
    elements,
    appState: {
      gridSize: 20,
      viewBackgroundColor: "#ffffff",
    },
    files: {},
  };
}

function write(name, elements) {
  const path = join(OUT, name);
  writeFileSync(path, JSON.stringify(scene(elements), null, 2));
  console.log(`wrote ${path} (${elements.length} elements)`);
}

// ─────────────────────────────────────────────────────────────
// 1) HLD — System context
// ─────────────────────────────────────────────────────────────
function hldSystemContext() {
  const e = [];
  e.push(title("t1", 40, 20, "Fathom HLD — System Context"));
  e.push(
    subtitle(
      "s1",
      40,
      60,
      "Android companion for Huawei GT5-A07 · Direct LPv2 RFCOMM · Local-first",
    ),
  );

  e.push(...box("watch", 80, 140, 200, 90, "Huawei Watch\nGT5-A07", COLORS.watch));
  e.push(...box("native", 380, 140, 240, 90, "Android Native\nHuawei LPv2 stack", COLORS.native));
  e.push(...box("flutter", 720, 140, 240, 90, "Flutter App\n(Fathom / fitness_os)", COLORS.flutter));
  e.push(...box("local", 720, 320, 240, 90, "Local Persist\nprefs + side-files", COLORS.store));
  e.push(...box("sentry", 380, 320, 200, 80, "Sentry\n(optional)", COLORS.external));
  e.push(...box("gemma", 80, 320, 200, 80, "On-device\nQwen3 / Gemma", COLORS.external));

  e.push(...connect("watch", "native", 280, 185, 380, 185, "RFCOMM LPv2"));
  e.push(...connect("native", "flutter", 620, 185, 720, 185, "Method/EventChannel"));
  e.push(...connect("flutter", "local", 840, 230, 840, 320, "read/write"));
  e.push(...connect("flutter", "sentry", 720, 230, 520, 320, "crash/sync"));
  e.push(...connect("flutter", "gemma", 720, 230, 280, 320, "Swim Bible reasoner"));

  e.push(
    subtitle(
      "note1",
      40,
      440,
      "No Huawei Health Kit runtime. Secrets stay in native HuaweiSecretStore — never Flutter prefs.",
    ),
  );
  return e;
}

// ─────────────────────────────────────────────────────────────
// 2) HLD — Layered architecture
// ─────────────────────────────────────────────────────────────
function hldLayers() {
  const e = [];
  e.push(title("t2", 40, 20, "Fathom HLD — Layered Architecture"));
  e.push(subtitle("s2", 40, 60, "Presentation → Domain → Data → Core bridge → Native"));

  const layers = [
    { id: "Lpres", y: 110, label: "Presentation\nBLoC + Screens (Home / Recovery / Workouts / Pairing)", bg: COLORS.flutter },
    { id: "Ldom", y: 230, label: "Domain\nRepositories · Entities · Use cases", bg: COLORS.feature },
    { id: "Ldata", y: 350, label: "Data\nRepositoryImpl · Prefs · Side-files · Channel wrappers", bg: COLORS.core },
    { id: "Lcore", y: 470, label: "Core\nHuaweiLink · HuaweiBtChannel · DI · StoreInvalidation · Sentry", bg: COLORS.accent },
    { id: "Lnat", y: 590, label: "Android Native\nHuaweiBtPlugin · Session · Framing · Sync · Secrets", bg: COLORS.native },
  ];
  for (const L of layers) {
    e.push(...box(L.id, 80, L.y, 900, 90, L.label, L.bg));
  }
  for (let i = 0; i < layers.length - 1; i++) {
    e.push(
      ...connect(
        layers[i].id,
        layers[i + 1].id,
        530,
        layers[i].y + 90,
        530,
        layers[i + 1].y,
        "",
      ),
    );
  }
  e.push(
    subtitle(
      "note2",
      40,
      710,
      "Each feature under lib/features/{name}/ owns data/domain/presentation + *_di.dart",
    ),
  );
  return e;
}

// ─────────────────────────────────────────────────────────────
// 3) HLD — Feature module map
// ─────────────────────────────────────────────────────────────
function hldFeatureMap() {
  const e = [];
  e.push(title("t3", 40, 20, "Fathom HLD — Feature Module Map"));
  e.push(subtitle("s3", 40, 60, "Shell tabs + feature packages wired via GetIt"));

  e.push(...box("shell", 360, 110, 280, 70, "AppShell\nHome | Recovery | Workouts", COLORS.flutter));

  e.push(...box("home", 40, 240, 200, 110, "home\nKPIs · Sync CTA\nprecedence states", COLORS.feature));
  e.push(...box("vitals", 280, 240, 200, 110, "vitals\nSleep · HR · FT\nauto-tracking", COLORS.feature));
  e.push(...box("wh", 520, 240, 200, 110, "workout_history\nGate B · Swim Bible\ncharts · coach", COLORS.feature));
  e.push(...box("pair", 760, 240, 200, 110, "device_pairing\nGate A · scan\nremember · Forget", COLORS.feature));

  e.push(...box("diag", 280, 400, 200, 80, "diagnostics\nJSON export", COLORS.external));
  e.push(...box("link", 520, 400, 200, 80, "HuaweiLink\n(singleton)", COLORS.core));
  e.push(...box("prefs", 760, 400, 200, 80, "SharedPreferences\n+ side-files", COLORS.store));

  e.push(...connect("shell", "home", 400, 180, 140, 240, ""));
  e.push(...connect("shell", "vitals", 500, 180, 380, 240, ""));
  e.push(...connect("shell", "wh", 560, 180, 620, 240, ""));
  e.push(...connect("home", "link", 140, 350, 520, 400, ""));
  e.push(...connect("vitals", "link", 380, 350, 560, 400, ""));
  e.push(...connect("wh", "link", 620, 350, 620, 400, ""));
  e.push(...connect("pair", "link", 860, 350, 720, 400, "owns register"));
  e.push(...connect("vitals", "prefs", 480, 295, 760, 420, ""));
  e.push(...connect("wh", "prefs", 720, 295, 820, 400, ""));
  e.push(...connect("diag", "prefs", 480, 440, 760, 440, "export"));
  return e;
}

// ─────────────────────────────────────────────────────────────
// 4) HLD — User interaction / Sync planes
// ─────────────────────────────────────────────────────────────
function hldUserFlows() {
  const e = [];
  e.push(title("t4", 40, 20, "Fathom HLD — User Journeys & Sync Planes"));

  // Journey column
  e.push(title("t4a", 40, 80, "Primary user journey", 20));
  const steps = [
    ["u1", "Open app / splash"],
    ["u2", "Pair GT5 (Gate A)\nor reconnect remembered"],
    ["u3", "Auto-sync pass\nworkouts → vitals"],
    ["u4", "Home: today KPIs\n+ swim takeaway"],
    ["u5", "Recovery: sleep/HR\nWorkouts: Swim Bible"],
  ];
  steps.forEach((s, i) => {
    const y = 130 + i * 100;
    e.push(...box(s[0], 60, y, 260, 70, s[1], COLORS.flutter));
    if (i > 0) {
      e.push(...connect(steps[i - 1][0], s[0], 190, y - 30, 190, y, ""));
    }
  });

  // Sync planes
  e.push(title("t4b", 420, 80, "Sync data planes", 20));
  e.push(...box("ga", 420, 130, 220, 70, "Gate A\npair · auth · remember", COLORS.warn));
  e.push(...box("gb", 420, 240, 220, 70, "Gate B workouts\nCount → Totals → enrich", COLORS.native));
  e.push(...box("act", 420, 350, 220, 70, "Activity / Vitals\nsleep · HR · FitnessTotals", COLORS.core));
  e.push(...box("bible", 420, 460, 220, 70, "Swim Bible v0\nEvidence → Dx → Recs", COLORS.feature));
  e.push(...box("ui", 700, 300, 200, 80, "UI Charts\nHome / Recovery / Detail", COLORS.flutter));

  e.push(...connect("ga", "gb", 530, 200, 530, 240, ""));
  e.push(...connect("ga", "act", 530, 200, 470, 350, ""));
  e.push(...connect("gb", "bible", 530, 310, 530, 460, "canonical swim"));
  e.push(...connect("gb", "ui", 640, 275, 700, 330, ""));
  e.push(...connect("act", "ui", 640, 385, 700, 350, ""));
  e.push(...connect("bible", "ui", 640, 495, 800, 380, ""));
  return e;
}

// ─────────────────────────────────────────────────────────────
// 5) LLD — Bootstrap & DI
// ─────────────────────────────────────────────────────────────
function lldBootstrap() {
  const e = [];
  e.push(title("t5", 40, 20, "LLD — Bootstrap & Dependency Injection"));
  e.push(subtitle("s5", 40, 60, "lib/main.dart → bootstrap → GetIt → routes → FitnessOsApp"));

  const nodes = [
    ["m", 80, 120, "main.dart"],
    ["b", 80, 220, "bootstrap()\nSentry? · Gemma · DI"],
    ["di", 80, 340, "initDependencies()\ninjector.dart"],
    ["rr", 80, 460, "RouteRegistry\n.registerAll()"],
    ["app", 80, 560, "FitnessOsApp\n+ AutoSyncLifecycle"],
  ];
  for (const [id, x, y, label] of nodes) {
    e.push(...box(id, x, y, 280, 70, label, COLORS.flutter));
  }
  for (let i = 1; i < nodes.length; i++) {
    e.push(...connect(nodes[i - 1][0], nodes[i][0], 220, nodes[i - 1][2] + 70, 220, nodes[i][2], ""));
  }

  e.push(title("t5b", 420, 120, "DI registration order", 18));
  const order = [
    "1. StoreInvalidation",
    "2. device_pairing (+ HuaweiLink)",
    "3. workout_history",
    "4. vitals (Forget wipe hook)",
    "5. diagnostics (export + wipe)",
    "6. OneShotAutoSync",
    "7. home",
  ];
  order.forEach((line, i) => {
    e.push(...box(`di${i}`, 420, 160 + i * 70, 360, 55, line, i === 1 ? COLORS.core : COLORS.feature));
  });
  return e;
}

// ─────────────────────────────────────────────────────────────
// 6) LLD — Huawei native stack
// ─────────────────────────────────────────────────────────────
function lldHuaweiNative() {
  const e = [];
  e.push(title("t6", 40, 20, "LLD — Android Huawei Native Stack"));
  e.push(subtitle("s6", 40, 60, "android/.../huawei/ · channel contract · session orchestration"));

  e.push(...box("plugin", 360, 110, 280, 70, "HuaweiBtPlugin\nMethod + EventChannel", COLORS.native));
  e.push(...box("rfcomm", 40, 240, 220, 70, "RfcommTransport\nBLE discover → RFCOMM", COLORS.native));
  e.push(...box("secrets", 700, 240, 220, 70, "HuaweiSecretStore\nnative-only secrets", COLORS.store));
  e.push(...box("session", 360, 240, 280, 70, "HuaweiSession\nauth + sync entry", COLORS.accent));

  e.push(...box("frame", 40, 380, 180, 70, "HuaweiFraming\nLPv2 TLV", COLORS.core));
  e.push(...box("crypto", 240, 380, 180, 70, "PacketCrypto", COLORS.core));
  e.push(...box("auth", 440, 380, 200, 70, "NormalAuth /\nHiChain", COLORS.core));
  e.push(...box("lock", 680, 380, 200, 70, "HuaweiSyncLock\nsingle-flight", COLORS.warn));

  e.push(...box("upload", 40, 520, 180, 70, "FeatureUpload", COLORS.feature));
  e.push(...box("wosync", 240, 520, 200, 70, "WorkoutSync\n0x17 / 0x0e/0a/0c", COLORS.feature));
  e.push(...box("fit", 460, 520, 200, 70, "FitnessDataSync\nsleep/HR/FT", COLORS.feature));
  e.push(...box("fdl", 680, 520, 200, 70, "FileDownload\nTruSleep", COLORS.feature));

  e.push(...connect("plugin", "session", 500, 180, 500, 240, ""));
  e.push(...connect("plugin", "rfcomm", 360, 180, 150, 240, ""));
  e.push(...connect("plugin", "secrets", 640, 180, 810, 240, ""));
  e.push(...connect("session", "frame", 400, 310, 130, 380, ""));
  e.push(...connect("session", "crypto", 460, 310, 330, 380, ""));
  e.push(...connect("session", "auth", 520, 310, 540, 380, ""));
  e.push(...connect("session", "lock", 580, 310, 780, 380, ""));
  e.push(...connect("session", "upload", 400, 310, 130, 520, ""));
  e.push(...connect("session", "wosync", 460, 310, 340, 520, ""));
  e.push(...connect("session", "fit", 520, 310, 560, 520, ""));
  e.push(...connect("session", "fdl", 580, 310, 780, 520, ""));
  return e;
}

// ─────────────────────────────────────────────────────────────
// 7) LLD — Flutter Huawei bridge
// ─────────────────────────────────────────────────────────────
function lldHuaweiFlutter() {
  const e = [];
  e.push(title("t7", 40, 20, "LLD — Flutter Huawei Bridge"));
  e.push(subtitle("s7", 40, 60, "lib/core/huawei/ · typed API over MethodChannel"));

  e.push(...box("ui", 80, 120, 200, 70, "Repos / BLoCs", COLORS.flutter));
  e.push(...box("repos", 360, 120, 240, 70, "Feature Repositories", COLORS.feature));
  e.push(...box("link", 360, 250, 240, 90, "HuaweiLink\nLinkState · DTOs\nsyncWorkouts/Activity", COLORS.core));
  e.push(...box("ch", 360, 400, 240, 70, "HuaweiBtChannel\nfitness_os/huawei_bt", COLORS.accent));
  e.push(...box("nat", 360, 530, 240, 70, "Native Plugin", COLORS.native));
  e.push(...box("osa", 700, 250, 240, 90, "OneShotAutoSync\nworkouts → vitals\non open/resume", COLORS.warn));

  e.push(...connect("ui", "repos", 280, 155, 360, 155, ""));
  e.push(...connect("repos", "link", 480, 190, 480, 250, ""));
  e.push(...connect("link", "ch", 480, 340, 480, 400, ""));
  e.push(...connect("ch", "nat", 480, 470, 480, 530, ""));
  e.push(...connect("osa", "repos", 700, 295, 600, 155, "trigger"));

  const methods = [
    "ensurePermissions / startScan",
    "connectAndAuthenticate(mac)",
    "reconnect(mac)",
    "syncWorkouts / syncActivity",
    "enableAutoTracking",
  ];
  e.push(title("t7b", 40, 250, "Key Link APIs", 16));
  methods.forEach((m, i) => {
    e.push(...box(`api${i}`, 40, 290 + i * 55, 260, 45, m, COLORS.external));
  });
  return e;
}

// ─────────────────────────────────────────────────────────────
// 8) LLD — Gate A pairing flow
// ─────────────────────────────────────────────────────────────
function lldGateA() {
  const e = [];
  e.push(title("t8", 40, 20, "LLD — Gate A Pairing Flow"));
  e.push(subtitle("s8", 40, 60, "device_pairing · prove reconnect after kill / reboot / BT toggle"));

  const flow = [
    ["g1", "Request BT/location\npermissions"],
    ["g2", "BLE scan for\nGT5 name"],
    ["g3", "RFCOMM connect\n+ authenticate"],
    ["g4", "Feature upload\nstabilize session"],
    ["g5", "Persist remembered MAC\nGateAPrefs.gateAPassed"],
    ["g6", "LinkState.connected\n(ready for sync)"],
  ];
  flow.forEach((f, i) => {
    const x = 60 + (i % 3) * 320;
    const y = 120 + Math.floor(i / 3) * 160;
    e.push(...box(f[0], x, y, 260, 90, f[1], i < 3 ? COLORS.native : COLORS.feature));
  });
  e.push(...connect("g1", "g2", 320, 165, 380, 165, ""));
  e.push(...connect("g2", "g3", 640, 165, 700, 165, ""));
  e.push(...connect("g3", "g4", 830, 210, 190, 280, ""));
  e.push(...connect("g4", "g5", 320, 325, 380, 325, ""));
  e.push(...connect("g5", "g6", 640, 325, 700, 325, ""));

  e.push(...box("dec", 360, 460, 280, 80, "Reconnect path\nremembered MAC + secrets?", COLORS.warn));
  e.push(...box("ok", 80, 580, 220, 70, "Yes → reconnect()\nskip full pair", COLORS.core));
  e.push(...box("no", 680, 580, 220, 70, "No → full Gate A\nor setAuthKey recovery", COLORS.warn));
  e.push(...connect("dec", "ok", 400, 540, 190, 580, ""));
  e.push(...connect("dec", "no", 600, 540, 790, 580, ""));
  return e;
}

// ─────────────────────────────────────────────────────────────
// 9) LLD — Sync pass (workouts + vitals)
// ─────────────────────────────────────────────────────────────
function lldSyncPass() {
  const e = [];
  e.push(title("t9", 40, 20, "LLD — Sync Pass (Workouts then Vitals)"));
  e.push(subtitle("s9", 40, 60, "OneShotAutoSync + Home.syncNow · native HuaweiSyncLock"));

  e.push(...box("trig", 80, 120, 220, 70, "Trigger\nresume / sessionReady\n/ Sync CTA", COLORS.flutter));
  e.push(...diamond("gate", 360, 110, 160, 90, COLORS.warn));
  e.push(text("gate-t", 385, 140, "Gate A\npassed?", { fontSize: 14, width: 110, height: 40 }));
  e.push(...box("busy", 600, 120, 200, 70, "syncInFlight /\nnative busy?", COLORS.warn));
  e.push(...box("wo", 80, 280, 280, 80, "WorkoutHistoryRepository\n.syncFromWatch()", COLORS.feature));
  e.push(...box("vi", 420, 280, 280, 80, "VitalsRepository\n.syncFromWatch()", COLORS.feature));
  e.push(...box("hl", 250, 420, 280, 70, "HuaweiLink → Native Sync", COLORS.core));
  e.push(...box("store", 80, 540, 280, 70, "Persist\nworkouts_json + canonical", COLORS.store));
  e.push(...box("vstore", 420, 540, 280, 70, "Persist\nsleep/HR/FT + side-files", COLORS.store));
  e.push(...box("si", 250, 660, 280, 70, "StoreInvalidation.notify\n→ BLoCs reload", COLORS.accent));

  e.push(...connect("trig", "gate", 300, 155, 360, 155, ""));
  e.push(...connect("gate", "wo", 440, 200, 220, 280, "yes"));
  e.push(...connect("wo", "vi", 360, 320, 420, 320, "then"));
  e.push(...connect("wo", "hl", 220, 360, 320, 420, ""));
  e.push(...connect("vi", "hl", 560, 360, 460, 420, ""));
  e.push(...connect("hl", "store", 300, 490, 220, 540, ""));
  e.push(...connect("hl", "vstore", 480, 490, 560, 540, ""));
  e.push(...connect("store", "si", 220, 610, 320, 660, ""));
  e.push(...connect("vstore", "si", 560, 610, 460, 660, ""));
  return e;
}

// ─────────────────────────────────────────────────────────────
// 10) LLD — Feature internals (per module)
// ─────────────────────────────────────────────────────────────
function lldFeatureInternals() {
  const e = [];
  e.push(title("t10", 40, 20, "LLD — Feature Internals (Clean Architecture)"));
  e.push(subtitle("s10", 40, 60, "Same pattern in each lib/features/{name}/"));

  const modules = [
    {
      name: "device_pairing",
      x: 40,
      items: ["DevicePairingBloc", "DevicePairingRepository", "GateAPrefs", "RememberedDevice"],
    },
    {
      name: "home",
      x: 280,
      items: ["HomeBloc", "HomeRepository", "HomePrecedence", "GetHomeData"],
    },
    {
      name: "vitals",
      x: 520,
      items: ["VitalsBloc", "VitalsRepository", "VitalsSnapshot", "Sleep* screens"],
    },
    {
      name: "workout_history",
      x: 760,
      items: ["WorkoutHistoryBloc", "CanonicalSwimStore", "SwimReasoner", "P0 metrics"],
    },
  ];

  for (const m of modules) {
    e.push(...box(`${m.name}-h`, m.x, 110, 220, 50, m.name, COLORS.feature));
    e.push(...box(`${m.name}-p`, m.x, 180, 220, 55, "presentation/", COLORS.flutter));
    e.push(...box(`${m.name}-d`, m.x, 250, 220, 55, "domain/", COLORS.accent));
    e.push(...box(`${m.name}-a`, m.x, 320, 220, 55, "data/ + *_di.dart", COLORS.core));
    m.items.forEach((item, i) => {
      e.push(
        ...box(`${m.name}-i${i}`, m.x, 400 + i * 55, 220, 45, item, COLORS.external),
      );
    });
    e.push(...connect(`${m.name}-p`, `${m.name}-d`, m.x + 110, 235, m.x + 110, 250, ""));
    e.push(...connect(`${m.name}-d`, `${m.name}-a`, m.x + 110, 305, m.x + 110, 320, ""));
  }
  return e;
}

// ─────────────────────────────────────────────────────────────
// 11) LLD — Persistence map
// ─────────────────────────────────────────────────────────────
function lldPersistence() {
  const e = [];
  e.push(title("t11", 40, 20, "LLD — Persistence Map"));
  e.push(subtitle("s11", 40, 60, "What lives where — Flutter prefs vs side-files vs native secrets"));

  e.push(...box("prefs", 60, 120, 320, 280, "SharedPreferences\n· Gate A identity / status\n· workouts_json\n· sleep_sessions_json\n· daily_hr_json\n· fitness_totals_day_json\n· home sync status\n· coach settings", COLORS.store));
  e.push(...box("side", 420, 120, 320, 280, "App support side-files\n(no-backup)\n· vitals/hr_series/\n· vitals/sleep_stages/\n· vitals/sleep_enrich/\n· vitals/sleep_files/\n· workouts/canonical_swim/", COLORS.core));
  e.push(...box("nat", 780, 120, 280, 180, "Native only\nHuaweiSecretStore\n· auth keys\n· pairing secrets\nNEVER in Flutter", COLORS.warn));
  e.push(...box("inv", 780, 340, 280, 60, "StoreInvalidation bus", COLORS.accent));
  return e;
}

// ─────────────────────────────────────────────────────────────
// 12) LLD — Navigation / routes
// ─────────────────────────────────────────────────────────────
function lldNavigation() {
  const e = [];
  e.push(title("t12", 40, 20, "LLD — Navigation & Routes"));
  e.push(subtitle("s12", 40, 60, "MaterialApp.routes via AppRouter — not go_router"));

  e.push(...box("root", 360, 110, 240, 60, "/  → AppShell", COLORS.flutter));
  e.push(...box("h", 40, 240, 200, 60, "/home", COLORS.feature));
  e.push(...box("r", 280, 240, 200, 60, "Recovery tab\n(Vitals|Sleep)", COLORS.feature));
  e.push(...box("w", 520, 240, 200, 60, "Workouts tab", COLORS.feature));
  e.push(...box("p", 760, 240, 200, 60, "/device_pairing", COLORS.feature));

  e.push(...box("sd", 160, 360, 200, 55, "/sleep_detail", COLORS.external));
  e.push(...box("sh", 160, 430, 200, 55, "/sleep_history", COLORS.external));
  e.push(...box("wd", 520, 360, 200, 55, "/workout_detail", COLORS.external));
  e.push(...box("cs", 520, 430, 200, 55, "/coach_settings", COLORS.external));
  e.push(...box("whr", 520, 500, 200, 55, "/workout_history", COLORS.external));

  e.push(...connect("root", "h", 400, 170, 140, 240, ""));
  e.push(...connect("root", "r", 480, 170, 380, 240, ""));
  e.push(...connect("root", "w", 540, 170, 620, 240, ""));
  e.push(...connect("r", "sd", 380, 300, 260, 360, ""));
  e.push(...connect("r", "sh", 380, 300, 260, 430, ""));
  e.push(...connect("w", "wd", 620, 300, 620, 360, ""));
  e.push(...connect("w", "cs", 620, 300, 620, 430, ""));
  e.push(...connect("w", "whr", 620, 300, 620, 500, ""));
  return e;
}

const diagrams = {
  "01-hld-system-context.excalidraw": hldSystemContext,
  "02-hld-layered-architecture.excalidraw": hldLayers,
  "03-hld-feature-module-map.excalidraw": hldFeatureMap,
  "04-hld-user-journeys-sync-planes.excalidraw": hldUserFlows,
  "05-lld-bootstrap-di.excalidraw": lldBootstrap,
  "06-lld-huawei-native-stack.excalidraw": lldHuaweiNative,
  "07-lld-huawei-flutter-bridge.excalidraw": lldHuaweiFlutter,
  "08-lld-gate-a-pairing.excalidraw": lldGateA,
  "09-lld-sync-pass.excalidraw": lldSyncPass,
  "10-lld-feature-internals.excalidraw": lldFeatureInternals,
  "11-lld-persistence-map.excalidraw": lldPersistence,
  "12-lld-navigation-routes.excalidraw": lldNavigation,
};

for (const [name, fn] of Object.entries(diagrams)) {
  write(name, fn());
}

console.log(`\nGenerated ${Object.keys(diagrams).length} Excalidraw diagrams in ${OUT}`);
