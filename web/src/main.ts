import "./style.css";
import profilesJson from "../../shared/sport_profiles.json";
import catalogJson from "../../shared/cue_catalog.json";
import { effectiveProfile, type EngineEvent, type Joint, type Recording, type Rep } from "./engine/engine.ts";
import { summarize, targetFor, type Summary } from "./engine/scoring.ts";
import { CameraSession, SampleSession, drawSkeleton, type SessionOptions } from "./app/session.ts";
import { clearSessions, deleteSession, listSessions, pref, saveSession, setPref, storageIsPersistent,
         type StoredSession } from "./app/store.ts";
import { loadPose } from "./app/pose.ts";
import { gate, pricing, trialBanner } from "./app/beta.ts";
import { buildCard, drawCard, playMotion, shortLabel, type FixCard } from "./app/fixcard.ts";
import { drillsFor, findDrill, personalize, type Drill } from "./engine/personalize.ts";
import { cmToFtIn, ftInToCm, handSpeed, heightLabel, loadPlayer, minPhoneDistance, savePlayer, speedUnit,
         torsoToReal, type PlayerPrefs } from "./app/player.ts";

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
  no_metrics: "not enough of you visible to score", other_stroke: "a different stroke from this drill's",
};
const SESSION_CHECKPOINT = 5;
const UNIT: Record<string, string> = { deg: "°", s: " s" };

const app = document.getElementById("app")!;
const esc = (s: unknown) => String(s ?? "").replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);
const fmt = (v: number | null | undefined, d = 0) => (v == null || !isFinite(v) ? "—" : v.toFixed(d));
let teardown: (() => void) | null = null;

interface Setup { sport: string; training: string | null; view: string; stroke: "forehand" | "backhand"; drill: string | null }
const setup: Setup = { sport: "golf", training: null, view: "front", stroke: "forehand", drill: null };
const player = (): PlayerPrefs => loadPlayer(profiles.player);
const LEVELS = ["beginner", "intermediate", "advanced", "pro"].filter((l) => l in profiles.player.levels);

/** The drills on offer for the current sport and (tennis) training type; keeps setup.drill valid. */
function setupDrills(): Drill[] {
  const drills = drillsFor(profiles.sports[setup.sport], setup.training);
  if (!drills.some((d) => d.id === setup.drill)) setup.drill = drills[0]?.id ?? null;
  return drills;
}

