"""Adapt a sport profile's scoring to the player and the drill they picked.

Ported to ios/FormCore (Personalize.swift) and web/src/engine/personalize.ts; parity tests keep them equal.

- level   widens (beginner) or tightens (pro) every metric's tolerance and spread, so a beginner's
          good rep scores well instead of being judged against tour pros.
- height  shifts the expected value of metrics that carry a `height_shift` (a coaching prior, e.g. a
          shorter basketball player needs more leg drive). Everything else is already measured in the
          player's own torso lengths, so it does not depend on height.
- drill   multiplies metric weights by the drill's `emphasis` (so the score reflects what is being
          practised), puts its cues first, and limits counted reps to the drill's stroke `types`.

Without a player or drill the profile is returned unchanged.
"""
from __future__ import annotations

import copy


def find_drill(profile: dict, drill_id: str | None) -> dict | None:
    if not drill_id:
        return None
    return next((d for d in profile.get("drills") or [] if d["id"] == drill_id), None)


def _targets(spec: dict) -> list:
    """The spec itself plus every by-type target that applies, so adjustments reach all of them."""
    return [spec] + [o for o in (spec.get("by_type") or {}).values() if o is not None]


def personalize(profile: dict, player_cfg: dict | None, player: dict | None = None,
                drill_id: str | None = None) -> dict:
    drill = find_drill(profile, drill_id)
    if not player and not drill:
        return profile
    out = dict(profile)
    out["metrics"] = copy.deepcopy(profile["metrics"])
    player = player or {}
    cfg = player_cfg or {}
    level = (cfg.get("levels") or {}).get(player.get("level") or "")
    height = player.get("height_cm")
    emphasis = (drill or {}).get("emphasis") or {}
    for spec in out["metrics"]:
        if level is not None:
            for t in _targets(spec):
                t["tol"] = t["tol"] * level["tol_scale"]
                t["std"] = t["std"] * level["std_scale"]
        shift = spec.get("height_shift")
        if shift is not None and height:
            steps = (cfg["reference_height_cm"] - height) / 10.0
            steps = max(-shift["max_steps"], min(shift["max_steps"], steps))
            for t in _targets(spec):
                t["mean"] = t["mean"] + shift["per_10cm"] * steps
        mult = emphasis.get(spec["id"])
        if mult is not None:
            spec["weight"] = spec["weight"] * mult
            spec["focus"] = mult > 1.0
    out["drill"] = drill
    return out


def torso_m(height_cm: float | None, player_cfg: dict) -> float | None:
    """Shoulder-to-hip length in metres estimated from standing height, for showing real units."""
    if not height_cm:
        return None
    return height_cm / 100.0 * player_cfg["torso_fraction"]
