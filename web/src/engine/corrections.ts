// Port of ml/formcoach/corrections.py: the player's own pose at a rep's key moment with only the faulty
// body part moved to where the cue says it should be (bone lengths kept). Checked by scripts/check.ts.
import type { Pt } from "./engine.ts";

export type Pose = Record<string, Pt>;

// metric id -> [event at which to show the fix, reference event or null]. Timing, rotation and
// racket-sport head stability have no flat 2D fix on purpose.
export const EVENTS: Record<string, Record<string, [string, string | null]>> = {
  golf: {
    lead_arm_top: ["top", null], head_sway: ["impact", "address"], head_lift: ["impact", "address"],
    hip_sway: ["top", "address"], finish_balance: ["finish", null],
  },
  basketball: {
    elbow_extension: ["release", null], elbow_flare: ["set", null], release_height: ["release", null],
    arm_verticality: ["release", null], guide_hand_gap: ["release", null], lateral_drift: ["end", "start"],
  },
  racket: {
    finish_height: ["follow_through", null], elbow_finish: ["follow_through", null],
    off_hand_reach: ["backswing", null], spacing: ["contact", null], contact_front: ["contact", "backswing"],
    back_load: ["backswing", "contact"], weight_shift: ["contact", "backswing"], contact_arm: ["contact", null],
    contact_height: ["contact", null], stance_height: ["contact", null],
    ready_height: ["start", null], backswing_size: ["backswing", null],
  },
};

const UPPER = ["nose", "l_shoulder", "r_shoulder", "l_elbow", "r_elbow", "l_wrist", "r_wrist"];

const len = (a: Pt, b: Pt) => Math.hypot(a[0] - b[0], a[1] - b[1]);
const midp = (a: Pt, b: Pt): Pt => [(a[0] + b[0]) / 2.0, (a[1] + b[1]) / 2.0];
const copysign = (a: number, b: number) => (b < 0 || Object.is(b, -0) ? -Math.abs(a) : Math.abs(a));

function shift(p: Pose, names: string[], dx: number, dy: number) {
  for (const n of names) if (n in p) p[n] = [p[n][0] + dx, p[n][1] + dy];
}

/** Two-bone IK: middle joint for root->mid->end reaching target, bending to the side of bendRef. */
function ik(root: Pt, target: Pt, l1: number, l2: number, bendRef: Pt): [Pt, Pt] {
  let dx = target[0] - root[0], dy = target[1] - root[1];
  let d = Math.hypot(dx, dy);
  const reach = (l1 + l2) * 0.999;
  if (d < 1e-9) return [bendRef, target];
  if (d > reach) {
    target = [root[0] + (dx / d) * reach, root[1] + (dy / d) * reach];
    dx = target[0] - root[0]; dy = target[1] - root[1]; d = reach;
  }
  d = Math.max(d, Math.abs(l1 - l2) + 1e-6);
  const a = (l1 * l1 - l2 * l2 + d * d) / (2 * d);
  const h = Math.sqrt(Math.max(l1 * l1 - a * a, 0.0));
  const mx = root[0] + (a * dx) / d, my = root[1] + (a * dy) / d;
  const cands: Pt[] = [[mx - (h * dy) / d, my + (h * dx) / d], [mx + (h * dy) / d, my - (h * dx) / d]];
  const side = dx * (bendRef[1] - root[1]) - dy * (bendRef[0] - root[0]) >= 0;
  const c0 = dx * (cands[0][1] - root[1]) - dy * (cands[0][0] - root[0]) >= 0;
  return [c0 === side ? cands[0] : cands[1], target];
}

function placeWrist(p: Pose, side: string, target: Pt) {
  const s = p[side + "_shoulder"], e = p[side + "_elbow"], w = p[side + "_wrist"];
  const [m, end] = ik(s, target, len(s, e), len(e, w), e);
  p[side + "_elbow"] = m;
  p[side + "_wrist"] = end;
}

