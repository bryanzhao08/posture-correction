import "./style.css";
import profilesJson from "../../shared/sport_profiles.json";
import catalogJson from "../../shared/cue_catalog.json";
import { effectiveProfile, type EngineEvent, type Joint, type Recording, type Rep } from "./engine/engine.ts";
import { summarize, targetFor, type Summary } from "./engine/scoring.ts";
import { CameraSession, SampleSession, drawSkeleton, type SessionOptions } from "./app/session.ts";
import { clearSessions, deleteSession, listSessions, pref, saveSession, setPref, storageIsPersistent,
         type StoredSession } from "./app/store.ts";
import { loadPose } from "./app/pose.ts";
import { buildCard, drawCard, shortLabel, type FixCard } from "./app/fixcard.ts";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const profiles: any = profilesJson;
interface CueInfo { key: string; sport: string; metric: string; view: string | null; text: string; meaning: string;
                    wrong_motion: string; correct_motion: string }
const catalog = catalogJson as CueInfo[];

const SPORTS = ["golf", "basketball", "tennis", "pickleball"] as const;
const ICONS: Record<string, string> = { golf: "⛳", basketball: "🏀", tennis: "🎾", pickleball: "🏓" };
const VIEW_LABEL: Record<string, string> = { front: "Front", side: "Side", back: "Behind" };
const STATE_LABEL: Record<string, string> = {
  no_person: "Step into view", moving: "Get set — hold still a moment", ready: "Ready", active: "Swing detected…",
};
const REJECT_LABEL: Record<string, string> = {
  too_short: "too quick to be a full swing", too_long: "too long, looked like walking or fidgeting",
  too_slow: "not fast enough", too_small: "too small a movement", one_way: "a one-way movement, not a swing",
  bad_start: "hands started too high", not_high_enough: "hands didn't get high enough",
  bad_pattern: "didn't match the shape of this movement", lost_tracking: "lost sight of you mid-motion",
  no_metrics: "not enough of you visible to score",
};
const SESSION_CHECKPOINT = 5;
const UNIT: Record<string, string> = { deg: "°", s: " s" };

const app = document.getElementById("app")!;
const esc = (s: unknown) => String(s ?? "").replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);
const fmt = (v: number | null | undefined, d = 0) => (v == null || !isFinite(v) ? "—" : v.toFixed(d));
let teardown: (() => void) | null = null;

interface Setup { sport: string; training: string | null; view: string; stroke: "forehand" | "backhand" }
const setup: Setup = { sport: "golf", training: null, view: "front", stroke: "forehand" };

function sportProfile(sport: string, view?: string) {
  return effectiveProfile(profiles.sports[sport], view ?? profiles.sports[sport].default_view ?? "front");
}

function focusFor(s: Setup): string | null {
  if (s.sport !== "tennis") return null;
  if (s.training === "serve") return "serve";
  return s.view === "side" ? s.stroke : null;
}

function cueInfo(sport: string, text: string): CueInfo | undefined {
  return catalog.find((c) => c.text === text && (c.sport === sport || c.sport === "racket"))
    ?? catalog.find((c) => c.text === text);
}

function go(screen: () => void | Promise<void>) {
  teardown?.();
  teardown = null;
  window.scrollTo(0, 0);
  void screen();
}

