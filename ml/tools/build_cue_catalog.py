"""Rebuild shared/cue_catalog.json from shared/sport_profiles.json.

Every cue text in every sport and camera view gets an entry with a stable key, its meaning, and
the wrong and correct movement the in-app hologram demos animate. Explanations for existing keys are
kept from the current catalog; new cues take theirs from NEW below. The app maps a displayed cue
string to its entry by exact text, so a metric whose cue text differs by view gets "@view" in its key.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROFILES = ROOT / "shared" / "sport_profiles.json"
CATALOG = ROOT / "shared" / "cue_catalog.json"

NEW = {
    "tennis.finish_height.low": ("The swing stops low instead of finishing up and over the opposite shoulder.",
        "Racket stops at chest height in front of the body.", "Racket wraps up and over the opposite shoulder, hitting elbow high."),
    "tennis.elbow_finish.low": ("At the finish the hitting elbow is below the face.",
        "Elbow finishes down by the chest.", "Elbow finishes up at nose height, pointing toward the target."),
    "tennis.off_hand_reach.low": ("The non-hitting hand stays tucked in during the turn, so the spacing to the ball is guessed.",
        "Free hand stays by the body as the racket goes back.", "Free hand reaches out toward the incoming ball during the turn, then releases before contact."),
    "tennis.spacing.low": ("The ball is too close to the body at contact.",
        "Elbow jammed into the side at contact.", "An arm's length of space between body and contact point."),
    "tennis.spacing.high": ("The player reaches for a ball that is too far away.",
        "Arm over-reaching, body leaning away from the ball.", "Feet move so contact happens at a comfortable arm's length."),
    "tennis.contact_front.low": ("Contact happens beside or behind the body instead of out in front.",
        "Ball hit level with the hips.", "Ball hit in front of the front foot."),
    "tennis.extension_through.low": ("The racket wraps around the body straight after contact.",
        "Hand pulls across the body immediately after contact.", "Hand extends out toward the target first, then wraps to the finish."),
    "tennis.back_load.high": ("Weight stays on the front foot during the take-back.",
        "Hips over the front foot as the racket goes back.", "Hips sit over the back foot, back knee bent, as the racket goes back."),
    "tennis.weight_shift.low": ("Weight stays back through contact.",
        "Hips stay over the back foot at contact.", "Hips move from the back foot onto the front foot through contact."),
    "tennis.contact_arm.low@side": ("On the backhand or serve the hitting arm is bent at contact.",
        "Contact with a bent elbow.", "Contact with the hitting arm fully extended."),
}


def main():
    profiles = json.loads(PROFILES.read_text())
    old = {c["key"]: c for c in json.loads(CATALOG.read_text())} if CATALOG.exists() else {}
    out, seen_text, key_text = [], set(), {}
    for sport, sp in profiles["sports"].items():
        lists = [(None, sp["metrics"])] + [(v, o["metrics"]) for v, o in (sp.get("views") or {}).items() if "metrics" in o]
        for view, metrics in lists:
            for m in metrics:
                for direction in ("low", "high"):
                    text = m.get("cue_" + direction)
                    if not text or text in seen_text:
                        continue
                    key = f"{sport}.{m['id']}.{direction}"
                    if key in key_text and key_text[key] != text:
                        key = f"{key}@{view}"
                    key_text.setdefault(key, text)
                    seen_text.add(text)
                    src = NEW.get(key) or (old[key]["meaning"], old[key]["wrong_motion"], old[key]["correct_motion"])
                    out.append({"key": key, "sport": sport, "metric": m["id"], "direction": direction, "view": view,
                                "text": text, "meaning": src[0], "wrong_motion": src[1], "correct_motion": src[2],
                                "hand": "shooting/hitting arm is the dominant side; golf lead arm is the non-dominant side"})
    CATALOG.write_text(json.dumps(out, indent=2) + "\n")
    print(f"{len(out)} cues -> {CATALOG}")


if __name__ == "__main__":
    main()