/** The scoring profile a session used: camera view, then the player's level and height, then the drill. */
function sessionProfile(sport: string, view: string, drill: string | null | undefined,
                        p: { level?: string | null; height_cm?: number | null } | null) {
  return personalize(sportProfile(sport, view), profiles.player, p, drill ?? null);
}

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
  const pl = player();
  const [ft, inch] = pl.height_cm ? cmToFtIn(pl.height_cm) : [null, null];
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
    ${trialBanner()}
    <h2>Choose a sport</h2>
    <div class="grid sports">
      ${SPORTS.map((s) => `<button class="card sport" data-sport="${s}">
          <span class="icon">${ICONS[s]}</span><span class="name">${esc(profiles.sports[s].label)}</span>
          <span class="muted small">${sessions.filter((x) => x.sport === s).length} saved sessions</span></button>`).join("")}
    </div>
    <section class="card profile" aria-labelledby="profile-h">
      <h3 id="profile-h">Your profile</h3>
      <div class="form-grid">
        <label><span>Height</span>
          ${pl.units === "metric"
            ? `<span class="field"><input id="h-cm" type="number" inputmode="numeric" min="${profiles.player.min_height_cm}" max="${profiles.player.max_height_cm}" step="1" placeholder="175" value="${pl.height_cm ? Math.round(pl.height_cm) : ""}"> cm</span>`
            : `<span class="field"><input id="h-ft" type="number" inputmode="numeric" min="3" max="7" step="1" placeholder="5" value="${ft ?? ""}"> ft
               <input id="h-in" type="number" inputmode="numeric" min="0" max="11" step="1" placeholder="9" value="${inch ?? ""}"> in</span>`}
        </label>
        <label><span>Level</span><select id="level">${LEVELS.map((l) =>
          `<option value="${l}" ${l === pl.level ? "selected" : ""}>${esc(profiles.player.levels[l].label)}</option>`).join("")}</select></label>
        <label><span>Hand</span><select id="hand"><option value="right" ${hand === "right" ? "selected" : ""}>Right</option>
          <option value="left" ${hand === "left" ? "selected" : ""}>Left</option></select></label>
        <label><span>Units</span><select id="units"><option value="imperial" ${pl.units === "imperial" ? "selected" : ""}>ft · mph</option>
          <option value="metric" ${pl.units === "metric" ? "selected" : ""}>cm · km/h</option></select></label>
      </div>
      <p class="muted small" id="level-about">${esc(profiles.player.levels[pl.level!].about)}</p>
      <p class="muted small" id="height-note">${pl.height_cm
        ? `Height shows distances in ${pl.units === "metric" ? "cm" : "inches"}, estimates your hand speed and adjusts how much leg drive a basketball shot needs.`
        : "Add your height to see hand speed and real distances."}</p>
    </section>
    <div class="row between settings">
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
    setup.drill = null;
    setupDrills();
    go(preSession);
  });
  (app.querySelector("#hand") as HTMLSelectElement).onchange = (e) => setPref("handedness", (e.target as HTMLSelectElement).value);
  const save = (change: Partial<PlayerPrefs>) => savePlayer({ ...player(), ...change });
  (app.querySelector("#level") as HTMLSelectElement).onchange = (e) => {
    const level = (e.target as HTMLSelectElement).value;
    save({ level });
    app.querySelector("#level-about")!.textContent = profiles.player.levels[level].about;
  };
  (app.querySelector("#units") as HTMLSelectElement).onchange = (e) => {
    save({ units: (e.target as HTMLSelectElement).value as PlayerPrefs["units"] });
    void home();
  };
  const readHeight = (): number | null => {
    const num = (id: string) => {
      const el = app.querySelector<HTMLInputElement>(id);
      return el && el.value.trim() !== "" ? Number(el.value) : null;
    };
    const cm = pl.units === "metric" ? num("#h-cm") : (num("#h-ft") != null ? ftInToCm(num("#h-ft")!, num("#h-in") ?? 0) : null);
    if (cm == null || !isFinite(cm)) return null;
    return cm >= profiles.player.min_height_cm && cm <= profiles.player.max_height_cm ? cm : NaN;
  };
  app.querySelectorAll<HTMLInputElement>("#h-cm, #h-ft, #h-in").forEach((el) => el.onchange = () => {
    const cm = readHeight();
    const note = app.querySelector("#height-note")!;
    if (Number.isNaN(cm)) {
      note.textContent = `Enter a height between ${heightLabel(profiles.player.min_height_cm, pl.units)} and ${heightLabel(profiles.player.max_height_cm, pl.units)}.`;
      note.classList.add("bad");
      return;
    }
    note.classList.remove("bad");
    save({ height_cm: cm });
    note.textContent = cm ? `Saved: ${heightLabel(cm, pl.units)}.` : "Height cleared.";
  });
  (app.querySelector("#history") as HTMLButtonElement).onclick = () => go(history);
  (app.querySelector("#plans") as HTMLButtonElement).onclick = () => go(() => pricing(app, () => go(home)));
  void loadPose().catch(() => undefined); // warm up the model while the user reads
}

