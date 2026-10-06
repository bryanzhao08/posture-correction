// Port of ml/formcoach/engine.py, the reference implementation of the FormCoach engine.
// Keep line-for-line with the Python; web/scripts/check.ts verifies parity against its fixtures.
//
// Joints arrive normalised (0..1, origin top-left, y down) and are converted to height units
// (x * aspect). Body-relative values are measured from the mid-hip in torso lengths.
import { ANALYZERS, dist, mid, type Metrics } from "./sports.ts";
import { scoreRep } from "./scoring.ts";

export type Pt = [number, number];
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export type Profiles = any;
export type Joint = [number, number, number] | null;

/** A sport profile adjusted for the camera view: per-view dicts merge key by key, other values replace. */
export function effectiveProfile(sportProfile: Profiles, view: string | null | undefined): Profiles {
  const views = sportProfile.views ?? {};
  if (!view || !(view in views)) return sportProfile;
  const out = { ...sportProfile };
  for (const [key, value] of Object.entries(views[view])) {
    const cur = out[key];
    if (isDict(value) && isDict(cur)) out[key] = { ...cur, ...(value as object) };
    else out[key] = value;
  }
  return out;
}

const isDict = (v: unknown) => v !== null && typeof v === "object" && !Array.isArray(v);

export interface Sample {
  t: number;
  pts: Record<string, Pt>;
  torso: number;
  hip: Pt;
  rx: number;
  ry: number;
  speed: number;
}

export interface Rep {
  t_start: number;
  t_end: number;
  type: string;
  events: Record<string, number>;
  metrics: Metrics;
  scores: Record<string, number>;
  score: number;
  cues: string[];
  peak_speed: number;
}

export interface EngineEvent {
  kind: "rep" | "rejected";
  t: number;
  rep?: Rep;
  reason: string;
  stats: Record<string, number>;
}

export interface Ctx {
  dom: string;
  off: string;
  sport: string;
  view: string;
  focus: string | null;
  facing: number;
  profile: Profiles;
  gates: Profiles;
}

export type EngineState = "no_person" | "moving" | "ready" | "active";

const alpha = (dt: number, tau: number) => (tau > 0 ? 1.0 - Math.exp(-dt / tau) : 1.0);

/**
 * Streaming state machine: push one pose frame at a time, get back counted reps.
 * no_person -> moving (seen, not armed) -> ready (armed) -> active -> ready.
 * Only motions that pass every gate and the sport's pattern check are counted.
 */
export class Engine implements Ctx {
  cfg: Profiles; scoring: Profiles; joints: string[]; sport: string; view: string; focus: string | null;
  profile: Profiles; det: Profiles; gates: Profiles; dom: string; off: string;
  state: EngineState = "no_person";
  buf: Sample[] = [];
  reps: Rep[] = [];
  rejected: Record<string, number> = {};
  activeS = 0.0;
  passiveS = 0.0;
  facing = 0.0;
  lastSample: Sample | null = null;

  private sm: Record<string, [number, number, number]> = {};
  private torso: number | null = null;
  private prevRel: Pt | null = null;
  private prevT: number | null = null;
  private speed = 0.0;
  private lastVisibleT: number | null = null;
  private quietSince: number | null = null;
  private lastRestT: number | null = null;
  private armed = false;
  private fastSince: number | null = null;
  private belowSince: number | null = null;
  private segStartT = 0.0;
  private cooldownUntil = -1.0;
  private lastSegEndT = -1.0;
  private dips: number[] = [];
  private inDip = false;
  private visibleSince: number | null = null;
  private peakV = 0.0;
  private peakT = 0.0;

