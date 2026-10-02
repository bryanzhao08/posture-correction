"""Averages, comparisons and checkpoints computed from stored sessions."""
import math
from datetime import timezone

from sqlalchemy import select
from sqlalchemy.orm import Session

from . import config
from .db import Checkpoint, PracticeSession, iso


def _metric_score(value: float, spec: dict) -> float:
    dev = value - spec["mean"]
    side = spec.get("one_sided")
    if (side == "high" and dev < 0) or (side == "low" and dev > 0):
        return 100.0
    z = max(0.0, abs(dev) - spec["tol"]) / spec["std"]
    return 100.0 * math.exp(-0.5 * (z / config.PROFILES["scoring"]["z_scale"]) ** 2)


def _order(x: PracticeSession):
    # SQLite returns naive datetimes; rows created in this request are still timezone-aware
    dt = x.started_at
    return (dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc), x.id)


def _mean(vals: list):
    vals = [v for v in vals if v is not None]
    return sum(vals) / len(vals) if vals else None


def _metric_avg(sessions: list[PracticeSession], metric_id: str):
    return _mean([(s.summary.get("metrics") or {}).get(metric_id, {}).get("mean") for s in sessions])


def metric_comparisons(sport: str, current: list[PracticeSession], previous: list[PracticeSession]) -> list:
    out = []
    for spec in config.PROFILES["sports"][sport]["metrics"]:
        value = _metric_avg(current, spec["id"])
        if value is None:
            continue
        prev = _metric_avg(previous, spec["id"])
        score = _metric_score(value, spec)
        direction = None
        if prev is not None:
            diff = score - _metric_score(prev, spec)
            direction = "better" if diff > 1 else "worse" if diff < -1 else "same"
        out.append({"id": spec["id"], "label": spec["label"], "unit": spec["unit"], "value": value,
                    "previous": prev, "pro": spec["mean"], "score": score, "direction": direction})
    return out


def user_sessions(db: Session, user_id: int, sport: str) -> list[PracticeSession]:
    """Oldest first."""
    q = (select(PracticeSession).where(PracticeSession.user_id == user_id, PracticeSession.sport == sport)
         .order_by(PracticeSession.started_at, PracticeSession.id))
    return list(db.scalars(q))


def comparison(db: Session, s: PracticeSession) -> dict:
    earlier = [x for x in user_sessions(db, s.user_id, s.sport)
               if _order(x) < _order(s) and x.rep_count > 0][-20:]
    prev_avg = _mean([x.score for x in earlier])
    return {
        "previous_sessions": len(earlier),
        "previous_avg_score": prev_avg,
        "score_delta": s.score - prev_avg if s.score is not None and prev_avg is not None else None,
        "metrics": metric_comparisons(s.sport, [s], earlier),
    }


def stats(db: Session, user_id: int, sport: str) -> dict:
    all_s = [x for x in user_sessions(db, user_id, sport) if x.rep_count > 0]
    n = config.CHECKPOINT_EVERY
    recent, previous = all_s[-n:], all_s[-2 * n:-n]
    scores = [x.score for x in all_s if x.score is not None]
    return {
        "sport": sport, "sessions": len(all_s), "total_reps": sum(x.rep_count for x in all_s),
        "avg_score": _mean(scores), "best_score": max(scores) if scores else None,
        "recent_avg_score": _mean([x.score for x in recent]),
        "previous_avg_score": _mean([x.score for x in previous]),
        "metrics": metric_comparisons(sport, recent, previous),
        "trend": [{"id": x.id, "started_at": iso(x.started_at), "score": x.score, "rep_count": x.rep_count}
                  for x in all_s],
    }


def checkpoint_out(c: Checkpoint) -> dict:
    return {"id": c.id, "sport": c.sport, "number": c.number, "created_at": iso(c.created_at), **c.data}


def maybe_checkpoint(db: Session, s: PracticeSession) -> Checkpoint | None:
    """Every CHECKPOINT_EVERY sessions with reps (per sport) closes a block and records its averages."""
    all_s = [x for x in user_sessions(db, s.user_id, s.sport) if x.rep_count > 0]
    n = config.CHECKPOINT_EVERY
    if s.rep_count == 0 or len(all_s) % n != 0:
        return None
    number = len(all_s) // n
    exists = db.scalar(select(Checkpoint).where(Checkpoint.user_id == s.user_id, Checkpoint.sport == s.sport,
                                                Checkpoint.number == number))
    if exists:
        return None
    block, previous = all_s[-n:], all_s[-2 * n:-n]
    cues: dict[str, int] = {}
    for x in block:
        for cue in x.summary.get("top_cues") or []:
            cues[cue] = cues.get(cue, 0) + 1
    data = {
        "sessions": len(block), "total_reps": sum(x.rep_count for x in block),
        "avg_score": _mean([x.score for x in block]),
        "previous_avg_score": _mean([x.score for x in previous]),
        "metrics": metric_comparisons(s.sport, block, previous),
        "focus_cues": [c for c, _ in sorted(cues.items(), key=lambda kv: (-kv[1], kv[0]))[:3]],
    }
    cp = Checkpoint(user_id=s.user_id, sport=s.sport, number=number, data=data)
    db.add(cp)
    db.commit()
    return cp
