"""Reference implementation of the FormCoach analysis engine.

The Swift package ios/FormCore is a line-for-line port of this file and sports.py;
ml/tests/test_parity.py + `swift run formcore-check` keep the two in agreement.

Coordinates: joints arrive normalised (0..1, origin top-left, y down) and are converted to
"height units" (x multiplied by aspect = width/height) so angles are not distorted.
Body-relative values are measured from the mid-hip in torso lengths (hip = 0, shoulders = -1).
"""
from __future__ import annotations

import json
import math
from dataclasses import dataclass, field
from pathlib import Path

from . import sports
from .scoring import score_rep

PROFILES_PATH = Path(__file__).resolve().parents[2] / "shared" / "sport_profiles.json"


def load_profiles(path: Path | str = PROFILES_PATH) -> dict:
    return json.loads(Path(path).read_text())


@dataclass
class Sample:
    t: float
    pts: dict            # joint name -> (x, y) smoothed, height units
    torso: float
    hip: tuple           # mid-hip (x, y)
    rx: float            # tracked hand relative to hip, torso units
    ry: float
    speed: float         # torso lengths / second, smoothed


@dataclass
class Rep:
    t_start: float
    t_end: float
    type: str
    events: dict
    metrics: dict
    scores: dict
    score: float
    cues: list
    peak_speed: float

    def to_dict(self) -> dict:
        return {
            "t_start": self.t_start, "t_end": self.t_end, "type": self.type, "events": self.events,
            "metrics": self.metrics, "scores": self.scores, "score": self.score, "cues": self.cues,
            "peak_speed": self.peak_speed,
        }


@dataclass
class Event:
    kind: str                 # "rep" | "rejected"
    t: float
    rep: Rep | None = None
    reason: str = ""
    stats: dict = field(default_factory=dict)


def _alpha(dt: float, tau: float) -> float:
    return 1.0 - math.exp(-dt / tau) if tau > 0 else 1.0


