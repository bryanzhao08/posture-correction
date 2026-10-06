// Port of ml/formcoach/scoring.py: raw metrics -> 0-100 scores against the pro reference ranges.
import type { Metrics } from "./sports.ts";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Spec = any;

/** [mean, std, tol] for this rep type, or null when the metric does not apply. */
export function targetFor(spec: Spec, repType: string): [number, number, number] | null {
  const only = spec.only_types;
  if (only != null && !only.includes(repType)) return null;
  const byType = spec.by_type ?? {};
  if (repType in byType) {
    const o = byType[repType];
    if (o == null) return null;
    return [o.mean, o.std, o.tol];
  }
  return [spec.mean, spec.std, spec.tol];
}

export function metricScore(value: number, spec: Spec, repType: string, zScale: number): number | null {
  const tgt = targetFor(spec, repType);
  if (tgt === null) return null;
  const [mean, std, tol] = tgt;
  const dev = value - mean;
  const side = spec.one_sided;
  if ((side === "high" && dev < 0) || (side === "low" && dev > 0)) return 100.0;
  const z = Math.max(0.0, Math.abs(dev) - tol) / std;
  return 100.0 * Math.exp(-0.5 * (z / zScale) ** 2);
}

export function scoreRep(metrics: Metrics, repType: string, specs: Spec[], scoring: Spec) {
  const scores: Record<string, number> = {};
  let wsum = 0.0;
  let total = 0.0;
  const worst: [number, string][] = [];
  for (const spec of specs) {
    const v = metrics[spec.id];
    if (v == null) continue;
    const s = metricScore(v, spec, repType, scoring.z_scale);
    if (s === null) continue;
    scores[spec.id] = s;
    wsum += spec.weight;
    total += spec.weight * s;
    if (s < 75.0) {
      const mean = targetFor(spec, repType)![0];
      const cue = v > mean ? spec.cue_high : spec.cue_low;
      if (cue) worst.push([s, cue]);
    }
  }
  if (wsum === 0) return { scores, total: null as number | null, cues: [] as string[] };
  worst.sort((a, b) => a[0] - b[0]);
  return { scores, total: total / wsum as number | null, cues: worst.slice(0, 2).map((w) => w[1]) };
}

export interface RepLike {
  type: string;
  metrics: Metrics;
  scores: Record<string, number>;
  score: number;
  cues: string[];
}

export interface Summary {
  sport: string;
  rep_count: number;
  rejected: Record<string, number>;
  types: Record<string, number>;
  score: number | null;
  form_score: number | null;
  consistency: number | null;
  metrics: Record<string, { mean: number; sd: number; score: number; n: number }>;
  top_cues: string[];
  active_s: number;
  passive_s: number;
}

export function summarize(sport: string, reps: RepLike[], rejected: Record<string, number>, specs: Spec[],
                          scoring: Spec, activeS = 0.0, passiveS = 0.0): Summary {
  const metrics: Summary["metrics"] = {};
  const cons: number[] = [];
  for (const spec of specs) {
    const use = reps.filter((r) => r.scores[spec.id] != null);
    const vals = use.map((r) => r.metrics[spec.id] as number);
    const scs = use.map((r) => r.scores[spec.id]);
    if (!vals.length) continue;
    const m = vals.reduce((a, b) => a + b, 0) / vals.length;
    const sd = Math.sqrt(vals.reduce((a, v) => a + (v - m) ** 2, 0) / vals.length);
    metrics[spec.id] = { mean: m, sd, score: scs.reduce((a, b) => a + b, 0) / scs.length, n: vals.length };
    if (vals.length >= 3) cons.push(100.0 * Math.exp(-0.5 * (sd / (scoring.z_scale * spec.std)) ** 2));
  }
  const form = reps.length ? reps.reduce((a, r) => a + r.score, 0) / reps.length : null;
  const consistency = cons.length ? cons.reduce((a, b) => a + b, 0) / cons.length : null;
  let score: number | null;
  if (form === null) score = null;
  else if (consistency === null) score = form;
  else score = scoring.form_weight * form + scoring.consistency_weight * consistency;
  const cueCounts: Record<string, number> = {};
  for (const r of reps) for (const c of r.cues) cueCounts[c] = (cueCounts[c] ?? 0) + 1;
  const top = Object.entries(cueCounts)
    .sort((a, b) => b[1] - a[1] || (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0))
    .slice(0, 3);
  const types: Record<string, number> = {};
  for (const r of reps) types[r.type] = (types[r.type] ?? 0) + 1;
  return {
    sport, rep_count: reps.length, rejected, types, score, form_score: form, consistency,
    metrics, top_cues: top.map(([c]) => c), active_s: activeS, passive_s: passiveS,
  };
}