function straighten(p: Pose, side: string) {
  const s = p[side + "_shoulder"], e = p[side + "_elbow"], w = p[side + "_wrist"];
  const l1 = len(s, e), l2 = len(e, w);
  const d = len(s, w);
  if (d < 1e-9) return;
  const ux = (w[0] - s[0]) / d, uy = (w[1] - s[1]) / d;
  p[side + "_elbow"] = [s[0] + ux * l1, s[1] + uy * l1];
  p[side + "_wrist"] = [s[0] + ux * (l1 + l2), s[1] + uy * (l1 + l2)];
}

function elbowToHeight(p: Pose, side: string, y: number) {
  const s = p[side + "_shoulder"], e = p[side + "_elbow"], w = p[side + "_wrist"];
  const l1 = len(s, e), l2 = len(e, w);
  const dy = Math.max(-l1, Math.min(l1, y - s[1]));
  const dx = Math.sqrt(Math.max(l1 * l1 - dy * dy, 0.0)) * (e[0] >= s[0] ? 1 : -1);
  const ne: Pt = [s[0] + dx, s[1] + dy];
  const d = len(ne, w);
  p[side + "_elbow"] = ne;
  if (d > 1e-9) p[side + "_wrist"] = [ne[0] + ((w[0] - ne[0]) * l2) / d, ne[1] + ((w[1] - ne[1]) * l2) / d];
}

const hips = (p: Pose) => midp(p.l_hip, p.r_hip);

/** Shift the body over the feet: upper body and hips fully, knees half, ankles stay planted. */
function moveBodyX(p: Pose, dx: number) {
  shift(p, [...UPPER, "l_hip", "r_hip"], dx, 0.0);
  shift(p, ["l_knee", "r_knee"], dx / 2.0, 0.0);
}

function lowerHips(p: Pose, dy: number) {
  const legs: [string, number, number][] = [];
  for (const s of ["l", "r"]) {
    if (["_hip", "_knee", "_ankle"].every((j) => s + j in p)) {
      legs.push([s, len(p[s + "_hip"], p[s + "_knee"]), len(p[s + "_knee"], p[s + "_ankle"])]);
    }
  }
  shift(p, [...UPPER, "l_hip", "r_hip"], 0.0, dy);
  for (const [s, thigh, shin] of legs) p[s + "_knee"] = ik(p[s + "_hip"], p[s + "_ankle"], thigh, shin, p[s + "_knee"])[0];
}

