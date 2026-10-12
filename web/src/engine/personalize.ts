// Port of ml/formcoach/personalize.py: adapt a sport profile's scoring to the player and the drill.
// Without a player or drill the profile is returned unchanged.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Json = any;

export interface Player { height_cm?: number | null; level?: string | null }

export interface Drill {
  id: string; label: string; about: string; goal_reps: number;
  types?: string[]; emphasis?: Record<string, number>; trainings?: string[]; tip?: string;
}

export function findDrill(profile: Json, drillId: string | null | undefined): Drill | null {
  if (!drillId) return null;
  return (profile.drills ?? []).find((d: Drill) => d.id === drillId) ?? null;
}

/** Drills offered for a tennis training type (or every drill for sports without training types). */
export function drillsFor(profile: Json, training: string | null): Drill[] {
  return (profile.drills ?? []).filter((d: Drill) => training === null || !d.trainings || d.trainings.includes(training));
}

function targets(spec: Json): Json[] {
  return [spec, ...Object.values(spec.by_type ?? {}).filter((o) => o != null)];
}

export function personalize(profile: Json, playerCfg: Json, player: Player | null = null,
                            drillId: string | null = null): Json {
  const drill = findDrill(profile, drillId);
  if (!player && !drill) return profile;
  const out = { ...profile, metrics: structuredClone(profile.metrics) };
  const p = player ?? {};
  const cfg = playerCfg ?? {};
  const level = (cfg.levels ?? {})[p.level ?? ""];
  const height = p.height_cm;
  const emphasis = drill?.emphasis ?? {};
  for (const spec of out.metrics) {
    if (level != null) {
      for (const t of targets(spec)) {
        t.tol = t.tol * level.tol_scale;
        t.std = t.std * level.std_scale;
      }
    }
    const shift = spec.height_shift;
    if (shift != null && height) {
      let steps = (cfg.reference_height_cm - height) / 10.0;
      steps = Math.max(-shift.max_steps, Math.min(shift.max_steps, steps));
      for (const t of targets(spec)) t.mean = t.mean + shift.per_10cm * steps;
    }
    const mult = emphasis[spec.id];
    if (mult != null) {
      spec.weight = spec.weight * mult;
      spec.focus = mult > 1.0;
    }
  }
  out.drill = drill;
  return out;
}

/** Shoulder-to-hip length in metres estimated from standing height, for showing real units. */
export function torsoM(heightCm: number | null | undefined, playerCfg: Json): number | null {
  return heightCm ? (heightCm / 100.0) * playerCfg.torso_fraction : null;
}