// ---------------------------------------------------------------- home
async function home() {
  const sessions = await listSessions();
  const hand = pref<string>("handedness", "right");
  app.innerHTML = `
  <main class="page">
    <header class="brand">
      <div class="logo">FC</div>
      <div><h1>FormCoach</h1><p class="muted">Web demo · counts your real swings and scores them against pros</p></div>
    </header>
    <section class="notice">
      <strong>Runs entirely in your browser.</strong> Your camera video never leaves this device, and sessions
      are saved only in this browser. Put your phone on a tripod (or lean it on something) a few metres away.
    </section>
    <h2>Choose a sport</h2>
    <div class="grid sports">
      ${SPORTS.map((s) => `<button class="card sport" data-sport="${s}">
          <span class="icon">${ICONS[s]}</span><span class="name">${esc(profiles.sports[s].label)}</span>
          <span class="muted small">${sessions.filter((x) => x.sport === s).length} saved sessions</span></button>`).join("")}
    </div>
    <div class="row between settings">
      <label>I play with my
        <select id="hand"><option value="right" ${hand === "right" ? "selected" : ""}>right hand</option>
        <option value="left" ${hand === "left" ? "selected" : ""}>left hand</option></select></label>
      <button class="btn ghost" id="history">History & averages${sessions.length ? ` (${sessions.length})` : ""}</button>
    </div>
    <footer class="muted small">
      FormCoach is an iOS app; this is its browser demo with the same counting and scoring engine, checked against
      the reference implementation. Accounts, email checkpoints and 3D coaching demos are in the iPhone app.
      <a href="https://github.com/bryanzhao08/posture-correction" target="_blank" rel="noopener">Source on GitHub</a>
    </footer>
  </main>`;
  app.querySelectorAll<HTMLButtonElement>("[data-sport]").forEach((b) => b.onclick = () => {
    setup.sport = b.dataset.sport!;
    const p = profiles.sports[setup.sport];
    setup.training = p.training ? p.training[0].id : null;
    setup.view = p.training ? p.training[0].recommended : (p.default_view ?? "front");
    go(preSession);
  });
  (app.querySelector("#hand") as HTMLSelectElement).onchange = (e) => setPref("handedness", (e.target as HTMLSelectElement).value);
  (app.querySelector("#history") as HTMLButtonElement).onclick = () => go(history);
  void loadPose().catch(() => undefined); // warm up the model while the user reads
}

// ---------------------------------------------------------------- pre-session
function preSession() {
  const base = profiles.sports[setup.sport];
  const prof = sportProfile(setup.sport, setup.view);
  const trainings: { id: string; label: string; recommended: string; views: string[]; why: string }[] = base.training ?? [];
  const tr = trainings.find((t) => t.id === setup.training);
  const showStroke = setup.sport === "tennis" && setup.view === "side" && setup.training !== "serve";
  app.innerHTML = `
  <main class="page">
    <button class="btn link" id="back">← Back</button>
    <h1>${ICONS[setup.sport]} ${esc(base.label)}</h1>
    ${trainings.length ? `
      <h2>What are you working on?</h2>
      <div class="chips">${trainings.map((t) => `<button class="chip ${t.id === setup.training ? "on" : ""}" data-training="${t.id}">${esc(t.label)}</button>`).join("")}</div>
      <h2>Camera position</h2>
      <div class="chips">${tr!.views.map((v) => `<button class="chip ${v === setup.view ? "on" : ""}" data-view="${v}">${VIEW_LABEL[v]}${v === tr!.recommended ? " · recommended" : ""}</button>`).join("")}</div>
      <p class="muted">${esc(tr!.why)}</p>
      ${showStroke ? `<h2>Stroke</h2><div class="chips">${(["forehand", "backhand"] as const).map((s) =>
        `<button class="chip ${s === setup.stroke ? "on" : ""}" data-stroke="${s}">${s[0].toUpperCase() + s.slice(1)}</button>`).join("")}</div>
        <p class="muted small">Side-on, forehands and backhands look alike to the camera, so tell it which one you're practising.</p>` : ""}
    ` : ""}
    <section class="card setup">
      <h3>Set up your camera</h3>
      <p>${esc(prof.camera)}</p>
      <p class="muted small">Your whole body, head to feet, needs to be in the picture. Good light helps a lot.</p>
    </section>
    <section class="card">
      <h3>What gets scored</h3>
      <ul class="metric-list">${prof.metrics.map((m: { label: string }) => `<li>${esc(m.label)}</li>`).join("")}</ul>
    </section>
    <div class="actions">
      <button class="btn primary big" id="start">Start session</button>
      <div class="row gap">
        <label class="small"><input type="checkbox" id="rear" ${pref("rearCamera", false) ? "checked" : ""}> Use the back camera</label>
        <label class="small"><input type="checkbox" id="speak" ${pref("speak", true) ? "checked" : ""}> Say a short tip after each rep</label>
        <label class="small"><input type="checkbox" id="nice" ${pref("sayNice", false) ? "checked" : ""}> Say "nice" on good reps</label>
      </div>
      <button class="btn ghost" id="sample">No camera handy? Try a sample recording</button>
    </div>
  </main>`;
  app.querySelector<HTMLButtonElement>("#back")!.onclick = () => go(home);
  app.querySelectorAll<HTMLButtonElement>("[data-training]").forEach((b) => b.onclick = () => {
    setup.training = b.dataset.training!;
    setup.view = trainings.find((t) => t.id === setup.training)!.recommended;
    preSession();
  });
  app.querySelectorAll<HTMLButtonElement>("[data-view]").forEach((b) => b.onclick = () => { setup.view = b.dataset.view!; preSession(); });
  app.querySelectorAll<HTMLButtonElement>("[data-stroke]").forEach((b) => b.onclick = () => { setup.stroke = b.dataset.stroke as Setup["stroke"]; preSession(); });
  app.querySelector<HTMLInputElement>("#rear")!.onchange = (e) => setPref("rearCamera", (e.target as HTMLInputElement).checked);
  app.querySelector<HTMLInputElement>("#speak")!.onchange = (e) => setPref("speak", (e.target as HTMLInputElement).checked);
  app.querySelector<HTMLInputElement>("#nice")!.onchange = (e) => setPref("sayNice", (e.target as HTMLInputElement).checked);
  app.querySelector<HTMLButtonElement>("#start")!.onclick = () => go(() => live("camera"));
  app.querySelector<HTMLButtonElement>("#sample")!.onclick = () => go(() => live("sample"));
}