class Engine:
    """Streaming state machine: push one pose frame at a time, get back counted reps.

    States: no_person -> moving (seen, not yet armed) -> ready (armed) -> active -> ready
    A motion is only counted when it is fast enough to trigger, passes every gate in the sport
    profile, and has the shape of the sport's movement (the analyzer's pattern check).
    Everything else is reported as a rejected motion, never as a rep.
    """

    def __init__(self, profiles: dict, sport: str, handedness: str = "right"):
        self.cfg = profiles["preprocess"]
        self.scoring = profiles["scoring"]
        self.joints = profiles["joints"]
        self.sport = sport
        self.profile = profiles["sports"][sport]
        self.det = self.profile["detect"]
        self.gates = self.profile["gates"]
        self.dom = "r" if handedness == "right" else "l"
        self.off = "l" if self.dom == "r" else "r"

        self.state = "no_person"
        self.buf: list[Sample] = []
        self.reps: list[Rep] = []
        self.rejected: dict[str, int] = {}
        self.active_s = 0.0
        self.passive_s = 0.0

        self._sm: dict = {}          # joint -> (x, y, last_seen_t)
        self._torso = None
        self._prev_rel = None
        self._prev_t = None
        self._speed = 0.0
        self._last_visible_t = None
        self._quiet_since = None
        self._last_rest_t = None
        self._armed = False
        self._fast_since = None
        self._below_since = None
        self._seg_start_t = 0.0
        self._cooldown_until = -1.0
        self._last_seg_end_t = -1.0
        self._dips: list[float] = []
        self._in_dip = False
        self._visible_since = None
        self._peak_v = 0.0
        self._peak_t = 0.0
        self.facing = 0.0            # slow average of dominant minus other shoulder x, torso units

    # ---- preprocessing -------------------------------------------------
    def _smooth(self, t: float, joints: list, aspect: float) -> dict:
        dt = (t - self._prev_t) if self._prev_t is not None else 0.0
        a = _alpha(dt, self.cfg["joint_tau_s"]) if dt > 0 else 1.0
        pts = {}
        for name, j in zip(self.joints, joints):
            ok = j is not None and j[2] >= self.cfg["min_conf"]
            prev = self._sm.get(name)
            if ok:
                x, y = j[0] * aspect, j[1]
                if prev is not None and t - prev[2] <= self.cfg["hold_s"]:
                    x = prev[0] + a * (x - prev[0])
                    y = prev[1] + a * (y - prev[1])
                self._sm[name] = (x, y, t)
                pts[name] = (x, y)
            elif prev is not None and t - prev[2] <= self.cfg["hold_s"]:
                pts[name] = (prev[0], prev[1])
        return pts

    def _hand(self, pts: dict):
        if self.profile["tracker"] == "hands_mid":
            ws = [pts[n] for n in ("l_wrist", "r_wrist") if n in pts]
            if not ws:
                return None
            return (sum(w[0] for w in ws) / len(ws), sum(w[1] for w in ws) / len(ws))
        return pts.get(self.dom + "_wrist")

    def _sample(self, t: float, joints: list, aspect: float) -> Sample | None:
        pts = self._smooth(t, joints, aspect)
        if not all(n in pts for n in ("l_shoulder", "r_shoulder", "l_hip", "r_hip")):
            return None
        hand = self._hand(pts)
        if hand is None:
            return None
        sh = sports.mid(pts["l_shoulder"], pts["r_shoulder"])
        hip = sports.mid(pts["l_hip"], pts["r_hip"])
        torso_now = sports.dist(sh, hip)
        if torso_now < 0.02:
            return None
        dt = (t - self._prev_t) if self._prev_t is not None else 0.0
        if self._torso is None:
            self._torso = torso_now
        elif dt > 0:
            self._torso += _alpha(dt, self.cfg["torso_tau_s"]) * (torso_now - self._torso)
        rel = ((hand[0] - hip[0]) / self._torso, (hand[1] - hip[1]) / self._torso)
        # Which image side the dominant shoulder is on when the player faces the camera. Averaged
        # slowly so that turning side-on during a stroke does not flip it.
        across = (pts[self.dom + "_shoulder"][0] - pts[self.off + "_shoulder"][0]) / self._torso
        self.facing += (_alpha(dt, self.cfg["facing_tau_s"]) if dt > 0 else 1.0) * (across - self.facing)
        if self._prev_rel is not None and dt > 0:
            raw = sports.dist(rel, self._prev_rel) / dt
            self._speed += _alpha(dt, self.cfg["speed_tau_s"]) * (raw - self._speed)
        else:
            self._speed = 0.0
        self._prev_rel = rel
        return Sample(t, pts, self._torso, hip, rel[0], rel[1], self._speed)

    # ---- state machine -------------------------------------------------
    def push(self, t: float, joints: list, aspect: float) -> list[Event]:
        """joints: list aligned with profiles['joints'] of [x, y, conf] (or None)."""
        events: list[Event] = []
        dt = (t - self._prev_t) if self._prev_t is not None else 0.0
        s = self._sample(t, joints, aspect)
        self._prev_t = t

        if s is None:
            self._prev_rel = None
            self._visible_since = None
            lost_for = t - self._last_visible_t if self._last_visible_t is not None else 1e9
            if lost_for >= self.cfg["no_person_s"] and self.state != "no_person":
                if self.state == "active":
                    events.append(self._reject(t, "lost_tracking", {}))
                self._reset_motion()
                self.state = "no_person"
            return events

        self._last_visible_t = t
        self.buf.append(s)
        horizon = self.det["max_lookback_s"] + self.gates["max_duration_s"] + 2.0
        while self.buf and t - self.buf[0].t > horizon:
            self.buf.pop(0)

        if self.state == "no_person":
            self.state = "moving"
        if self._visible_since is None:
            self._visible_since = t
        # Normally stillness arms the counter; someone who never stands quite still is armed after
        # being in view for a while, and the gates and pattern checks do the filtering.
        if t - self._visible_since >= self.cfg["arm_after_s"]:
            self._armed = True

        if s.speed < self.det["rest_speed"]:
            if self._quiet_since is None:
                self._quiet_since = t
            if t - self._quiet_since >= self.det["rest_ms"] / 1000.0:
                self._last_rest_t = t
                self._armed = True
        else:
            self._quiet_since = None

        if self.state == "active":
            self.active_s += dt
            if s.speed < self.det["exit_speed"]:
                if self._below_since is None:
                    self._below_since = t
                if t - self._below_since >= self.det["settle_ms"] / 1000.0:
                    events.append(self._finalize(t))
            else:
                self._below_since = None
            if s.speed > self._peak_v:
                self._peak_v, self._peak_t = s.speed, t
            # People often keep moving after the swing (recoil, walking off). Once a fast enough
            # phase is post_peak_s behind us, judge the motion without waiting for stillness.
            if (self.state == "active" and self._peak_v >= self.gates["min_peak_speed"]
                    and t - self._peak_t >= self.det["post_peak_s"]):
                events.append(self._finalize(t))
            if s.speed < self.det["rest_speed"]:
                if not self._in_dip:
                    self._dips.append(t)
                self._in_dip = True
            else:
                self._in_dip = False
            if self.state == "active" and t - self._seg_start_t > self.gates["max_duration_s"]:
                # Fidgeting (waggles, bouncing the ball) can run straight into the real motion.
                # Drop the oldest movement up to the next momentary pause rather than the lot.
                later = [d for d in self._dips if d > self._seg_start_t]
                if later:
                    self._seg_start_t = later[0]
                    self._dips = later[1:]
                    self._peak_v, self._peak_t = 0.0, t
                    for x in self.buf:
                        if x.t >= self._seg_start_t and x.speed > self._peak_v:
                            self._peak_v, self._peak_t = x.speed, x.t
                else:
                    events.append(self._reject(t, "too_long", {}))
                    self._armed = False
                    self._visible_since = t
                    self._end_segment(t)
        else:
            self.passive_s += dt
            if s.speed >= self.det["enter_speed"]:
                if self._fast_since is None:
                    self._fast_since = t
                long_enough = t - self._fast_since >= self.det["enter_ms"] / 1000.0
                if long_enough and self._armed and t >= self._cooldown_until:
                    start = t - self.det["max_lookback_s"]
                    if self._last_rest_t is not None and t - self._last_rest_t <= self.det["max_lookback_s"]:
                        start = self._last_rest_t - self.det["rest_ms"] / 1000.0
                    self._seg_start_t = max(start, self._last_seg_end_t)
                    self._below_since = None
                    self._dips = []
                    self._in_dip = False
                    self._peak_v, self._peak_t = s.speed, t
                    self.state = "active"
            else:
                self._fast_since = None
            if self.state != "active":
                self.state = "ready" if self._armed else "moving"
        return events

    def _reset_motion(self):
        self._quiet_since = None
        self._last_rest_t = None
        self._armed = False
        self._fast_since = None
        self._below_since = None
        self._speed = 0.0

    def _end_segment(self, t: float):
        self._fast_since = None
        self._below_since = None
        self.state = "ready" if self._armed else "moving"

    def _reject(self, t: float, reason: str, stats: dict) -> Event:
        self.rejected[reason] = self.rejected.get(reason, 0) + 1
        return Event("rejected", t, None, reason, stats)

    def _finalize(self, t: float) -> Event:
        seg = [x for x in self.buf if x.t >= self._seg_start_t]
        self._end_segment(t)
        stats = segment_stats(seg)
        reason = gate_failure(stats, self.gates)
        if reason:
            return self._reject(t, reason, stats)
        result = sports.ANALYZERS[self.profile["analyzer"]](seg, self)
        if result is None:
            return self._reject(t, "bad_pattern", stats)
        rep_type, ev, metrics = result
        scores, total, cues = score_rep(metrics, rep_type, self.profile["metrics"], self.scoring)
        if total is None:
            return self._reject(t, "no_metrics", stats)
        rep = Rep(seg[0].t, seg[-1].t, rep_type, ev, metrics, scores, total, cues, stats["peak_speed"])
        self.reps.append(rep)
        # only a counted rep closes off its frames; a rejected take-back may belong to the next motion
        self._last_seg_end_t = t
        self._cooldown_until = t + self.det["refractory_ms"] / 1000.0
        return Event("rep", t, rep, "", stats)


