import json
import uuid

import pytest
from fastapi.testclient import TestClient

from app import config
from app.main import app
from formcoach.engine import analyze_recording, load_profiles
from formcoach.scoring import summarize
from formcoach.synth import recording

client = TestClient(app)
PROFILES = load_profiles()


def golf_payload(swings=3, started="2026-10-01T10:00:00Z", seed=1):
    script = [("rest", 1.5)]
    for _ in range(swings):
        script += [("golf_swing",), ("rest", 1.5)]
    eng = analyze_recording(recording("golf", script, seed=seed), PROFILES)
    reps = [r.to_dict() for r in eng.reps]
    summary = summarize("golf", reps, eng.rejected, PROFILES["sports"]["golf"]["metrics"],
                        PROFILES["scoring"], eng.active_s, eng.passive_s)
    return {"client_id": str(uuid.uuid4()), "sport": "golf", "handedness": "right", "started_at": started,
            "duration_s": 60.0, "summary": summary, "reps": reps, "app_version": "1.0", "device": "test"}


def signup(email=None, password="correct horse 1"):
    email = email or f"{uuid.uuid4().hex[:10]}@example.com"
    r = client.post("/auth/register", json={"email": email, "password": password, "name": "Sam"})
    assert r.status_code == 201, r.text
    return email, {"Authorization": f"Bearer {r.json()['access_token']}"}


def outbox():
    return sorted(config.OUTBOX_DIR.glob("*.json")) if config.OUTBOX_DIR.exists() else []


def test_register_login_and_me():
    email, h = signup()
    assert client.get("/me", headers=h).json()["email"] == email
    assert client.post("/auth/register", json={"email": email.upper(), "password": "another pass 1",
                                               "name": "X"}).status_code == 409
    assert client.post("/auth/login", json={"email": email, "password": "wrong password"}).status_code == 401
    ok = client.post("/auth/login", json={"email": email.upper(), "password": "correct horse 1"})
    assert ok.status_code == 200 and ok.json()["user"]["email"] == email
    assert client.post("/auth/register", json={"email": "a@example.com", "password": "short",
                                               "name": "X"}).status_code == 422


def test_auth_is_required_and_tokens_are_checked():
    assert client.get("/me").status_code == 401
    assert client.get("/sessions", headers={"Authorization": "Bearer nonsense"}).status_code == 401
    assert client.post("/sessions", json=golf_payload()).status_code == 401


def test_repeated_failed_logins_are_locked_out():
    email, _ = signup()
    codes = [client.post("/auth/login", json={"email": email, "password": "nope nope"}).status_code
             for _ in range(10)]
    assert codes[0] == 401 and codes[-1] == 429


def test_session_is_saved_scored_and_emailed():
    email, h = signup()
    before = len(outbox())
    body = golf_payload()
    r = client.post("/sessions", json=body, headers=h)
    assert r.status_code == 201, r.text
    out = r.json()
    assert out["rep_count"] == 3 and 0 < out["score"] <= 100
    assert out["comparison"]["previous_sessions"] == 0 and out["comparison"]["score_delta"] is None
    assert {m["id"] for m in out["comparison"]["metrics"]} >= {"tempo_ratio", "head_sway"}
    assert out["checkpoint"] is None
    mails = outbox()[before:]
    assert len(mails) == 1 and json.loads(mails[0].read_text())["to"] == email

    again = client.post("/sessions", json=body, headers=h)
    assert again.status_code == 200 and again.json()["id"] == out["id"]
    assert len(client.get("/sessions", headers=h).json()) == 1
    assert len(outbox()) == before + 1

    full = client.get(f"/sessions/{out['id']}", headers=h).json()
    assert len(full["reps"]) == 3 and full["summary"]["rep_count"] == 3


def test_fifth_session_creates_checkpoint_and_second_block_compares_to_first():
    _, h = signup()
    before = len(outbox())
    outs = [client.post("/sessions", json=golf_payload(started=f"2026-10-{d:02d}T10:00:00Z", seed=d),
                        headers=h).json() for d in range(1, 11)]
    assert [bool(o["checkpoint"]) for o in outs] == [False] * 4 + [True] + [False] * 4 + [True]
    first, second = outs[4]["checkpoint"], outs[9]["checkpoint"]
    assert first["number"] == 1 and first["sessions"] == 5 and first["total_reps"] == 15
    assert first["previous_avg_score"] is None and first["metrics"][0]["previous"] is None
    assert second["number"] == 2 and second["previous_avg_score"] == pytest.approx(first["avg_score"])
    assert second["metrics"][0]["direction"] in ("better", "worse", "same")
    assert outs[1]["comparison"]["previous_sessions"] == 1
    assert outs[1]["comparison"]["score_delta"] == pytest.approx(outs[1]["score"] - outs[0]["score"])
    assert len(outbox()) - before == 12          # 10 session emails + 2 checkpoint emails
    assert [c["number"] for c in client.get("/checkpoints?sport=golf", headers=h).json()] == [2, 1]

    st = client.get("/stats/golf", headers=h).json()
    assert st["sessions"] == 10 and st["total_reps"] == 30 and len(st["trend"]) == 10
    assert st["recent_avg_score"] == pytest.approx(second["avg_score"])
    assert client.get("/stats/tennis", headers=h).json()["sessions"] == 0


def test_email_opt_out_is_respected():
    _, h = signup()
    assert client.patch("/me", json={"email_reports": False, "handedness": "left"}, headers=h).json() == {
        **client.get("/me", headers=h).json(), "email_reports": False, "handedness": "left"}
    before = len(outbox())
    assert client.post("/sessions", json=golf_payload(), headers=h).status_code == 201
    assert len(outbox()) == before


def test_users_cannot_see_each_others_sessions():
    _, a = signup()
    _, b = signup()
    sid = client.post("/sessions", json=golf_payload(), headers=a).json()["id"]
    assert client.get(f"/sessions/{sid}", headers=b).status_code == 404
    assert client.post(f"/sessions/{sid}/keypoints", json={"frames": []}, headers=b).status_code == 404
    assert client.get("/sessions", headers=b).json() == []


def test_keypoints_upload_and_account_deletion():
    email, h = signup()
    sid = client.post("/sessions", json=golf_payload(), headers=h).json()["id"]
    rec = recording("golf", [("rest", 0.5)])
    assert client.post(f"/sessions/{sid}/keypoints", json=rec, headers=h).status_code == 204
    assert client.post(f"/sessions/{sid}/keypoints", json={"nope": 1}, headers=h).status_code == 422
    uid = client.get("/me", headers=h).json()["id"]
    assert (config.DATA_DIR / "keypoints" / str(uid) / f"{sid}.json.gz").exists()

    assert client.delete("/me", headers=h).status_code == 204
    assert client.get("/me", headers=h).status_code == 401
    assert not (config.DATA_DIR / "keypoints" / str(uid)).exists()
    assert client.post("/auth/login", json={"email": email, "password": "correct horse 1"}).status_code == 401


def test_bad_session_payloads_are_rejected():
    _, h = signup()
    bad = golf_payload()
    bad["sport"] = "curling"
    assert client.post("/sessions", json=bad, headers=h).status_code == 422
    bad = golf_payload()
    bad["summary"]["score"] = "high"
    assert client.post("/sessions", json=bad, headers=h).status_code == 422
