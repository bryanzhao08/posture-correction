// Port of ml/formcoach/sports.py. Keep line-for-line with the Python reference;
// web/scripts/check.ts (run by ml/tests/test_parity.py) keeps the two in agreement.
import type { Ctx, Pt, Sample } from "./engine.ts";

export type Metrics = Record<string, number | null>;
export type Analysis = [string, Record<string, number>, Metrics] | null;

export function mid(a: Pt, b: Pt): Pt {
  return [(a[0] + b[0]) / 2.0, (a[1] + b[1]) / 2.0];
}

export function dist(a: Pt, b: Pt): number {
  return Math.hypot(a[0] - b[0], a[1] - b[1]);
}

/** Interior angle at b in degrees, or null if any point is missing. */
export function angle(a?: Pt, b?: Pt, c?: Pt): number | null {
  if (!a || !b || !c) return null;
  const v1 = [a[0] - b[0], a[1] - b[1]];
  const v2 = [c[0] - b[0], c[1] - b[1]];
  const n = Math.hypot(v1[0], v1[1]) * Math.hypot(v2[0], v2[1]);
  if (n < 1e-9) return null;
  const cos = Math.max(-1.0, Math.min(1.0, (v1[0] * v2[0] + v1[1] * v2[1]) / n));
  return (Math.acos(cos) * 180) / Math.PI;
}

export function median(vals: number[]): number {
  const v = [...vals].sort((a, b) => a - b);
  const n = v.length;
  return n % 2 ? v[(n - 1) / 2] : (v[n / 2 - 1] + v[n / 2]) / 2.0;
}

/** Index of the first maximum in vals[lo..hi] inclusive. */
export function argmax(vals: number[], lo: number, hi: number): number {
  let best = lo;
  for (let i = lo; i <= hi; i++) if (vals[i] > vals[best]) best = i;
  return best;
}

export function argmin(vals: number[], lo: number, hi: number): number {
  let best = lo;
  for (let i = lo; i <= hi; i++) if (vals[i] < vals[best]) best = i;
  return best;
}

const p = (s: Sample, name: string): Pt | undefined => s.pts[name];
const armAngle = (s: Sample, side: string) => angle(p(s, side + "_shoulder"), p(s, side + "_elbow"), p(s, side + "_wrist"));
const shoulderWidth = (s: Sample) => dist(s.pts["l_shoulder"], s.pts["r_shoulder"]);
const deg = (r: number) => (r * 180) / Math.PI;

export function golf(seg: Sample[], ctx: Ctx): Analysis {
  const n = seg.length;
  const ry = seg.map((s) => s.ry);
  const sp = seg.map((s) => s.speed);
  // Impact is the deepest valley in hand height, flanked by high hands before and after.
  const pre = new Array(n).fill(0.0);
  const suf = new Array(n).fill(0.0);
  for (let i = 1; i < n; i++) pre[i] = i === 1 ? ry[i - 1] : Math.min(pre[i - 1], ry[i - 1]);
  for (let i = n - 2; i >= 0; i--) suf[i] = i === n - 2 ? ry[i + 1] : Math.min(suf[i + 1], ry[i + 1]);
  if (n < 5) return null;
  const depth = [0.0];
  for (let i = 1; i < n - 1; i++) depth.push(ry[i] - Math.max(pre[i], suf[i]));
  depth.push(0.0);
  const impact = argmax(depth, 1, n - 2);
  if (depth[impact] < ctx.profile.pattern.min_valley) return null;
  let lo = impact;
  while (lo > 0 && seg[impact].t - seg[lo - 1].t <= 1.0) lo--;
  let hi = impact;
  while (hi < n - 1 && seg[hi + 1].t - seg[impact].t <= 1.5) hi++;
  const top = argmin(ry, lo, impact);
  const fin = argmin(ry, impact, hi);
  if (sp[argmax(sp, top, fin)] < ctx.gates.min_peak_speed) return null;
  // Takeaway: last moment before the top that the hands were still at address.
  lo = top;
  while (lo > 0 && seg[top].t - seg[lo - 1].t <= 2.5) lo--;
  const low: number[] = [];
  for (let i = lo; i < top; i++) if (ry[i] - ry[top] >= 0.6) low.push(i);
  if (!low.length) return null;
  low.sort((a, b) => sp[a] - sp[b] || a - b);
  const still = low.slice(0, Math.max(3, Math.floor(low.length / 3)));
  const ax = median(still.map((i) => seg[i].rx));
  const ay = median(still.map((i) => seg[i].ry));
  let start = lo;
  for (let i = top - 1; i >= lo; i--) {
    if (Math.hypot(seg[i].rx - ax, seg[i].ry - ay) < 0.15) {
      start = i;
      break;
    }
  }
  const back = seg[top].t - seg[start].t;
  const down = seg[impact].t - seg[top].t;
  if (back < 0.2 || down < 0.06) return null;

  const a = seg[start], tp = seg[top], im = seg[impact], fi = seg[fin];
  const lead = tp.rx < a.rx ? "l" : "r";
  const m: Metrics = { tempo_ratio: back / down, lead_arm_top: armAngle(tp, lead) };
  const nose0 = p(a, "nose");
  if (nose0) {
    let sway = 0.0;
    for (let i = start; i <= impact; i++) {
      const nz = p(seg[i], "nose");
      if (nz) sway = Math.max(sway, Math.abs(nz[0] - nose0[0]) / seg[i].torso);
    }
    m.head_sway = sway;
    const nz = p(im, "nose");
    m.head_lift = nz ? (nz[1] - nose0[1]) / im.torso : null;
  }
  m.hip_sway = Math.abs(tp.hip[0] - a.hip[0]) / tp.torso;
  m.shoulder_turn = shoulderWidth(tp) / Math.max(shoulderWidth(a), 1e-6);
  const ankle = p(fi, lead + "_ankle");
  m.finish_balance = ankle ? Math.abs(fi.hip[0] - ankle[0]) / fi.torso : null;
  return ["swing", { address: a.t, top: tp.t, impact: im.t, finish: fi.t }, m];
}