def segment_stats(seg: list[Sample]) -> dict:
    path = 0.0
    extent = 0.0
    for i in range(1, len(seg)):
        path += math.hypot(seg[i].rx - seg[i - 1].rx, seg[i].ry - seg[i - 1].ry)
        extent = max(extent, math.hypot(seg[i].rx - seg[0].rx, seg[i].ry - seg[0].ry))
    xs = [s.rx for s in seg]
    ys = [s.ry for s in seg]
    return {
        "duration": seg[-1].t - seg[0].t,
        "peak_speed": max(s.speed for s in seg),
        "path_len": path,
        "extent": extent,
        "vertical_range": max(ys) - min(ys),
        "horizontal_range": max(xs) - min(xs),
        "start_y": ys[0],
        "min_y": min(ys),
    }


def gate_failure(st: dict, g: dict) -> str:
    if st["duration"] < g["min_duration_s"]:
        return "too_short"
    if st["duration"] > g["max_duration_s"]:
        return "too_long"
    if st["peak_speed"] < g["min_peak_speed"]:
        return "too_slow"
    if st["path_len"] < g["min_path_len"]:
        return "too_small"
    if st["vertical_range"] < g["min_vertical_range"]:
        return "too_small"
    if st["horizontal_range"] < g["min_horizontal_range"]:
        return "too_small"
    if "min_extent" in g and st["extent"] < g["min_extent"]:
        return "too_small"
    if "min_path_ratio" in g and st["path_len"] < g["min_path_ratio"] * st["extent"]:
        return "one_way"
    if "start_hand_min_y" in g and st["start_y"] < g["start_hand_min_y"]:
        return "bad_start"
    if "peak_hand_max_y" in g and st["min_y"] > g["peak_hand_max_y"]:
        return "not_high_enough"
    return ""


def analyze_recording(rec: dict, profiles: dict | None = None) -> Engine:
    """rec: {"sport", "handedness", "aspect", "frames": [{"t", "j": [[x, y, c] * 13]}]}"""
    profiles = profiles or load_profiles()
    eng = Engine(profiles, rec["sport"], rec.get("handedness", "right"))
    eng.events = []
    for fr in rec["frames"]:
        eng.events.extend(eng.push(fr["t"], fr["j"], rec.get("aspect", 1.0)))
    return eng