// ---------------------------------------------------------------- live
// Quiet by default (docs/QUIET_COACHING.md): no text pops up when a rep ends. A small scoreboard, an
// optional short spoken cue, and a "last rep" card that stays until the next rep.
type BoardMode = "compact" | "mini" | "hidden";
const NEXT_BOARD: Record<BoardMode, BoardMode> = { compact: "mini", mini: "hidden", hidden: "compact" };

async function live(source: "camera" | "sample") {
  const opts: SessionOptions = { sport: setup.sport, handedness: pref("handedness", "right"), view: setup.view, focus: focusFor(setup) };
  const mirrored = source === "camera" && !pref("rearCamera", false);
  const stored = pref<string>("scoreboard", "compact");
  let board: BoardMode = stored === "mini" || stored === "hidden" ? stored : "compact";
  app.innerHTML = `
  <main class="live">
    <div class="stage"><div class="frame ${mirrored ? "mirror" : ""}" id="frame">
      ${source === "camera" ? `<video id="video" playsinline muted></video>` : ""}
      <canvas id="overlay"></canvas>
    </div></div>
    <div class="hud">
      <div class="top row between">
        <span class="pill" id="state">Starting…</span>
        <div class="row gap">
          <div class="board" id="board">
            <div class="col"><div class="lbl">REPS</div><div class="num" id="reps">0</div></div>
            <div class="divider"></div>
            <div class="col"><div class="lbl">SCORE</div><div class="num" id="score">—</div></div>
          </div>
          <button class="pill mini" id="mini-pill" hidden aria-label="Hide scoreboard"></button>
          <button class="icon-btn" id="board-btn" aria-label="Minimize scoreboard">–</button>
        </div>
      </div>
      <div id="setup-check" class="center-msg" hidden></div>
      <div class="bottom">
        <button class="fixcard" id="card" hidden aria-label="Last rep: open the fix">
          <canvas id="card-canvas" width="300" height="400"></canvas>
          <span class="fix-label" id="card-label"></span>
          <span class="fix-score" id="card-score"></span>
        </button>
        <div class="row between controls">
          <span class="muted small" id="note">${source === "sample" ? "Playing a sample recording" : ""}</span>
          <button class="btn danger" id="end">End session</button>
        </div>
      </div>
    </div>
    <dialog id="explain"></dialog>
  </main>`;
  const $ = <T extends HTMLElement>(id: string) => document.getElementById(id) as T;
  const canvas = $<HTMLCanvasElement>("overlay");
  const ctx = canvas.getContext("2d")!;
  const frame = $<HTMLDivElement>("frame");
  const dom = opts.handedness === "right" ? "r" : "l";
  const cards: FixCard[] = [];
  let lastSpoken = -1e9;
  let noteTimer = 0;
  let aspectNow = 1;

  const applyBoard = () => {
    $("board").hidden = board !== "compact";
    $("mini-pill").hidden = board !== "mini";
    const btn = $("board-btn");
    btn.textContent = board === "hidden" ? "＋" : "–";
    btn.setAttribute("aria-label", board === "compact" ? "Minimize scoreboard" : board === "mini" ? "Hide scoreboard" : "Show scoreboard");
    setPref("scoreboard", board);
  };
  $("board-btn").onclick = () => { board = NEXT_BOARD[board]; applyBoard(); };
  $("mini-pill").onclick = () => { board = "hidden"; applyBoard(); };
  applyBoard();

  const sizeCanvas = (aspect: number) => {
    frame.style.aspectRatio = String(aspect);
    const r = frame.getBoundingClientRect();
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    const w = Math.round(r.width * dpr), h = Math.round(r.height * dpr);
    if (canvas.width !== w || canvas.height !== h) { canvas.width = w; canvas.height = h; }
  };

  // quiet status line for ignored motions: small, bottom, fades
  const note = (msg: string) => {
    const n = $("note");
    n.textContent = msg;
    clearTimeout(noteTimer);
    noteTimer = window.setTimeout(() => (n.textContent = ""), 3000);
  };

  const showCard = (card: FixCard) => {
    const el = $("card");
    el.hidden = false;
    const c = $<HTMLCanvasElement>("card-canvas");
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    const w = el.clientWidth || 120;
    c.width = Math.round(w * dpr);
    c.height = Math.round(w * 1.25 * dpr);
    drawCard(c, card);
    $("card-label").textContent = card.short ?? "";
    $("card-score").textContent = `Rep ${card.repIndex + 1} · ${fmt(card.score)}`;
    el.onclick = () => openCard(card);
  };

  const openCard = (card: FixCard) => openFix($<HTMLDialogElement>("explain"), opts.sport, card);

  const speak = (text: string) => {
    if (!pref("speak", true) || !("speechSynthesis" in window)) return;
    const now = performance.now();
    if (now - lastSpoken < 6000) return;
    lastSpoken = now;
    speechSynthesis.cancel();
    speechSynthesis.speak(new SpeechSynthesisUtterance(text));
  };

  const onEvent = (ev: EngineEvent) => {
    if (ev.kind === "rep" && ev.rep) {
      const eng = session.engine;
      const n = eng.reps.length;
      $("reps").textContent = String(n);
      $("score").textContent = fmt(ev.rep.score);
      $("mini-pill").textContent = `${n} · ${fmt(ev.rep.score)}`;
      navigator.vibrate?.(40);
      const frames = session instanceof CameraSession ? session.frames : [];
      const card = buildCard(eng, ev.rep, n - 1, frames, aspectNow, mirrored);
      if (card) {
        cards.push(card);
        showCard(card);
        speak(card.short ?? card.cue ?? "");
      } else {
        $("card").hidden = true;
        if (pref("sayNice", false)) speak("Nice");
      }
    } else if (ev.kind === "rejected" && ["bad_pattern", "too_slow", "too_small", "one_way", "bad_start", "not_high_enough"].includes(ev.reason)) {
      note(`Not counted: ${REJECT_LABEL[ev.reason] ?? ev.reason}`);
    }
  };

  const hooks = {
    onFrame: (joints: Joint[] | null, aspect: number) => {
      aspectNow = aspect;
      sizeCanvas(aspect);
      if (source === "sample") {
        ctx.fillStyle = "#0d1117";
        ctx.fillRect(0, 0, canvas.width, canvas.height);
        ctx.save();
        drawSkeleton(ctx, joints, canvas.width, canvas.height, dom);
        ctx.restore();
      } else {
        drawSkeleton(ctx, joints, canvas.width, canvas.height, dom);
      }
      if (source === "camera" && !(session as CameraSession).isCounting) setupCheck(joints);
    },
    onEvent,
    onState: (s: string) => { $("state").textContent = STATE_LABEL[s] ?? s; $("state").dataset.state = s; },
    onEnd: () => finish(),
  };

  let session: CameraSession | SampleSession;
  let visibleSince: number | null = null;
  let countdownStarted = false;
  const setupCheck = (joints: Joint[] | null) => {
    const msg = $("setup-check");
    if (countdownStarted) return;
    const seen = joints ? joints.filter((j) => j && j[2] >= 0.5).length : 0;
    msg.hidden = false;
    $("state").textContent = "Setting up";
    if (seen >= 12) {
      visibleSince ??= performance.now();
      msg.innerHTML = `<p>Great — hold still…</p>`;
      if (performance.now() - visibleSince > 1000) countdown();
    } else {
      visibleSince = null;
      msg.innerHTML = `<p>${seen === 0 ? "Step into the picture" : "Move back until your head and feet are both in view"}</p>
        <button class="btn link small" id="skip">Start counting anyway</button>`;
      const sk = document.getElementById("skip");
      if (sk) sk.onclick = () => countdown();
    }
  };
  const countdown = () => {
    if (countdownStarted) return;
    countdownStarted = true;
    const msg = $("setup-check");
    let n = 3;
    const tick = () => {
      if (!session.running) return;
      if (n === 0) {
        msg.hidden = true;
        (session as CameraSession).beginCounting();
        hooks.onState(session.engine.state);
        speak("Go");
        lastSpoken = -1e9;
        return;
      }
      msg.innerHTML = `<p class="count">${n}</p>`;
      n--;
      setTimeout(tick, 800);
    };
    tick();
  };

  let ended = false;
  const finish = () => {
    if (ended) return;
    ended = true;
    const eng = session.engine;
    const duration = source === "sample" ? (session as SampleSession).duration : session.elapsed;
    session.stop();
    speechSynthesis?.cancel?.();
    const summary = summarize(opts.sport, eng.reps, eng.rejected, eng.profile.metrics, profiles.scoring, eng.activeS, eng.passiveS);
    const rec: StoredSession = {
      id: crypto.randomUUID?.() ?? String(Date.now()), sport: opts.sport, view: opts.view, focus: opts.focus,
      training: setup.training, handedness: opts.handedness, source, started_at: new Date().toISOString(),
      duration_s: duration, summary, reps: eng.reps,
    };
    go(() => summaryScreen(rec, source === "camera" && eng.reps.length > 0, cards));
  };
  $("end").onclick = finish;

  if (source === "sample") {
    const res = await fetch(import.meta.env.BASE_URL + `samples/${opts.sport}_demo.json`);
    const rec = (await res.json()) as Recording;
    opts.handedness = rec.handedness ?? "right";
    session = new SampleSession(profiles, { ...opts, view: rec.view ?? sportProfile(opts.sport).default_view ?? "front" }, hooks, rec);
    (session as SampleSession).start();
  } else {
    session = new CameraSession(profiles, opts, hooks);
    $("state").textContent = "Loading pose tracker…";
    try {
      await (session as CameraSession).start($<HTMLVideoElement>("video"), mirrored ? "user" : "environment");
    } catch (e) {
      session.stop();
      app.innerHTML = `<main class="page"><h1>Camera unavailable</h1>
        <p>${esc((e as Error)?.name === "NotAllowedError" ? "Camera permission was denied. Allow camera access for this site in your browser settings, then try again." : `Could not start the camera or pose tracker (${(e as Error)?.message ?? e}).`)}</p>
        <div class="row gap"><button class="btn primary" id="retry">Try again</button><button class="btn ghost" id="sample">Use a sample recording</button><button class="btn link" id="home">Home</button></div></main>`;
      document.getElementById("retry")!.onclick = () => go(() => live("camera"));
      document.getElementById("sample")!.onclick = () => go(() => live("sample"));
      document.getElementById("home")!.onclick = () => go(home);
      return;
    }
  }
  const onVis = () => { if (document.hidden && source === "camera") finish(); };
  document.addEventListener("visibilitychange", onVis);
  teardown = () => { document.removeEventListener("visibilitychange", onVis); session.stop(); };
}