export function basketball(seg: Sample[], ctx: Ctx): Analysis {
  const n = seg.length;
  const d = ctx.dom;
  const ry = seg.map((s) => s.ry);
  const apex = argmin(ry, 0, n - 1);
  const ea = seg.map((s) => armAngle(s, d));
  let best: number | null = null;
  for (let i = 0; i <= apex; i++) {
    const v = ea[i];
    if (v !== null && (best === null || v > best)) best = v;
  }
  if (best === null) return null;
  let release = apex;
  for (let i = 0; i <= apex; i++) {
    const sh = p(seg[i], d + "_shoulder")!;
    const v = ea[i];
    if (v !== null && v >= best - 5.0 && seg[i].pts[d + "_wrist"][1] < sh[1]) {
      release = i;
      break;
    }
  }
  let setI = 0;
  for (let i = release; i >= 0; i--) {
    if (seg[i].pts[d + "_wrist"][1] >= p(seg[i], d + "_shoulder")![1]) {
      setI = Math.min(i + 1, release);
      break;
    }
  }
  if (release < 1) return null;
  // A shot loads the elbow and then snaps it straight.
  let load: number | null = null;
  let snap = 0.0;
  for (let i = 0; i <= release; i++) {
    const v = ea[i];
    if (v === null) continue;
    if (load === null || v < load) load = v;
    for (let k = i - 1; k >= 0; k--) {
      if (seg[i].t - seg[k].t >= 0.1) {
        const w = ea[k];
        if (w !== null) snap = Math.max(snap, (v - w) / (seg[i].t - seg[k].t));
        break;
      }
    }
  }
  const pat = ctx.profile.pattern ?? {};
  if (load! > (pat.max_load_elbow ?? 180.0) || snap < (pat.min_extension_speed ?? 0.0)) return null;
  const er = ea[release];
  if (er === null || er < (pat.min_release_elbow ?? 0.0)) return null;

  // Face-on, knee flexion is invisible in 2D; the hips dropping and rising is visible.
  const hy = seg.map((x) => x.hip[1]);
  const dip = argmax(hy, 0, release);

  const rel = seg[release], st = seg[setI];
  const sh = p(rel, d + "_shoulder")!;
  const wr = rel.pts[d + "_wrist"];
  const m: Metrics = {
    leg_drive: (hy[dip] - hy[release]) / seg[release].torso,
    elbow_extension: er,
    release_height: (sh[1] - wr[1]) / rel.torso,
    arm_verticality: deg(Math.atan2(Math.abs(wr[0] - sh[0]), Math.max(sh[1] - wr[1], 1e-6))),
    lateral_drift: Math.abs(seg[n - 1].hip[0] - seg[0].hip[0]) / seg[n - 1].torso,
    shot_rhythm: rel.t - seg[dip].t,
    elbow_load: load,
    extension_speed: snap,
  };
  const el = p(st, d + "_elbow");
  m.elbow_flare = el ? Math.abs(el[0] - p(st, d + "_shoulder")![0]) / Math.max(shoulderWidth(seg[0]), 1e-6) : null;
  let holdEnd = release;
  for (let i = release; i < n; i++) {
    const s = seg[i];
    const nose = p(s, "nose");
    const headY = nose ? nose[1] : p(s, d + "_shoulder")![1] - 0.3 * s.torso;
    if (s.pts[d + "_wrist"][1] < headY) holdEnd = i;
    else break;
  }
  m.follow_through_hold = seg[holdEnd].t - rel.t;
  const gw = rel.pts[ctx.off + "_wrist"];
  if (gw) {
    m.guide_hand_gap = dist(gw, wr) / rel.torso;
    // Both arms locked straight overhead with the hands wide apart is a press, not a shot.
    const offEl = armAngle(rel, ctx.off);
    if (m.guide_hand_gap > pat.max_hand_gap && offEl !== null && offEl >= 150.0
        && (rel.pts[ctx.off + "_shoulder"][1] - gw[1]) / rel.torso >= 0.6) return null;
  }
  return ["shot", { dip: seg[dip].t, set: st.t, release: rel.t }, m];
}

