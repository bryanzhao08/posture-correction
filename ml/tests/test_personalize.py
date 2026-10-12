"""Player level, height and drill selection adapt scoring without changing what gets counted."""
import pytest

from formcoach.engine import analyze_recording, effective_profile, load_profiles
from formcoach.personalize import personalize, torso_m
from formcoach.scoring import metric_score, score_rep
from formcoach.synth import recording
from tests.test_engine import CASES

P = load_profiles()


def rec(name, **kw):
    sport, script, _ = CASES[name]
    return dict(recording(sport, script, noise=0.0015, seed=1), **kw)


def spec(sport, metric, profile=None):
    prof = profile or P["sports"][sport]
    return next(m for m in prof["metrics"] if m["id"] == metric)


def test_no_player_or_drill_changes_nothing():
    base = effective_profile(P["sports"]["golf"], None)
    assert personalize(base, P["player"]) is base
    plain = analyze_recording(rec("golf_3_swings"), P)
    again = analyze_recording(rec("golf_3_swings", player=None, drill=None), P)
    assert [r.score for r in plain.reps] == [r.score for r in again.reps]


@pytest.mark.parametrize("sport", list(P["sports"]))
def test_every_drill_references_real_metrics_and_types(sport):
    prof = P["sports"][sport]
    ids = {m["id"] for m in prof["metrics"]}
    for view in (prof.get("views") or {}).values():
        ids |= {m["id"] for m in view.get("metrics") or []}
    trainings = {t["id"] for t in prof.get("training") or []}
    types = {"golf": {"swing"}, "basketball": {"shot"}, "tennis": {"forehand", "backhand", "serve"},
             "pickleball": {"forehand", "backhand", "overhead"}}[sport]
    assert prof["drills"], sport
    for d in prof["drills"]:
        assert set(d.get("emphasis", {})) <= ids, d["id"]
        assert set(d.get("types", [])) <= types, d["id"]
        assert set(d.get("trainings", [])) <= trainings, d["id"]
        assert d["goal_reps"] > 0


def test_beginner_scores_higher_than_pro_on_the_same_reps():
    by_level = {}
    for level in ("beginner", "intermediate", "advanced", "pro"):
        eng = analyze_recording(rec("tennis_mixed", player={"level": level}), P)
        by_level[level] = [r.score for r in eng.reps]
    assert len(by_level["beginner"]) == 3
    for i in range(3):
        assert by_level["beginner"][i] >= by_level["intermediate"][i] >= by_level["advanced"][i] >= by_level["pro"][i]
    assert sum(by_level["beginner"]) > sum(by_level["pro"])


def test_advanced_level_is_the_fitted_pro_range():
    plain = analyze_recording(rec("golf_3_swings"), P)
    adv = analyze_recording(rec("golf_3_swings", player={"level": "advanced"}), P)
    assert [r.score for r in plain.reps] == pytest.approx([r.score for r in adv.reps])


def test_shorter_player_is_expected_to_use_more_leg_drive():
    base = P["sports"]["basketball"]
    short = spec("basketball", "leg_drive", personalize(base, P["player"], {"height_cm": 155}))
    tall = spec("basketball", "leg_drive", personalize(base, P["player"], {"height_cm": 195}))
    ref = spec("basketball", "leg_drive", personalize(base, P["player"], {"height_cm": 175}))
    assert short["mean"] > ref["mean"] > tall["mean"]
    assert ref["mean"] == pytest.approx(spec("basketball", "leg_drive")["mean"])
    huge = spec("basketball", "leg_drive", personalize(base, P["player"], {"height_cm": 230}))
    assert huge["mean"] == pytest.approx(ref["mean"] - 4 * 0.03)        # clamped
    # metrics measured in torso lengths do not move with height
    assert spec("basketball", "release_height", personalize(base, P["player"], {"height_cm": 155}))["mean"] == \
        spec("basketball", "release_height")["mean"]


def test_drill_emphasis_reweights_the_score_and_leads_the_cues():
    base = P["sports"]["golf"]
    drilled = personalize(base, P["player"], None, "quiet_head")
    assert spec("golf", "head_sway", drilled)["weight"] == spec("golf", "head_sway")["weight"] * 3
    metrics = {"tempo_ratio": 0.3, "lead_arm_top": 120.0, "head_sway": 0.4, "head_lift": 0.065,
               "hip_sway": 0.039, "shoulder_turn": 0.5, "finish_balance": 0.1}
    _, plain_total, plain_cues = score_rep(metrics, "swing", base["metrics"], P["scoring"])
    _, drill_total, drill_cues = score_rep(metrics, "swing", drilled["metrics"], P["scoring"])
    # the worst metric overall is tempo, but in a quiet-head drill the head cue comes first
    assert plain_cues[0] == spec("golf", "tempo_ratio")["cue_low"]
    assert drill_cues[0] == spec("golf", "head_sway")["cue_high"]
    assert drill_total != pytest.approx(plain_total)


def test_drill_only_counts_its_strokes():
    fh = analyze_recording(rec("tennis_mixed", drill="forehands"), P)
    assert [r.type for r in fh.reps] == ["forehand"]
    assert fh.rejected.get("other_stroke") == 2
    serve = analyze_recording(rec("tennis_mixed", drill="serve"), P)
    assert [r.type for r in serve.reps] == ["serve"]
    rally = analyze_recording(rec("tennis_mixed", drill="rally"), P)
    assert [r.type for r in rally.reps] == ["forehand", "backhand", "serve"]


def test_unknown_drill_or_level_is_ignored():
    plain = analyze_recording(rec("golf_3_swings"), P)
    odd = analyze_recording(rec("golf_3_swings", drill="nope", player={"level": "nope"}), P)
    assert [r.score for r in plain.reps] == pytest.approx([r.score for r in odd.reps])


def test_level_widens_the_tolerance():
    s = spec("golf", "tempo_ratio")
    beginner = spec("golf", "tempo_ratio", personalize(P["sports"]["golf"], P["player"], {"level": "beginner"}))
    off = s["mean"] + s["tol"] + 1.5 * s["std"]
    assert metric_score(off, beginner, "swing", 2.0) > metric_score(off, s, "swing", 2.0)


def test_torso_length_from_height():
    assert torso_m(180, P["player"]) == pytest.approx(0.54)
    assert torso_m(None, P["player"]) is None