  constructor(profiles: Profiles, sport: string, handedness = "right", view: string | null = null,
              focus: string | null = null) {
    this.cfg = profiles.preprocess;
    this.scoring = profiles.scoring;
    this.joints = profiles.joints;
    this.sport = sport;
    const base = profiles.sports[sport];
    this.view = view || base.default_view || "front";
    this.focus = focus;
    this.profile = effectiveProfile(base, this.view);
    this.det = this.profile.detect;
    this.gates = this.profile.gates;
    this.dom = handedness === "right" ? "r" : "l";
    this.off = this.dom === "r" ? "l" : "r";
  }

  // ---- preprocessing ----
  private smooth(t: number, joints: Joint[], aspect: number): Record<string, Pt> {
    const dt = this.prevT !== null ? t - this.prevT : 0.0;
    const a = dt > 0 ? alpha(dt, this.cfg.joint_tau_s) : 1.0;
    const pts: Record<string, Pt> = {};
    this.joints.forEach((name, i) => {
      const j = joints[i];
      const ok = j != null && j[2] >= this.cfg.min_conf;
      const prev = this.sm[name];
      if (ok) {
        let x = j![0] * aspect, y = j![1];
        if (prev !== undefined && t - prev[2] <= this.cfg.hold_s) {
          x = prev[0] + a * (x - prev[0]);
          y = prev[1] + a * (y - prev[1]);
        }
        this.sm[name] = [x, y, t];
        pts[name] = [x, y];
      } else if (prev !== undefined && t - prev[2] <= this.cfg.hold_s) {
        pts[name] = [prev[0], prev[1]];
      }
    });
    return pts;
  }

  private hand(pts: Record<string, Pt>): Pt | null {
    if (this.profile.tracker === "hands_mid") {
      const ws = ["l_wrist", "r_wrist"].filter((n) => n in pts).map((n) => pts[n]);
      if (!ws.length) return null;
      return [ws.reduce((s, w) => s + w[0], 0) / ws.length, ws.reduce((s, w) => s + w[1], 0) / ws.length];
    }
    return pts[this.dom + "_wrist"] ?? null;
  }

  private sample(t: number, joints: Joint[], aspect: number): Sample | null {
    const pts = this.smooth(t, joints, aspect);
    if (!["l_shoulder", "r_shoulder", "l_hip", "r_hip"].every((n) => n in pts)) return null;
    const hand = this.hand(pts);
    if (hand === null) return null;
    const sh = mid(pts.l_shoulder, pts.r_shoulder);
    const hip = mid(pts.l_hip, pts.r_hip);
    const torsoNow = dist(sh, hip);
    if (torsoNow < 0.02) return null;
    const dt = this.prevT !== null ? t - this.prevT : 0.0;
    if (this.torso === null) this.torso = torsoNow;
    else if (dt > 0) this.torso += alpha(dt, this.cfg.torso_tau_s) * (torsoNow - this.torso);
    const rel: Pt = [(hand[0] - hip[0]) / this.torso, (hand[1] - hip[1]) / this.torso];
    // Which image side the dominant shoulder is on; averaged slowly so a side-on turn does not flip it.
    const across = (pts[this.dom + "_shoulder"][0] - pts[this.off + "_shoulder"][0]) / this.torso;
    this.facing += (dt > 0 ? alpha(dt, this.cfg.facing_tau_s) : 1.0) * (across - this.facing);
    if (this.prevRel !== null && dt > 0) {
      const raw = dist(rel, this.prevRel) / dt;
      this.speed += alpha(dt, this.cfg.speed_tau_s) * (raw - this.speed);
    } else {
      this.speed = 0.0;
    }
    this.prevRel = rel;
    return { t, pts, torso: this.torso, hip, rx: rel[0], ry: rel[1], speed: this.speed };
  }

