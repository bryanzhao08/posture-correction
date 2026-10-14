// "Last rep" card: a freeze-frame of the player at the rep's key moment, their skeleton in white and the
// corrected pose as a cyan ghost (docs/QUIET_COACHING.md).
import type { Engine, Pt, Rep, Sample } from "../engine/engine.ts";
import { EVENTS, correctedPose, type Pose } from "../engine/corrections.ts";
import { targetFor } from "../engine/scoring.ts";

export interface Frame { t: number; image: CanvasImageSource; w: number; h: number }

export interface FixCard {
  repIndex: number;
  score: number;
  cue: string | null;       // full sentence
  short: string | null;     // 2-4 word label (falls back to the cue)
  pose: Pose | null;        // engine units (x * aspect, y)
  ghost: Pose | null;
  frame: Frame | null;
  aspect: number;
  mirrored: boolean;
  /** The whole rep as recorded (red) and the same motion with the fix applied (green), for the replay. */
  motion: { t: number; pose: Pose; fix: Pose | null }[];
}

const BONES: [string, string][] = [
  ["l_shoulder", "r_shoulder"], ["l_shoulder", "l_elbow"], ["l_elbow", "l_wrist"], ["r_shoulder", "r_elbow"],
  ["r_elbow", "r_wrist"], ["l_shoulder", "l_hip"], ["r_shoulder", "r_hip"], ["l_hip", "r_hip"], ["l_hip", "l_knee"],
  ["l_knee", "l_ankle"], ["r_hip", "r_knee"], ["r_knee", "r_ankle"],
];

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Spec = any;

/** The metric spec whose cue text the engine returned, and which direction it was. */
export function specForCue(profile: Spec, cue: string): { spec: Spec; dir: "low" | "high" } | null {
  for (const spec of profile.metrics) {
    if (spec.cue_low === cue) return { spec, dir: "low" };
    if (spec.cue_high === cue) return { spec, dir: "high" };
  }
  return null;
}

export function shortLabel(profile: Spec, cue: string): string {
  const m = specForCue(profile, cue);
  return (m && m.spec[`short_${m.dir}`]) || cue;
}

function nearest<T extends { t: number }>(xs: T[], t: number): T | null {
  let best: T | null = null;
  for (const x of xs) if (!best || Math.abs(x.t - t) < Math.abs(best.t - t)) best = x;
  return best;
}

function eventTime(rep: Rep, name: string | null): number | null {
  if (name === null) return null;
  if (name === "start") return rep.t_start;
  if (name === "end") return rep.t_end;
  return rep.events[name] ?? null;
}

/** Builds the card for a rep just counted. `frames` is the recent camera history (may be empty). */
export function buildCard(eng: Engine, rep: Rep, repIndex: number, frames: Frame[], aspect: number,
                          mirrored: boolean): FixCard | null {
  if (!rep.cues.length && eng.sport !== "tennis") return null;
  const analyzer: string = eng.profile.analyzer;
  // Show the ghost for the worst cue that has a pose fix; otherwise the worst cue without one.
  let chosen: { cue: string; spec: Spec } | null = null;
  for (const cue of rep.cues) {
    const m = specForCue(eng.profile, cue);
    if (m && EVENTS[analyzer]?.[m.spec.id]) { chosen = { cue, spec: m.spec }; break; }
  }
  const cue = chosen?.cue ?? rep.cues[0] ?? "";
  const metric = chosen?.spec.id ?? specForCue(eng.profile, cue)?.spec.id;
  const rule = metric ? EVENTS[analyzer]?.[metric] : undefined;
  const keyT = (rule && eventTime(rep, rule[0])) ?? rep.events.contact ?? rep.events.impact ?? rep.events.release ?? rep.t_end;
  const seg = eng.buf.filter((s) => s.t >= rep.t_start - 0.05 && s.t <= rep.t_end + 0.05);
  const at = nearest(seg, keyT);
  let pose: Pose | null = at ? { ...at.pts } : null;
  let ghost: Pose | null = null;
  if (chosen && rule && at) {
    const refT = eventTime(rep, rule[1]);
    const ref: Sample | null = refT === null ? null : nearest(seg, refT);
    const tgt = targetFor(chosen.spec, rep.type);
    if (tgt) ghost = correctedPose(analyzer, chosen.spec.id, tgt[0], at.pts, ref ? ref.pts : null, at.torso, eng.dom);
    // a fix of a few pixels would hide the player's skeleton without showing anything
    if (ghost && Math.max(...Object.keys(ghost).map((k) => at.pts[k]
      ? Math.hypot(ghost![k][0] - at.pts[k][0], ghost![k][1] - at.pts[k][1]) : 0)) < 0.12 * at.torso) ghost = null;
  }
  if (pose && Object.keys(pose).length < 8) pose = null;
  const fr = nearest(frames, keyT);
  // Capture canvases belong to a recyclable rolling buffer. Cards own an immutable copy.
  let frozen: Frame | null = null;
  if (fr && Math.abs(fr.t - keyT) < 0.3) {
    const image = document.createElement("canvas");
    image.width = fr.w; image.height = fr.h;
    image.getContext("2d")!.drawImage(fr.image, 0, 0, fr.w, fr.h);
    frozen = { ...fr, image };
  }
  return {
    repIndex, score: rep.score, cue: cue || null, short: cue ? shortLabel(eng.profile, cue) : "No correction needed", pose, ghost,
    frame: frozen, aspect, mirrored,
    motion: fixMotion(seg.map((x) => ({ t: x.t, pose: { ...x.pts } })), at && ghost ? at.pts : null, ghost,
                      rep.t_start, at ? at.t : keyT, rep.t_end),
  };
}