// ---------------------------------------------------------------- pre-session
function preSession() {
  const base = profiles.sports[setup.sport];
  const pl = player();
  const drills = setupDrills();
  const drill = findDrill(base, setup.drill);
  const prof = sessionProfile(setup.sport, setup.view, setup.drill, pl);
  const trainings: { id: string; label: string; recommended: string; views: string[]; why: string }[] = base.training ?? [];
  const tr = trainings.find((t) => t.id === setup.training);
  // drill focus first, then the rest
  const scored = [...prof.metrics].sort((a: { focus?: boolean }, b: { focus?: boolean }) => Number(!!b.focus) - Number(!!a.focus));
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
    ${drills.length ? `
      <h2>Drill</h2>
      <div class="chips">${drills.map((d) => `<button class="chip ${d.id === setup.drill ? "on" : ""}" data-drill="${d.id}">${esc(d.label)}</button>`).join("")}</div>
      ${drill ? `<p>${esc(drill.about)}</p>${drill.tip ? `<p class="tip small">Tip: ${esc(drill.tip)}</p>` : ""}` : ""}
    ` : ""}
    <p class="muted small profile-line">Goal ${drill?.goal_reps ?? "—"} reps · scored as <strong>${esc(profiles.player.levels[pl.level!].label)}</strong>
      · height ${esc(heightLabel(pl.height_cm, pl.units))} <button class="btn link small" id="edit-profile">Change</button></p>
    <section class="card setup">
      <h3>Set up your camera</h3>
      <p>${esc(prof.camera)}</p>
      <p class="muted small">Your whole body, head to feet, needs to be in the picture.${pl.height_cm
        ? ` At ${esc(heightLabel(pl.height_cm, pl.units))}, a phone held upright needs to be at least ${minPhoneDistance(pl.height_cm, pl.units)} away to fit you in.`
        : ""} Good light helps a lot.</p>
    </section>
    <section class="card">
      <h3>What gets scored</h3>
      <ul class="metric-list">${scored.map((m: { label: string; focus?: boolean }) =>
        `<li${m.focus ? ' class="focus"' : ""}>${esc(m.label)}${m.focus ? ' <span class="tag">focus</span>' : ""}</li>`).join("")}</ul>
      ${drill?.types ? `<p class="muted small">Only ${esc(drill.types.join(" and "))}s count in this drill; other strokes are ignored.</p>` : ""}
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
  app.querySelectorAll<HTMLButtonElement>("[data-drill]").forEach((b) => b.onclick = () => { setup.drill = b.dataset.drill!; preSession(); });
  app.querySelector<HTMLButtonElement>("#edit-profile")!.onclick = () => go(home);
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
  const pl = player();
  const opts: SessionOptions = { sport: setup.sport, handedness: pref("handedness", "right"), view: setup.view, focus: focusFor(setup),
                                 player: { height_cm: pl.height_cm, level: pl.level }, drill: setup.drill };
  const drill = findDrill(profiles.sports[setup.sport], setup.drill);
  const goal = drill?.goal_reps ?? null;
  let goalSaid = false;
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
            <div class="col"><div class="lbl">REPS</div><div class="num" id="reps">${goal ? `0/${goal}` : 0}</div></div>
            <div class="divider"></div>
            <div class="col"><div class="lbl">SCORE</div><div class="num" id="score">—</div></div>
            ${pl.height_cm ? `<div class="divider"></div>
            <div class="col"><div class="lbl">${speedUnit(pl.units).toUpperCase()}</div><div class="num" id="speed">—</div></div>` : ""}
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
      $("reps").textContent = goal ? `${n}/${goal}` : String(n);
      $("score").textContent = fmt(ev.rep.score);
      const spd = handSpeed(ev.rep.peak_speed, opts.player!, profiles.player, pl.units);
      if (spd != null) $("speed").textContent = fmt(spd);
      $("mini-pill").textContent = `${n} · ${fmt(ev.rep.score)}`;
      if (goal && n >= goal && !goalSaid) {
        goalSaid = true;
        $("board").classList.add("done");
        note(`Goal reached: ${goal} reps. Keep going or end the session.`);
        lastSpoken = -1e9;
        speak("Goal reached");
        lastSpoken = performance.now();
      }
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
    } else if (ev.kind === "rejected" && ev.reason === "other_stroke" && drill?.types) {
      note(`Not counted: this drill only counts ${drill.types.join(" and ")}s`);
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
      training: setup.training, handedness: opts.handedness, drill: setup.drill, level: pl.level, height_cm: pl.height_cm,
      source, started_at: new Date().toISOString(),
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
  const replay = card.ghost && card.motion.length > 1;
  d.innerHTML = `${replay ? `<div class="tabs"><button class="chip on" data-tab="replay">Replay</button><button class="chip" data-tab="still">Key moment</button></div>
    <canvas class="fix-big" id="fix-replay" width="600" height="750"></canvas>
    <p class="legend" id="legend-replay"><span class="sw red"></span> What you did <span class="sw green"></span> What to do <span class="muted small">(your recorded rep, half speed)</span></p>` : ""}
    <canvas class="fix-big" id="fix-still" width="600" height="750" ${replay ? "hidden" : ""}></canvas>
    <p class="legend" id="legend-still" ${replay ? "hidden" : ""}><span class="sw white"></span> You <span class="sw cyan"></span> The fix ${card.ghost ? "" : "<span class='muted small'>(this one is about timing or rotation, so there's no pose to draw)</span>"}</p>
    <h3>${esc(card.short ?? "")}</h3>
    ${card.cue ? `<p>${esc(card.cue)}</p>` : ""}
    ${info ? `<p class="muted">${esc(info.meaning)}</p><p><strong class="good">Aim for:</strong> ${esc(info.correct_motion)}</p>` : ""}
    <button class="btn primary" id="close-explain">Got it</button>`;
  d.showModal();
  drawCard(d.querySelector<HTMLCanvasElement>("#fix-still")!, card);
  let stop = replay ? playMotion(d.querySelector<HTMLCanvasElement>("#fix-replay")!, card) : () => undefined;
  d.querySelectorAll<HTMLButtonElement>("[data-tab]").forEach((btn) => btn.onclick = () => {
    const still = btn.dataset.tab === "still";
    d.querySelectorAll("[data-tab]").forEach((x) => x.classList.toggle("on", x === btn));
    for (const id of ["fix-replay", "legend-replay"]) (d.querySelector("#" + id) as HTMLElement).hidden = still;
    for (const id of ["fix-still", "legend-still"]) (d.querySelector("#" + id) as HTMLElement).hidden = !still;
    stop();
    stop = still ? () => undefined : playMotion(d.querySelector<HTMLCanvasElement>("#fix-replay")!, card);
  });
  d.onclose = () => stop();
  document.getElementById("close-explain")!.onclick = () => d.close();
}