  // ---- state machine ----
  /** joints: aligned with profiles.joints, each [x, y, conf] or null. */
  push(t: number, joints: Joint[], aspect: number): EngineEvent[] {
    const events: EngineEvent[] = [];
    const dt = this.prevT !== null ? t - this.prevT : 0.0;
    const s = this.sample(t, joints, aspect);
    this.prevT = t;
    this.lastSample = s;

    if (s === null) {
      this.prevRel = null;
      this.visibleSince = null;
      const lostFor = this.lastVisibleT !== null ? t - this.lastVisibleT : 1e9;
      if (lostFor >= this.cfg.no_person_s && this.state !== "no_person") {
        if (this.state === "active") events.push(this.reject(t, "lost_tracking", {}));
        this.resetMotion();
        this.state = "no_person";
      }
      return events;
    }

    this.lastVisibleT = t;
    this.buf.push(s);
    const horizon = this.det.max_lookback_s + this.gates.max_duration_s + 2.0;
    while (this.buf.length && t - this.buf[0].t > horizon) this.buf.shift();

    if (this.state === "no_person") this.state = "moving";
    if (this.visibleSince === null) this.visibleSince = t;
    // Someone who never stands quite still is armed after being in view for a while.
    if (t - this.visibleSince >= this.cfg.arm_after_s) this.armed = true;

    if (s.speed < this.det.rest_speed) {
      if (this.quietSince === null) this.quietSince = t;
      if (t - this.quietSince >= this.det.rest_ms / 1000.0) {
        this.lastRestT = t;
        this.armed = true;
      }
    } else {
      this.quietSince = null;
    }

    if (this.state === "active") {
      this.activeS += dt;
      if (s.speed < this.det.exit_speed) {
        if (this.belowSince === null) this.belowSince = t;
        if (t - this.belowSince >= this.det.settle_ms / 1000.0) events.push(this.finalize(t));
      } else {
        this.belowSince = null;
      }
      if (s.speed > this.peakV) { this.peakV = s.speed; this.peakT = t; }
      // Once a fast enough phase is post_peak_s behind us, judge the motion without waiting for stillness.
      if (this.state === "active" && this.peakV >= this.gates.min_peak_speed
          && t - this.peakT >= this.det.post_peak_s) events.push(this.finalize(t));
      if (s.speed < this.det.rest_speed) {
        if (!this.inDip) this.dips.push(t);
        this.inDip = true;
      } else {
        this.inDip = false;
      }
      if (this.state === "active" && t - this.segStartT > this.gates.max_duration_s) {
        // Fidgeting can run straight into the real motion: drop the oldest movement up to the next pause.
        const later = this.dips.filter((d) => d > this.segStartT);
        if (later.length) {
          this.segStartT = later[0];
          this.dips = later.slice(1);
          this.peakV = 0.0; this.peakT = t;
          for (const x of this.buf) {
            if (x.t >= this.segStartT && x.speed > this.peakV) { this.peakV = x.speed; this.peakT = x.t; }
          }
        } else {
          events.push(this.reject(t, "too_long", {}));
          this.armed = false;
          this.visibleSince = t;
          this.endSegment();
        }
      }
    } else {
      this.passiveS += dt;
      if (s.speed >= this.det.enter_speed) {
        if (this.fastSince === null) this.fastSince = t;
        const longEnough = t - this.fastSince >= this.det.enter_ms / 1000.0;
        if (longEnough && this.armed && t >= this.cooldownUntil) {
          let start = t - this.det.max_lookback_s;
          if (this.lastRestT !== null && t - this.lastRestT <= this.det.max_lookback_s) {
            start = this.lastRestT - this.det.rest_ms / 1000.0;
          }
          this.segStartT = Math.max(start, this.lastSegEndT);
          this.belowSince = null;
          this.dips = [];
          this.inDip = false;
          this.peakV = s.speed; this.peakT = t;
          this.state = "active";
        }
      } else {
        this.fastSince = null;
      }
      if (this.state !== "active") this.state = this.armed ? "ready" : "moving";
    }
    return events;
  }

  private resetMotion() {
    this.quietSince = null;
    this.lastRestT = null;
    this.armed = false;
    this.fastSince = null;
    this.belowSince = null;
    this.speed = 0.0;
  }

