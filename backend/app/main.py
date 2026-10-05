import gzip
import json
from datetime import datetime
from typing import Literal

from fastapi import BackgroundTasks, Depends, FastAPI, HTTPException, Request, Response
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from . import config, email_templates, emailer, stats
from .auth import current_user, hash_password, login_limiter, make_token, verify_password
from .db import Checkpoint, PracticeSession, User, get_db, iso

app = FastAPI(title="FormCoach API", version="1.0")

Sport = Literal["golf", "basketball", "tennis", "pickleball"]
Hand = Literal["right", "left"]


class RegisterIn(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=256)
    name: str = Field(min_length=1, max_length=120)


class LoginIn(BaseModel):
    email: EmailStr
    password: str = Field(max_length=256)


class MePatch(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=120)
    handedness: Hand | None = None
    email_reports: bool | None = None


class SessionIn(BaseModel):
    client_id: str = Field(min_length=8, max_length=64)
    sport: Sport
    handedness: Hand
    started_at: datetime
    duration_s: float = Field(ge=0, le=6 * 3600)
    summary: dict
    reps: list[dict] = Field(max_length=5000)
    app_version: str = Field(default="", max_length=20)
    device: str = Field(default="", max_length=40)
    view: Literal["front", "side", "back"] | None = None
    focus: str | None = Field(default=None, max_length=30)


def user_out(u: User) -> dict:
    return {"id": u.id, "email": u.email, "name": u.name, "handedness": u.handedness,
            "email_reports": u.email_reports}


def auth_out(u: User) -> dict:
    return {"access_token": make_token(u.id), "token_type": "bearer", "user": user_out(u)}


def list_item(s: PracticeSession) -> dict:
    return {"id": s.id, "client_id": s.client_id, "sport": s.sport, "started_at": iso(s.started_at),
            "duration_s": s.duration_s, "rep_count": s.rep_count, "score": s.score}


def session_out(db: Session, s: PracticeSession, checkpoint: Checkpoint | None = None) -> dict:
    return {**list_item(s), "handedness": s.handedness, "summary": s.summary, "reps": s.reps,
            "comparison": stats.comparison(db, s),
            "checkpoint": stats.checkpoint_out(checkpoint) if checkpoint else None}


def owned_session(db: Session, user: User, session_id: int) -> PracticeSession:
    s = db.get(PracticeSession, session_id)
    if s is None or s.user_id != user.id:
        raise HTTPException(404, "Session not found")
    return s


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/profiles")
def profiles():
    return config.PROFILES


@app.post("/auth/register", status_code=201)
def register(body: RegisterIn, db: Session = Depends(get_db)):
    email = body.email.lower()
    if db.scalar(select(User).where(User.email == email)):
        raise HTTPException(409, "An account with this email already exists")
    user = User(email=email, name=body.name.strip(), password_hash=hash_password(body.password))
    db.add(user)
    db.commit()
    return auth_out(user)


@app.post("/auth/login")
def login(body: LoginIn, request: Request, db: Session = Depends(get_db)):
    email = body.email.lower()
    key = f"{email}|{request.client.host if request.client else ''}"
    login_limiter.check(key)
    user = db.scalar(select(User).where(User.email == email))
    if not verify_password(body.password, user.password_hash if user else None):
        login_limiter.fail(key)
        raise HTTPException(401, "Incorrect email or password")
    login_limiter.reset(key)
    return auth_out(user)


@app.get("/me")
def me(user: User = Depends(current_user)):
    return user_out(user)


@app.patch("/me")
def patch_me(body: MePatch, user: User = Depends(current_user), db: Session = Depends(get_db)):
    user = db.merge(user)
    for field, value in body.model_dump(exclude_none=True).items():
        setattr(user, field, value)
    db.commit()
    return user_out(user)


@app.delete("/me", status_code=204)
def delete_me(user: User = Depends(current_user), db: Session = Depends(get_db)):
    kp_dir = config.DATA_DIR / "keypoints" / str(user.id)
    if kp_dir.exists():
        for f in kp_dir.iterdir():
            f.unlink()
        kp_dir.rmdir()
    db.delete(db.merge(user))
    db.commit()
    return Response(status_code=204)


