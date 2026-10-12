// The player's profile (height, level, units), kept in this browser, and the real-world units it unlocks.
import { pref, setPref } from "./store.ts";
import { torsoM, type Player } from "../engine/personalize.ts";

export type Units = "metric" | "imperial";

export interface PlayerPrefs extends Player { units: Units }

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function loadPlayer(cfg: any): PlayerPrefs {
  const h = pref<number | null>("heightCm", null);
  const level = pref<string>("level", cfg.default_level);
  const ok = typeof h === "number" && h >= cfg.min_height_cm && h <= cfg.max_height_cm;
  return { height_cm: ok ? h : null, level: level in cfg.levels ? level : cfg.default_level,
           units: pref<Units>("units", navigator.language === "en-US" ? "imperial" : "metric") };
}

export function savePlayer(p: PlayerPrefs) {
  setPref("heightCm", p.height_cm ?? null);
  setPref("level", p.level);
  setPref("units", p.units);
}

export const cmToFtIn = (cm: number): [number, number] => {
  const inches = Math.round(cm / 2.54);
  return [Math.floor(inches / 12), inches % 12];
};
export const ftInToCm = (ft: number, inch: number) => (ft * 12 + inch) * 2.54;

export function heightLabel(cm: number | null | undefined, units: Units) {
  if (!cm) return "not set";
  if (units === "metric") return `${Math.round(cm)} cm`;
  const [ft, inch] = cmToFtIn(cm);
  return `${ft}′${inch}″`;
}

/** Peak hand speed of a rep, from torso lengths per second to mph or km/h. 2D only, so an estimate. */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function handSpeed(peakTorsoPerS: number, p: Player, cfg: any, units: Units): number | null {
  const t = torsoM(p.height_cm, cfg);
  if (t == null) return null;
  const mps = peakTorsoPerS * t;
  return units === "metric" ? mps * 3.6 : mps * 2.23694;
}

export const speedUnit = (u: Units) => (u === "metric" ? "km/h" : "mph");

/** A torso-length value as a real distance (cm or in), when the height is known. */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function torsoToReal(v: number, p: Player, cfg: any, units: Units): string | null {
  const t = torsoM(p.height_cm, cfg);
  if (t == null) return null;
  const cm = v * t * 100;
  return units === "metric" ? `${cm.toFixed(0)} cm` : `${(cm / 2.54).toFixed(1)} in`;
}

/** Closest a phone held upright (about 70° vertical field of view) can be and still fit you head to feet. */
export function minPhoneDistance(heightCm: number, units: Units) {
  const m = (heightCm / 100 / 0.85) / 2 / Math.tan((70 / 2) * Math.PI / 180);
  return units === "metric" ? `${m.toFixed(1)} m` : `${Math.ceil(m * 3.281)} ft`;
}