  private endSegment() {
    this.fastSince = null;
    this.belowSince = null;
    this.state = this.armed ? "ready" : "moving";
  }

  private reject(t: number, reason: string, stats: Record<string, number>): EngineEvent {
    this.rejected[reason] = (this.rejected[reason] ?? 0) + 1;
    return { kind: "rejected", t, reason, stats };
  }

  private finalize(t: number): EngineEvent {
    const seg = this.buf.filter((x) => x.t >= this.segStartT);
    this.endSegment();
    const stats = segmentStats(seg);
    const reason = gateFailure(stats, this.gates);
    if (reason) return this.reject(t, reason, stats);
    const result = ANALYZERS[this.profile.analyzer](seg, this);
    if (result === null) return this.reject(t, "bad_pattern", stats);
    const [repType, ev, metrics] = result;
    const { scores, total, cues } = scoreRep(metrics, repType, this.profile.metrics, this.scoring);
    if (total === null) return this.reject(t, "no_metrics", stats);
    const rep: Rep = {
      t_start: seg[0].t, t_end: seg[seg.length - 1].t, type: repType, events: ev, metrics, scores,
      score: total, cues, peak_speed: stats.peak_speed,
    };
    this.reps.push(rep);
    // Only a counted rep closes off its frames; a rejected take-back may belong to the next motion.
    this.lastSegEndT = t;
    this.cooldownUntil = t + this.det.refractory_ms / 1000.0;
    return { kind: "rep", t, rep, reason: "", stats };
  }
}

export function segmentStats(seg: Sample[]): Record<string, number> {
  let path = 0.0;
  let extent = 0.0;
  for (let i = 1; i < seg.length; i++) {
    path += Math.hypot(seg[i].rx - seg[i - 1].rx, seg[i].ry - seg[i - 1].ry);
    extent = Math.max(extent, Math.hypot(seg[i].rx - seg[0].rx, seg[i].ry - seg[0].ry));
  }
  const xs = seg.map((s) => s.rx);
  const ys = seg.map((s) => s.ry);
  let peak = -Infinity;
  for (const s of seg) peak = Math.max(peak, s.speed);
  return {
    duration: seg[seg.length - 1].t - seg[0].t,
    peak_speed: peak,
    path_len: path,
    extent,
    vertical_range: Math.max(...ys) - Math.min(...ys),
    horizontal_range: Math.max(...xs) - Math.min(...xs),
    start_y: ys[0],
    min_y: Math.min(...ys),
  };
}

export function gateFailure(st: Record<string, number>, g: Profiles): string {
  if (st.duration < g.min_duration_s) return "too_short";
  if (st.duration > g.max_duration_s) return "too_long";
  if (st.peak_speed < g.min_peak_speed) return "too_slow";
  if (st.path_len < g.min_path_len) return "too_small";
  if (st.vertical_range < g.min_vertical_range) return "too_small";
  if (st.horizontal_range < g.min_horizontal_range) return "too_small";
  if ("min_extent" in g && st.extent < g.min_extent) return "too_small";
  if ("min_path_ratio" in g && st.path_len < g.min_path_ratio * st.extent) return "one_way";
  if ("start_hand_min_y" in g && st.start_y < g.start_hand_min_y) return "bad_start";
  if ("peak_hand_max_y" in g && st.min_y > g.peak_hand_max_y) return "not_high_enough";
  return "";
}

export interface Recording {
  sport: string;
  handedness?: string;
  aspect?: number;
  view?: string | null;
  focus?: string | null;
  frames: { t: number; j: Joint[] }[];
}

export function analyzeRecording(rec: Recording, profiles: Profiles) {
  const eng = new Engine(profiles, rec.sport, rec.handedness ?? "right", rec.view ?? null, rec.focus ?? null);
  const events: EngineEvent[] = [];
  for (const fr of rec.frames) events.push(...eng.push(fr.t, fr.j, rec.aspect ?? 1.0));
  return { eng, events };
}