def send_reports(user_id: int, session_id: int, checkpoint_id: int | None):
    from .db import SessionLocal
    with SessionLocal() as db:
        user, s = db.get(User, user_id), db.get(PracticeSession, session_id)
        if user is None or s is None or not user.email_reports:
            return
        label = config.PROFILES["sports"][s.sport]["label"]
        session = {**list_item(s), "top_cues": s.summary.get("top_cues") or []}
        emailer.send(user.email, *email_templates.session_email(user.name, label, session, stats.comparison(db, s)))
        if checkpoint_id is not None:
            cp = stats.checkpoint_out(db.get(Checkpoint, checkpoint_id))
            emailer.send(user.email, *email_templates.checkpoint_email(user.name, label, cp))


@app.post("/sessions", status_code=201)
def create_session(body: SessionIn, response: Response, background: BackgroundTasks,
                   user: User = Depends(current_user), db: Session = Depends(get_db)):
    existing = db.scalar(select(PracticeSession).where(PracticeSession.user_id == user.id,
                                                       PracticeSession.client_id == body.client_id))
    if existing:
        response.status_code = 200
        return session_out(db, existing)
    score = body.summary.get("score")
    if score is not None and not isinstance(score, (int, float)):
        raise HTTPException(422, "summary.score must be a number or null")
    s = PracticeSession(
        user_id=user.id, client_id=body.client_id, sport=body.sport, handedness=body.handedness,
        started_at=body.started_at, duration_s=body.duration_s, rep_count=len(body.reps), score=score,
        summary={**body.summary, "view": body.view, "focus": body.focus} if body.view else body.summary,
        reps=body.reps, app_version=body.app_version, device=body.device)
    db.add(s)
    db.commit()
    cp = stats.maybe_checkpoint(db, s)
    if s.rep_count > 0:
        background.add_task(send_reports, user.id, s.id, cp.id if cp else None)
    return session_out(db, s, cp)


@app.get("/sessions")
def list_sessions(sport: Sport | None = None, limit: int = 50,
                  user: User = Depends(current_user), db: Session = Depends(get_db)):
    q = select(PracticeSession).where(PracticeSession.user_id == user.id)
    if sport:
        q = q.where(PracticeSession.sport == sport)
    q = q.order_by(PracticeSession.started_at.desc(), PracticeSession.id.desc()).limit(max(1, min(limit, 200)))
    return [list_item(s) for s in db.scalars(q)]


@app.get("/sessions/{session_id}")
def get_session(session_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return session_out(db, owned_session(db, user, session_id))


@app.post("/sessions/{session_id}/keypoints", status_code=204)
async def upload_keypoints(session_id: int, request: Request, user: User = Depends(current_user),
                           db: Session = Depends(get_db)):
    s = owned_session(db, user, session_id)
    raw = bytearray()
    async for chunk in request.stream():
        raw.extend(chunk)
        if len(raw) > config.MAX_KEYPOINT_BYTES:
            raise HTTPException(413, "Recording too large")
    try:
        rec = json.loads(raw)
        frames = rec["frames"]
        assert isinstance(frames, list)
    except (ValueError, KeyError, TypeError, AssertionError):
        raise HTTPException(422, "Body must be a Recording with a frames list")
    out = config.DATA_DIR / "keypoints" / str(user.id)
    out.mkdir(parents=True, exist_ok=True)
    with gzip.open(out / f"{s.id}.json.gz", "wt") as f:
        json.dump(rec, f)
    return Response(status_code=204)


@app.get("/stats/{sport}")
def get_stats(sport: Sport, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return stats.stats(db, user.id, sport)


@app.get("/checkpoints")
def list_checkpoints(sport: Sport | None = None, user: User = Depends(current_user),
                     db: Session = Depends(get_db)):
    q = select(Checkpoint).where(Checkpoint.user_id == user.id)
    if sport:
        q = q.where(Checkpoint.sport == sport)
    return [stats.checkpoint_out(c) for c in db.scalars(q.order_by(Checkpoint.id.desc()))]