export function racket(seg: Sample[], ctx: Ctx): Analysis {
  const n = seg.length;
  const d = ctx.dom;
  const sp = seg.map((s) => s.speed);
  const ry = seg.map((s) => s.ry);
  const side = ctx.facing >= 0 ? 1.0 : -1.0;
  const lat = seg.map((s) => s.rx * side); // positive = wrist on the dominant side
  const pat = ctx.profile.pattern;
  const apex = argmin(ry, 0, n - 1);
  const fastest = argmax(sp, 0, n - 1);
  let contact: number, back: number, thru: number, repType: string;
  if (ry[apex] <= -1.7 && seg[apex].t - seg[fastest].t <= 0.2) {
    // Serve or smash.
    contact = apex;
    if (contact < 1 || Math.max(...ry.slice(apex)) - ry[apex] < pat.min_overhead_drop) return null;
    const far = seg.map((s) => Math.hypot(s.rx - seg[contact].rx, s.ry - seg[contact].ry));
    back = argmax(far, 0, contact);
    const off = lat.map((v) => Math.abs(v - lat[back]));
    thru = argmax(off, contact, n - 1);
    repType = ctx.sport === "tennis" ? "serve" : "overhead";
  } else {
    // Groundstroke: the forward swing is the widest sweep of the hand across the body.
    back = 0; thru = 0;
    let sweep = 0.0, lo = 0, hi = 0;
    for (let j = 1; j < n; j++) {
      if (lat[j - 1] < lat[lo]) lo = j - 1;
      if (lat[j - 1] > lat[hi]) hi = j - 1;
      if (lat[j] - lat[lo] > sweep) { back = lo; thru = j; sweep = lat[j] - lat[lo]; }
      if (lat[hi] - lat[j] > sweep) { back = hi; thru = j; sweep = lat[hi] - lat[j]; }
    }
    if (sweep < pat.min_sweep) return null;
    if (Math.min(lat[back], lat[thru]) > -pat.min_cross || Math.max(lat[back], lat[thru]) < pat.min_cross) return null;
    contact = argmax(sp, back, thru);
    if (contact <= back) contact = back + 1;
    if (ctx.view === "side") repType = ctx.focus === "backhand" ? "backhand" : "forehand";
    else repType = lat[back] > lat[thru] ? "forehand" : "backhand";
  }
  const c = seg[contact];
  const reach = Math.abs(lat[thru] - lat[back]);
  // Jumping jacks and arm circles move both hands as mirror images above the head.
  const o = ctx.off;
  let dot = 0.0, nd = 0.0, no = 0.0;
  let bothUp = false;
  for (let i = Math.max(back, 1); i <= thru; i++) {
    const a0 = seg[i - 1].pts[d + "_wrist"], a1 = seg[i].pts[d + "_wrist"];
    const b0 = p(seg[i - 1], o + "_wrist"), b1 = p(seg[i], o + "_wrist");
    if (!b0 || !b1) continue;
    const dx = a1[0] - a0[0], dy = a1[1] - a0[1];
    const mx = -(b1[0] - b0[0]), my = b1[1] - b0[1];
    dot += dx * mx + dy * my;
    nd += dx * dx + dy * dy;
    no += mx * mx + my * my;
    const hip = seg[i].hip;
    if ((a1[1] - hip[1]) / seg[i].torso < -1.3 && (b1[1] - hip[1]) / seg[i].torso < -1.3) bothUp = true;
  }
  if (bothUp && nd > 0 && no > 0 && dot / Math.sqrt(nd * no) > pat.max_mirror) return null;

  const b = seg[back];
  let stance: number | null = null;
  for (let i = 0; i <= contact; i++) {
    const la = p(seg[i], "l_ankle"), ra = p(seg[i], "r_ankle");
    if (la && ra) {
      const h = ((la[1] + ra[1]) / 2.0 - seg[i].hip[1]) / seg[i].torso;
      if (stance === null || h < stance) stance = h;
    }
  }
  const w0 = Math.max(shoulderWidth(seg[0]), 1e-6);
  let minW = Infinity;
  for (let i = 0; i <= contact; i++) minW = Math.min(minW, shoulderWidth(seg[i]));
  const m: Metrics = {
    stance_height: stance,
    contact_arm: armAngle(c, d),
    contact_height: c.ry,
    swing_through: reach,
    shoulder_turn: minW / w0,
    swing_tempo: c.t - b.t,
    backswing_size: Math.hypot(b.rx, b.ry + 0.5),
    ready_height: seg[0].ry,
  };
  const nose0 = p(b, "nose");
  if (nose0) {
    let move = 0.0;
    for (let i = back; i <= contact; i++) {
      const nz = p(seg[i], "nose");
      if (nz) move = Math.max(move, dist(nz, nose0) / seg[i].torso);
    }
    m.head_stability = move;
  }

  // Coaching details; each is only scored in the camera views that can see it.
  const fh = argmin(ry, contact, n - 1);
  const f = seg[fh];
  m.finish_height = (f.pts[o + "_shoulder"][1] - f.pts[d + "_wrist"][1]) / f.torso;
  const el = p(f, d + "_elbow"), nz = p(f, "nose");
  if (el && nz) m.elbow_finish = (nz[1] - el[1]) / f.torso;
  let offReach: number | null = null;
  for (let i = 0; i <= contact; i++) {
    const ow = p(seg[i], o + "_wrist"), osh = p(seg[i], o + "_shoulder");
    if (ow && osh) {
      const r = dist(ow, osh) / seg[i].torso;
      offReach = offReach === null ? r : Math.max(offReach, r);
    }
  }
  m.off_hand_reach = offReach;
  m.spacing = Math.abs(c.rx);
  const fwd = c.rx >= b.rx ? 1.0 : -1.0;
  m.contact_front = c.rx * fwd;
  const cla = p(c, "l_ankle"), cra = p(c, "r_ankle");
  if (cla && cra) {
    const frontAnkle = Math.max(cla[0] * fwd, cra[0] * fwd);
    m.contact_front = (c.pts[d + "_wrist"][0] * fwd - frontAnkle) / c.torso;
  }
  let ext = -Infinity;
  for (let i = contact; i < n; i++) ext = Math.max(ext, seg[i].rx * fwd);
  m.extension_through = ext - c.rx * fwd;
  const la = p(b, "l_ankle"), ra = p(b, "r_ankle");
  if (la && ra && Math.abs(la[0] - ra[0]) / b.torso >= 0.3) {
    const [backX, frontX] = [la[0], ra[0]].sort((u, v) => u * fwd - v * fwd);
    const width = (frontX - backX) * fwd;
    m.back_load = ((b.hip[0] - backX) * fwd) / width;
    m.weight_shift = ((c.hip[0] - b.hip[0]) * fwd) / width;
  }
  return [repType, { backswing: b.t, contact: c.t, finish: seg[thru].t, follow_through: f.t }, m];
}

export const ANALYZERS: Record<string, (seg: Sample[], ctx: Ctx) => Analysis> = { golf, basketball, racket };
