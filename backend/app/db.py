from datetime import datetime, timezone

from sqlalchemy import JSON, Boolean, DateTime, Float, ForeignKey, Integer, String, UniqueConstraint, create_engine
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship, sessionmaker

from . import config

connect_args = {"check_same_thread": False} if config.DATABASE_URL.startswith("sqlite") else {}
engine = create_engine(config.DATABASE_URL, connect_args=connect_args)
SessionLocal = sessionmaker(engine, expire_on_commit=False)


def now() -> datetime:
    return datetime.now(timezone.utc)


def iso(dt: datetime) -> str:
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


class Base(DeclarativeBase):
    pass


class User(Base):
    __tablename__ = "users"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    email: Mapped[str] = mapped_column(String(320), unique=True, index=True)
    name: Mapped[str] = mapped_column(String(120))
    password_hash: Mapped[str] = mapped_column(String(100))
    handedness: Mapped[str] = mapped_column(String(5), default="right")
    email_reports: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)
    sessions = relationship("PracticeSession", cascade="all, delete-orphan", back_populates="user")
    checkpoints = relationship("Checkpoint", cascade="all, delete-orphan")


class PracticeSession(Base):
    __tablename__ = "sessions"
    __table_args__ = (UniqueConstraint("user_id", "client_id"),)
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    client_id: Mapped[str] = mapped_column(String(64))
    sport: Mapped[str] = mapped_column(String(20), index=True)
    handedness: Mapped[str] = mapped_column(String(5))
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    duration_s: Mapped[float] = mapped_column(Float)
    rep_count: Mapped[int] = mapped_column(Integer)
    score: Mapped[float | None] = mapped_column(Float, nullable=True)
    summary: Mapped[dict] = mapped_column(JSON)
    reps: Mapped[list] = mapped_column(JSON)
    app_version: Mapped[str] = mapped_column(String(20), default="")
    device: Mapped[str] = mapped_column(String(40), default="")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)
    user = relationship("User", back_populates="sessions")


class Checkpoint(Base):
    __tablename__ = "checkpoints"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    sport: Mapped[str] = mapped_column(String(20))
    number: Mapped[int] = mapped_column(Integer)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)
    data: Mapped[dict] = mapped_column(JSON)


Base.metadata.create_all(engine)


def get_db():
    with SessionLocal() as db:
        yield db