const smooth = (u: number) => { const c = Math.max(0, Math.min(1, u)); return c * c * (3 - 2 * c); };

/** The recorded motion with the key-moment fix eased in and out: the correction's joint offsets grow from
 *  nothing at the start of the rep to full at the key moment, then ease off by the end (a fix at the set
 *  point should not bend the arm at release). Joints the fix does not move match the recording. */
export function fixMotion(frames: { t: number; pose: Pose }[], keyPose: Pose | null, ghost: Pose | null,
                          tStart: number, keyT: number, tEnd: number) {
  return frames.map(({ t, pose }) => {
    if (!keyPose || !ghost) return { t, pose, fix: null };
    const w = t <= keyT ? (keyT > tStart ? smooth((t - tStart) / (keyT - tStart)) : 1)
                        : (tEnd > keyT ? 1 - smooth((t - keyT) / (tEnd - keyT)) : 1);
    const fix: Pose = {};
    for (const [k, p] of Object.entries(pose)) {
      const g = ghost[k], kp = keyPose[k];
      fix[k] = g && kp ? [p[0] + w * (g[0] - kp[0]), p[1] + w * (g[1] - kp[1])] : p;
    }
    return { t, pose, fix };
  });
}

/** Loops the rep: red is what you did, green is the same motion with the fix. Returns a stop function. */
export function playMotion(canvas: HTMLCanvasElement, card: FixCard, onLoop?: (u: number) => void): () => void {
  const m = card.motion;
  if (m.length < 2) return () => undefined;
  const t0 = m[0].t, dur = m[m.length - 1].t - t0;
  const slow = 2;          // half speed so the difference is easy to see
  const pause = 0.8;       // hold the last frame before looping
  let raf = 0;
  const start = performance.now();
  const frame = () => {
    const el = ((performance.now() - start) / 1000) % (dur * slow + pause);
    const t = t0 + Math.min(dur, el / slow);
    let i = 0;
    while (i < m.length - 1 && m[i + 1].t <= t) i++;
    const a = m[i], b = m[Math.min(i + 1, m.length - 1)];
    const u = b.t > a.t ? (t - a.t) / (b.t - a.t) : 0;
    const lerp = (p: Pose, q: Pose): Pose => {
      const o: Pose = {};
      for (const k of Object.keys(p)) o[k] = q[k] ? [p[k][0] + u * (q[k][0] - p[k][0]), p[k][1] + u * (q[k][1] - p[k][1])] : p[k];
      return o;
    };
    const ctx = canvas.getContext("2d")!;
    const W = canvas.width, H = canvas.height;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.fillStyle = "#0d1117";
    ctx.fillRect(0, 0, W, H);
    let fw = W, fh = W / card.aspect;
    if (fh > H) { fh = H; fw = H * card.aspect; }
    // zoom on the player: frame the bounding box of the whole motion
    const pts = m.flatMap((f) => [...Object.values(f.pose), ...Object.values(f.fix ?? {})]);
    const xs = pts.map((p) => p[0]), ys = pts.map((p) => p[1]);
    const minX = Math.min(...xs), maxX = Math.max(...xs), minY = Math.min(...ys), maxY = Math.max(...ys);
    const span = Math.max((maxX - minX) / W, (maxY - minY) / H) * 1.25;
    const cx = (minX + maxX) / 2, cy = (minY + maxY) / 2;
    const px = (p: Pt): Pt => [W / 2 + (p[0] - cx) / span, H / 2 + (p[1] - cy) / span];
    if (card.mirrored) { ctx.translate(W, 0); ctx.scale(-1, 1); }
    const unit = Math.max(2, H / 140);
    if (a.fix && b.fix) {
      ctx.save();
      ctx.shadowColor = "rgba(61, 220, 132, 0.9)";
      ctx.shadowBlur = unit * 3;
      skeleton(ctx, lerp(a.fix, b.fix), px, "rgba(61, 220, 132, 0.95)", unit * 1.1, null);
      ctx.restore();
    }
    skeleton(ctx, lerp(a.pose, b.pose), px, "rgba(255, 90, 95, 0.95)", unit * 0.9, null);
    onLoop?.((t - t0) / Math.max(dur, 1e-6));
    raf = requestAnimationFrame(frame);
  };
  frame();
  return () => cancelAnimationFrame(raf);
}