// ---------------------------------------------------------------- summary
function metricRows(s: StoredSession) {
  const prof = sessionProfile(s.sport, s.view, s.drill, s);
  const pl = player();
  const real = (v: number, unit: string) => {
    const r = unit === "torso" ? torsoToReal(v, { height_cm: s.height_cm }, profiles.player, pl.units) : null;
    return r ? ` <span class="muted small">(${r})</span>` : "";
  };
  const mainType = Object.entries(s.summary.types).sort((a, b) => b[1] - a[1])[0]?.[0] ?? "";
  return prof.metrics
    .filter((m: { id: string }) => s.summary.metrics[m.id])
    .sort((a: { focus?: boolean }, b: { focus?: boolean }) => Number(!!b.focus) - Number(!!a.focus))
    .map((m: { id: string; label: string; unit: string; focus?: boolean }) => {
      const v = s.summary.metrics[m.id];
      const tgt = targetFor(m, mainType);
      const d = m.unit === "deg" || m.unit === "s" ? (m.unit === "s" ? 2 : 0) : 2;
      const u = UNIT[m.unit] ?? "";
      return `<tr><td>${esc(m.label)}${m.focus ? ' <span class="tag">focus</span>' : ""}</td><td>${fmt(v.mean, d)}${u}${real(v.mean, m.unit)}</td><td class="muted">${tgt ? fmt(tgt[0], d) + u : "—"}</td>
        <td><div class="bar"><span style="width:${Math.max(3, v.score)}%" class="${v.score >= 75 ? "ok" : v.score >= 50 ? "mid" : "low"}"></span></div></td></tr>`;
    }).join("");
}