/** The big view of a rep's fix: freeze-frame, full cue and the plain explanation. */
function openFix(d: HTMLDialogElement, sport: string, card: FixCard) {
  const info = card.cue ? cueInfo(sport, card.cue) : undefined;
  d.innerHTML = `<canvas class="fix-big" width="600" height="750"></canvas>
    <p class="legend"><span class="sw white"></span> You <span class="sw cyan"></span> The fix ${card.ghost ? "" : "<span class='muted small'>(this one is about timing or rotation, so there's no pose to draw)</span>"}</p>
    <h3>${esc(card.short ?? "")}</h3>
    ${card.cue ? `<p>${esc(card.cue)}</p>` : ""}
    ${info ? `<p class="muted">${esc(info.meaning)}</p><p><strong class="good">Aim for:</strong> ${esc(info.correct_motion)}</p>` : ""}
    <button class="btn primary" id="close-explain">Got it</button>`;
  d.showModal();
  drawCard(d.querySelector("canvas")!, card);
  document.getElementById("close-explain")!.onclick = () => d.close();
}

// ---------------------------------------------------------------- summary
function metricRows(s: StoredSession) {
  const prof = sportProfile(s.sport, s.view);
  const mainType = Object.entries(s.summary.types).sort((a, b) => b[1] - a[1])[0]?.[0] ?? "";
  return prof.metrics
    .filter((m: { id: string }) => s.summary.metrics[m.id])
    .map((m: { id: string; label: string; unit: string }) => {
      const v = s.summary.metrics[m.id];
      const tgt = targetFor(m, mainType);
      const d = m.unit === "deg" || m.unit === "s" ? (m.unit === "s" ? 2 : 0) : 2;
      const u = UNIT[m.unit] ?? "";
      return `<tr><td>${esc(m.label)}</td><td>${fmt(v.mean, d)}${u}</td><td class="muted">${tgt ? fmt(tgt[0], d) + u : "—"}</td>
        <td><div class="bar"><span style="width:${Math.max(3, v.score)}%" class="${v.score >= 75 ? "ok" : v.score >= 50 ? "mid" : "low"}"></span></div></td></tr>`;
    }).join("");
}

