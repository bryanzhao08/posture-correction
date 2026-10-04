"""Turn raw metrics into 0-100 scores against the professional reference ranges."""
from __future__ import annotations

import math


def target_for(spec: dict, rep_type: str):
    """Returns (mean, std, tol) for this rep type, or None when the metric does not apply."""
    only = spec.get("only_types")
    if only is not None and rep_type not in only:
        return None
    by_type = spec.get("by_type") or {}
    if rep_type in by_type:
        o = by_type[rep_type]
        if o is None:
            return None
        return o["mean"], o["std"], o["tol"]
    return spec["mean"], spec["std"], spec["tol"]


def metric_score(value: float, spec: dict, rep_type: str, z_scale: float):
    tgt = target_for(spec, rep_type)
    if tgt is None:
        return None
    mean, std, tol = tgt
    dev = value - mean
    side = spec.get("one_sided")
    if (side == "high" and dev < 0) or (side == "low" and dev > 0):
        return 100.0
    z = max(0.0, abs(dev) - tol) / std
    return 100.0 * math.exp(-0.5 * (z / z_scale) ** 2)


def score_rep(metrics: dict, rep_type: str, specs: list, scoring: dict):
    scores = {}
    wsum = 0.0
    total = 0.0
    worst = []
    for spec in specs:
        v = metrics.get(spec["id"])
        if v is None:
            continue
        s = metric_score(v, spec, rep_type, scoring["z_scale"])
        if s is None:
            continue
        scores[spec["id"]] = s
        wsum += spec["weight"]
        total += spec["weight"] * s
        if s < 75.0:
            mean = target_for(spec, rep_type)[0]
            cue = spec["cue_high"] if v > mean else spec["cue_low"]
            if cue:
                worst.append((s, cue))
    if wsum == 0:
        return scores, None, []
    worst.sort(key=lambda x: x[0])
    return scores, total / wsum, [c for _, c in worst[:2]]


def summarize(sport: str, reps: list, rejected: dict, specs: list, scoring: dict,
              active_s: float = 0.0, passive_s: float = 0.0) -> dict:
    """reps: list of rep dicts (Rep.to_dict())."""
    metrics = {}
    cons = []
    for spec in specs:
        vals = [r["metrics"][spec["id"]] for r in reps if r["scores"].get(spec["id"]) is not None]
        scs = [r["scores"][spec["id"]] for r in reps if r["scores"].get(spec["id"]) is not None]
        if not vals:
            continue
        m = sum(vals) / len(vals)
        sd = math.sqrt(sum((v - m) ** 2 for v in vals) / len(vals))
        metrics[spec["id"]] = {"mean": m, "sd": sd, "score": sum(scs) / len(scs), "n": len(vals)}
        if len(vals) >= 3:
            cons.append(100.0 * math.exp(-0.5 * (sd / (scoring["z_scale"] * spec["std"])) ** 2))
    form = sum(r["score"] for r in reps) / len(reps) if reps else None
    consistency = sum(cons) / len(cons) if cons else None
    if form is None:
        score = None
    elif consistency is None:
        score = form
    else:
        score = scoring["form_weight"] * form + scoring["consistency_weight"] * consistency
    cue_counts = {}
    for r in reps:
        for c in r["cues"]:
            cue_counts[c] = cue_counts.get(c, 0) + 1
    top = sorted(cue_counts.items(), key=lambda kv: (-kv[1], kv[0]))[:3]
    types = {}
    for r in reps:
        types[r["type"]] = types.get(r["type"], 0) + 1
    return {
        "sport": sport, "rep_count": len(reps), "rejected": rejected, "types": types,
        "score": score, "form_score": form, "consistency": consistency,
        "metrics": metrics, "top_cues": [c for c, _ in top],
        "active_s": active_s, "passive_s": passive_s,
    }