async function summaryScreen(s: StoredSession, save: boolean, cards: FixCard[] = []) {
  const prof = sessionProfile(s.sport, s.view, s.drill, s);
  const pl = player();
  const drill = findDrill(profiles.sports[s.sport], s.drill);
  const all = (await listSessions()).filter((x) => x.sport === s.sport && x.summary.score != null && x.id !== s.id);
  const previous = all;
  const sameDrill = drill ? all.filter((x) => x.drill === s.drill) : [];
  const drillBest = sameDrill.length ? Math.max(...sameDrill.map((x) => x.summary.score!)) : null;
  const speeds = s.reps.map((r) => handSpeed(r.peak_speed, { height_cm: s.height_cm }, profiles.player, pl.units))
    .filter((v): v is number => v != null);
  const goal = drill?.goal_reps ?? null;
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
    <p class="muted">${drill ? `${esc(drill.label)} · ` : ""}${s.level ? `scored as ${esc(profiles.player.levels[s.level]?.label ?? s.level)}` : ""}</p>
    ${s.source === "sample" ? `<p class="notice">This was a sample recording, so it isn't saved to your history.</p>` : ""}
    ${!save && s.source === "camera" ? `<p class="notice">No reps were counted, so nothing was saved. Make sure your whole body is in view and swing at full speed.</p>` : ""}
    <section class="stats">
      <div class="stat big"><div class="num">${fmt(sc)}</div><div class="lbl">Session score</div></div>
      <div class="stat"><div class="num">${s.summary.rep_count}${goal ? `<span class="of">/${goal}</span>` : ""}</div><div class="lbl">${goal ? (s.summary.rep_count >= goal ? "Goal reached ✓" : "Reps of goal") : "Reps counted"}</div></div>
      <div class="stat"><div class="num">${fmt(s.summary.form_score)}</div><div class="lbl">Form</div></div>
      <div class="stat"><div class="num">${fmt(s.summary.consistency)}</div><div class="lbl">Consistency</div></div>
    </section>
    ${speeds.length ? `<p class="speed">Hand speed: <strong>${fmt(speeds.reduce((a, b) => a + b, 0) / speeds.length)} ${speedUnit(pl.units)}</strong> average,
      <strong>${fmt(Math.max(...speeds))}</strong> fastest <span class="muted small">(estimated from your height; the camera can't see motion toward it)</span></p>` : ""}
    ${drill && sc != null && save ? `<p class="compare ${drillBest == null || sc > drillBest ? "good" : ""}">${drillBest == null
      ? `First ${esc(drill.label)} session: this is your score to beat.`
      : sc > drillBest ? `New ${esc(drill.label)} personal best (previous ${fmt(drillBest)})!` : `${esc(drill.label)} best: ${fmt(drillBest)}`}</p>` : ""}
    ${delta != null ? `<p class="compare ${delta >= 0 ? "good" : "bad"}">${delta >= 0 ? "▲" : "▼"} ${fmt(Math.abs(delta), 1)} vs your last ${prevScores.length} session average (${fmt(prevAvg, 1)})${best != null && sc! > best ? " · new personal best!" : ""}</p>` : ""}
    ${checkpoint ? `<section class="card checkpoint"><h3>🏁 Checkpoint: ${count} ${esc(profiles.sports[s.sport].label)} sessions</h3>
      <p>${checkpointText(previous, s)}</p></section>` : ""}
    ${s.summary.top_cues.length ? `<section class="card"><h3>Work on next</h3>${s.summary.top_cues.map((c) => {
      const info = cueInfo(s.sport, c);
      return `<details><summary>${esc(c)}</summary>${info ? `<p>${esc(info.meaning)}</p><p><strong class="good">Aim for:</strong> ${esc(info.correct_motion)}</p>` : ""}</details>`;
    }).join("")}</section>` : ""}
    ${Object.keys(s.summary.metrics).length ? `<section class="card"><h3>Your averages vs target</h3>
      <div class="scroll"><table><thead><tr><th>Metric</th><th>You</th><th>Target</th><th>Score</th></tr></thead>
      <tbody>${metricRows(s)}</tbody></table></div>
      <p class="muted small">Distances are measured in your own torso lengths (shoulders to hips), so they work at any height or camera distance${s.height_cm ? "; the converted values use your height" : ""}. Targets follow your level${s.drill ? " and the drill's focus" : ""}.</p></section>` : ""}
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
        <span>${ICONS[s.sport]} <strong>${fmt(s.summary.score)}</strong> · ${s.summary.rep_count} reps${s.drill ? ` · ${esc(findDrill(profiles.sports[s.sport], s.drill)?.label ?? s.drill)}` : ""}${s.sport === "tennis" ? ` · ${VIEW_LABEL[s.view]} view` : ""}</span>
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
  const rows = [["started_at", "sport", "view", "drill", "level", "height_cm", "reps", "score", "form", "consistency", "duration_s", "top_cue"]];
  for (const s of sessions) {
    const q: Summary = s.summary;
    rows.push([s.started_at, s.sport, s.view, s.drill ?? "", s.level ?? "", s.height_cm ? fmt(s.height_cm) : "", String(q.rep_count), fmt(q.score, 1), fmt(q.form_score, 1), fmt(q.consistency, 1),
               fmt(s.duration_s, 0), q.top_cues[0] ?? ""]);
  }
  return rows.map((r) => r.map((x) => `"${String(x).replace(/"/g, '""')}"`).join(",")).join("\n");
}

gate(app, () => go(home));