async function summaryScreen(s: StoredSession, save: boolean, cards: FixCard[] = []) {
  const prof = sportProfile(s.sport, s.view);
  const previous = (await listSessions()).filter((x) => x.sport === s.sport && x.summary.score != null);
  if (save) await saveSession(s);
  const prevScores = previous.slice(0, 5).map((x) => x.summary.score!);
  const prevAvg = prevScores.length ? prevScores.reduce((a, b) => a + b, 0) / prevScores.length : null;
  const best = previous.length ? Math.max(...previous.map((x) => x.summary.score!)) : null;
  const sc = s.summary.score;
  const delta = sc != null && prevAvg != null ? sc - prevAvg : null;
  const count = previous.length + (save ? 1 : 0);
  const checkpoint = save && count > 0 && count % SESSION_CHECKPOINT === 0;
  app.innerHTML = `
  <main class="page">
    <h1>${ICONS[s.sport]} Session summary</h1>
    ${s.source === "sample" ? `<p class="notice">This was a sample recording, so it isn't saved to your history.</p>` : ""}
    ${!save && s.source === "camera" ? `<p class="notice">No reps were counted, so nothing was saved. Make sure your whole body is in view and swing at full speed.</p>` : ""}
    <section class="stats">
      <div class="stat big"><div class="num">${fmt(sc)}</div><div class="lbl">Session score</div></div>
      <div class="stat"><div class="num">${s.summary.rep_count}</div><div class="lbl">Reps counted</div></div>
      <div class="stat"><div class="num">${fmt(s.summary.form_score)}</div><div class="lbl">Form</div></div>
      <div class="stat"><div class="num">${fmt(s.summary.consistency)}</div><div class="lbl">Consistency</div></div>
    </section>
    ${delta != null ? `<p class="compare ${delta >= 0 ? "good" : "bad"}">${delta >= 0 ? "▲" : "▼"} ${fmt(Math.abs(delta), 1)} vs your last ${prevScores.length} session average (${fmt(prevAvg, 1)})${best != null && sc! > best ? " · new personal best!" : ""}</p>` : ""}
    ${checkpoint ? `<section class="card checkpoint"><h3>🏁 Checkpoint: ${count} ${esc(profiles.sports[s.sport].label)} sessions</h3>
      <p>${checkpointText(previous, s)}</p></section>` : ""}
    ${s.summary.top_cues.length ? `<section class="card"><h3>Work on next</h3>${s.summary.top_cues.map((c) => {
      const info = cueInfo(s.sport, c);
      return `<details><summary>${esc(c)}</summary>${info ? `<p>${esc(info.meaning)}</p><p><strong class="good">Aim for:</strong> ${esc(info.correct_motion)}</p>` : ""}</details>`;
    }).join("")}</section>` : ""}
    ${Object.keys(s.summary.metrics).length ? `<section class="card"><h3>Your averages vs pro reference</h3>
      <div class="scroll"><table><thead><tr><th>Metric</th><th>You</th><th>Pro</th><th>Score</th></tr></thead>
      <tbody>${metricRows(s)}</tbody></table></div>
      <p class="muted small">Distances are measured in your own torso lengths (shoulders to hips), so they work at any height or camera distance.</p></section>` : ""}
    ${s.reps.length ? `<section class="card"><h3>Reps</h3><ol class="reps">${s.reps.map((r: Rep, i: number) =>
      `<li><span class="rs">${fmt(r.score)}</span> <span class="muted">${esc(r.type)}</span> ${r.cues[0] ? `· ${esc(shortLabel(prof, r.cues[0]))}` : ""}
        ${cards.some((c) => c.repIndex === i) ? `<button class="btn link small" data-card="${i}">See the fix</button>` : ""}</li>`).join("")}</ol></section>` : ""}
    <dialog id="explain"></dialog>
    ${Object.keys(s.summary.rejected).length ? `<p class="muted small">Ignored motions: ${Object.entries(s.summary.rejected).map(([k, v]) => `${v} × ${REJECT_LABEL[k] ?? k}`).join("; ")}.</p>` : ""}
    <div class="row gap"><button class="btn primary" id="again">Go again</button><button class="btn ghost" id="history">History</button><button class="btn link" id="home">Home</button></div>
  </main>`;
  app.querySelectorAll<HTMLButtonElement>("[data-card]").forEach((b) => b.onclick = () => {
    const card = cards.find((c) => c.repIndex === Number(b.dataset.card));
    if (card) openFix(document.getElementById("explain") as HTMLDialogElement, s.sport, card);
  });
  document.getElementById("again")!.onclick = () => go(preSession);
  document.getElementById("history")!.onclick = () => go(history);
  document.getElementById("home")!.onclick = () => go(home);
}

function checkpointText(previous: StoredSession[], s: StoredSession) {
  const all = [s, ...previous];
  const recent = all.slice(0, SESSION_CHECKPOINT), older = all.slice(SESSION_CHECKPOINT, SESSION_CHECKPOINT * 2);
  const avg = (xs: StoredSession[]) => xs.reduce((a, x) => a + (x.summary.score ?? 0), 0) / xs.length;
  const reps = recent.reduce((a, x) => a + x.summary.rep_count, 0);
  return older.length
    ? `Last ${recent.length} sessions averaged ${fmt(avg(recent), 1)}, ${avg(recent) >= avg(older) ? "up" : "down"} from ${fmt(avg(older), 1)} the ${older.length} before. ${reps} reps in that stretch.`
    : `Your first ${recent.length} sessions averaged ${fmt(avg(recent), 1)} across ${reps} reps. Keep going to see your trend.`;
}

// ---------------------------------------------------------------- history
async function history() {
  const sessions = await listSessions();
  const persistent = await storageIsPersistent();
  const bySport = SPORTS.map((sp) => {
    const xs = sessions.filter((x) => x.sport === sp && x.summary.score != null);
    return { sp, n: xs.length, avg: xs.length ? xs.reduce((a, x) => a + x.summary.score!, 0) / xs.length : null,
             best: xs.length ? Math.max(...xs.map((x) => x.summary.score!)) : null, reps: xs.reduce((a, x) => a + x.summary.rep_count, 0) };
  }).filter((x) => x.n);
  app.innerHTML = `
  <main class="page">
    <button class="btn link" id="back">← Home</button>
    <h1>History</h1>
    ${persistent ? "" : `<p class="notice">This browser is blocking storage (private mode?), so sessions last only until you close the tab.</p>`}
    ${bySport.length ? `<section class="grid sports">${bySport.map((x) => `<div class="card"><h3>${ICONS[x.sp]} ${esc(profiles.sports[x.sp].label)}</h3>
      <p><strong>${fmt(x.avg, 1)}</strong> average · best ${fmt(x.best)}<br><span class="muted small">${x.n} sessions · ${x.reps} reps</span></p>
      ${sparkline(sessions.filter((s) => s.sport === x.sp).map((s) => s.summary.score ?? 0).reverse())}</div>`).join("")}</section>` : `<p class="muted">No sessions yet. Finish a camera session with at least one counted rep and it shows up here.</p>`}
    ${sessions.length ? `<section class="card"><ul class="history">${sessions.map((s) => `<li>
        <span>${ICONS[s.sport]} <strong>${fmt(s.summary.score)}</strong> · ${s.summary.rep_count} reps${s.sport === "tennis" ? ` · ${VIEW_LABEL[s.view]} view` : ""}</span>
        <span class="muted small">${new Date(s.started_at).toLocaleString()}</span>
        <button class="btn link small" data-del="${s.id}" aria-label="Delete session">Delete</button></li>`).join("")}</ul></section>
      <div class="row gap"><button class="btn ghost" id="json">Export JSON</button><button class="btn ghost" id="csv">Export CSV</button>
      <button class="btn danger" id="clear">Delete all</button></div>
      <p class="muted small" id="confirm" hidden></p>` : ""}
  </main>`;
  document.getElementById("back")!.onclick = () => go(home);
  app.querySelectorAll<HTMLButtonElement>("[data-del]").forEach((b) => b.onclick = async () => { await deleteSession(b.dataset.del!); go(history); });
  const dl = (name: string, type: string, body: string) => {
    const a = document.createElement("a");
    a.href = URL.createObjectURL(new Blob([body], { type }));
    a.download = name;
    a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  };
  const j = document.getElementById("json");
  if (j) j.onclick = () => dl("formcoach-sessions.json", "application/json", JSON.stringify(sessions, null, 2));
  const c = document.getElementById("csv");
  if (c) c.onclick = () => dl("formcoach-sessions.csv", "text/csv", toCsv(sessions));
  const clr = document.getElementById("clear");
  if (clr) {
    let armed = false;
    clr.onclick = async () => {
      if (!armed) {
        armed = true;
        clr.textContent = "Tap again to delete everything";
        return;
      }
      await clearSessions();
      go(history);
    };
  }
}

function sparkline(vals: number[]) {
  if (vals.length < 2) return "";
  const w = 160, h = 36;
  const pts = vals.map((v, i) => `${(i / (vals.length - 1)) * w},${h - (Math.max(0, Math.min(100, v)) / 100) * h}`).join(" ");
  return `<svg class="spark" viewBox="0 0 ${w} ${h}" preserveAspectRatio="none" aria-hidden="true"><polyline points="${pts}"/></svg>`;
}

function toCsv(sessions: StoredSession[]) {
  const rows = [["started_at", "sport", "view", "reps", "score", "form", "consistency", "duration_s", "top_cue"]];
  for (const s of sessions) {
    const q: Summary = s.summary;
    rows.push([s.started_at, s.sport, s.view, String(q.rep_count), fmt(q.score, 1), fmt(q.form_score, 1), fmt(q.consistency, 1),
               fmt(s.duration_s, 0), q.top_cues[0] ?? ""]);
  }
  return rows.map((r) => r.map((x) => `"${String(x).replace(/"/g, '""')}"`).join(",")).join("\n");
}

go(home);