/** The pose with the fault for `metric` corrected to `target`, or null when there is no single-pose fix. */
export function correctedPose(analyzer: string, metric: string, target: number, pose: Pose, ref: Pose | null,
                              torso: number, dom: string): Pose | null {
  const rule = EVENTS[analyzer]?.[metric];
  if (!rule) return null;
  const p: Pose = { ...pose };
  const off = dom === "r" ? "l" : "r";
  const T = torso;
  try {
    if (analyzer === "golf") {
      const lead = off;
      if (metric === "lead_arm_top") straighten(p, lead);
      else if (metric === "head_sway") p.nose = [ref!.nose[0], p.nose[1]];
      else if (metric === "head_lift") {
        const dy = ref!.nose[1] + target * T - p.nose[1];
        lowerHips(p, Math.max(-0.3 * T, Math.min(0.3 * T, dy)));
      } else if (metric === "hip_sway") {
        const hx = hips(p)[0], rx = hips(ref!)[0];
        const want = rx + copysign(target * T, hx - rx);
        shift(p, ["l_hip", "r_hip"], want - hx, 0.0);
        shift(p, ["l_knee", "r_knee"], (want - hx) / 2.0, 0.0);
      } else if (metric === "finish_balance") {
        const ankle = p[lead + "_ankle"];
        const hx = hips(p)[0];
        const want = ankle[0] + copysign(target * T, hx - ankle[0]);
        moveBodyX(p, want - hx);
      }
    } else if (analyzer === "basketball") {
      const s = p[dom + "_shoulder"];
      if (metric === "elbow_extension") straighten(p, dom);
      else if (metric === "elbow_flare") {
        const width = len(p.l_shoulder, p.r_shoulder);
        const e = p[dom + "_elbow"];
        const want = s[0] + copysign(target * width, e[0] - s[0]);
        shift(p, [dom + "_elbow", dom + "_wrist"], want - e[0], 0.0);
      } else if (metric === "release_height") placeWrist(p, dom, [p[dom + "_wrist"][0], s[1] - target * T]);
      else if (metric === "arm_verticality") {
        const w = p[dom + "_wrist"];
        const L = len(s, p[dom + "_elbow"]) + len(p[dom + "_elbow"], w);
        const a = (target * Math.PI) / 180;
        const sign = w[0] >= s[0] ? 1 : -1;
        placeWrist(p, dom, [s[0] + sign * L * Math.sin(a), s[1] - L * Math.cos(a)]);
      } else if (metric === "guide_hand_gap") {
        const w = p[dom + "_wrist"];
        const side = p[off + "_shoulder"][0] >= s[0] ? 1 : -1;
        placeWrist(p, off, [w[0] + side * target * T, w[1] + 0.15 * T]);
      } else if (metric === "lateral_drift") {
        const hx = hips(p)[0], rx = hips(ref!)[0];
        const want = rx + copysign(target * T, hx - rx);
        moveBodyX(p, want - hx);
      }
    } else {
      const hip = hips(p);
      const w = p[dom + "_wrist"];
      if (metric === "finish_height") placeWrist(p, dom, [w[0], p[off + "_shoulder"][1] - target * T]);
      else if (metric === "elbow_finish") elbowToHeight(p, dom, p.nose[1] - target * T);
      else if (metric === "off_hand_reach") straighten(p, off);
      else if (metric === "spacing") placeWrist(p, dom, [hip[0] + copysign(target * T, w[0] - hip[0]), w[1]]);
      else if (metric === "contact_front" || metric === "weight_shift" || metric === "back_load") {
        const [contact, back] = metric !== "back_load" ? [p, ref!] : [ref!, p];
        const fwd = contact[dom + "_wrist"][0] >= back[dom + "_wrist"][0] ? 1.0 : -1.0;
        const la = p.l_ankle, ra = p.r_ankle;
        const [backX, frontX] = [la[0], ra[0]].sort((u, v) => u * fwd - v * fwd);
        if (metric === "contact_front") placeWrist(p, dom, [frontX + fwd * target * T, w[1]]);
        else {
          const width = (frontX - backX) * fwd;
          if (width <= 0) return null;
          const want = metric === "back_load" ? backX + fwd * target * width : hips(ref!)[0] + fwd * target * width;
          moveBodyX(p, want - hip[0]);
        }
      } else if (metric === "contact_arm") straighten(p, dom);
      else if (metric === "contact_height") placeWrist(p, dom, [w[0], hip[1] + target * T]);
      else if (metric === "stance_height") {
        const ankles = midp(p.l_ankle, p.r_ankle);
        lowerHips(p, ankles[1] - target * T - hip[1]);
      } else if (metric === "ready_height") placeWrist(p, dom, [w[0], hip[1] + target * T]);
      else if (metric === "backswing_size") {
        const c: Pt = [hip[0], hip[1] - 0.5 * T];
        const d = len(w, c);
        if (d < 1e-9) return null;
        const k = (target * T) / d;
        placeWrist(p, dom, [c[0] + (w[0] - c[0]) * k, c[1] + (w[1] - c[1]) * k]);
      }
    }
  } catch {
    return null;
  }
  for (const v of Object.values(p)) if (!Number.isFinite(v[0]) || !Number.isFinite(v[1])) return null;
  return p;
}