/** Draws the card's freeze-frame into a canvas of any size (keeps the camera aspect, letterboxed). */
export function drawCard(canvas: HTMLCanvasElement, card: FixCard) {
  const ctx = canvas.getContext("2d")!;
  const W = canvas.width, H = canvas.height;
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  ctx.fillStyle = "#0d1117";
  ctx.fillRect(0, 0, W, H);
  // fit the camera frame (aspect = width / height) into the canvas
  let fw = W, fh = W / card.aspect;
  if (fh > H) { fh = H; fw = H * card.aspect; }
  const ox = (W - fw) / 2, oy = (H - fh) / 2;
  if (card.mirrored) { ctx.translate(W, 0); ctx.scale(-1, 1); }
  if (card.frame) {
    ctx.globalAlpha = 0.85;
    ctx.drawImage(card.frame.image, ox, oy, fw, fh);
    ctx.globalAlpha = 1;
  }
  const px = (p: Pt): Pt => [ox + (p[0] / card.aspect) * fw, oy + p[1] * fh];
  const unit = Math.max(2, fh / 120);
  let arrows: [Pt, Pt][] = [];
  if (card.pose && card.ghost) {
    // only the limbs the fix moves are drawn in cyan, under the player's own skeleton
    const moved = Object.keys(card.ghost).filter((k) => card.pose![k] &&
      Math.hypot(card.ghost![k][0] - card.pose![k][0], card.ghost![k][1] - card.pose![k][1]) > 0.004);
    ctx.save();
    ctx.shadowColor = "rgba(0, 229, 255, 0.9)";
    ctx.shadowBlur = unit * 4;
    skeleton(ctx, card.ghost, px, "rgba(0, 229, 255, 0.95)", unit * 1.5, new Set(moved));
    ctx.restore();
    arrows = moved.length > 4
      ? [[centroid(card.pose, moved), centroid(card.ghost, moved)]]
      : moved.map((k) => [card.pose![k], card.ghost![k]]);
  }
  if (card.pose) skeleton(ctx, card.pose, px, "rgba(255,255,255,0.95)", unit * 0.8, null);
  for (const [a, b] of arrows) arrow(ctx, px(a), px(b), unit);
}

function centroid(p: Pose, keys: string[]): Pt {
  return [keys.reduce((s, k) => s + p[k][0], 0) / keys.length, keys.reduce((s, k) => s + p[k][1], 0) / keys.length];
}

function skeleton(ctx: CanvasRenderingContext2D, pose: Pose, px: (p: Pt) => Pt, color: string, unit: number,
                  strong: Set<string> | null) {
  ctx.lineCap = "round";
  for (const [a, b] of BONES) {
    if (!pose[a] || !pose[b]) continue;
    const hot = strong === null || strong.has(a) || strong.has(b);
    if (!hot) continue;
    ctx.strokeStyle = color;
    ctx.lineWidth = unit * 1.6;
    const [x1, y1] = px(pose[a]), [x2, y2] = px(pose[b]);
    ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke();
  }
  for (const [k, v] of Object.entries(pose)) {
    if (strong !== null && !strong.has(k)) continue;
    ctx.fillStyle = color;
    const [x, y] = px(v);
    ctx.beginPath(); ctx.arc(x, y, (k === "nose" ? 2.2 : 1.6) * unit, 0, Math.PI * 2); ctx.fill();
  }
  ctx.globalAlpha = 1;
}

function arrow(ctx: CanvasRenderingContext2D, a: Pt, b: Pt, unit: number) {
  const d = Math.hypot(b[0] - a[0], b[1] - a[1]);
  if (d < unit * 3) return;
  const ux = (b[0] - a[0]) / d, uy = (b[1] - a[1]) / d;
  const head = Math.min(d * 0.5, unit * 5);
  ctx.strokeStyle = "#ffd23f";
  ctx.fillStyle = "#ffd23f";
  ctx.lineWidth = unit;
  ctx.setLineDash([unit * 2, unit * 1.5]);
  ctx.beginPath(); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0] - ux * head, b[1] - uy * head); ctx.stroke();
  ctx.setLineDash([]);
  ctx.beginPath();
  ctx.moveTo(b[0], b[1]);
  ctx.lineTo(b[0] - ux * head - uy * head * 0.6, b[1] - uy * head + ux * head * 0.6);
  ctx.lineTo(b[0] - ux * head + uy * head * 0.6, b[1] - uy * head - ux * head * 0.6);
  ctx.closePath(); ctx.fill();
}
