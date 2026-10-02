import base64
import hashlib
import time
from datetime import timedelta

import bcrypt
import jwt
from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from . import config
from .db import User, get_db, now

bearer = HTTPBearer(auto_error=False)


def _prehash(password: str) -> bytes:
    # bcrypt only reads the first 72 bytes; hashing first keeps long passphrases fully significant
    return base64.b64encode(hashlib.sha256(password.encode()).digest())


def hash_password(password: str) -> str:
    return bcrypt.hashpw(_prehash(password), bcrypt.gensalt()).decode()


_DUMMY_HASH = hash_password("formcoach-dummy-password")


def verify_password(password: str, hashed: str | None) -> bool:
    # always run bcrypt, even for unknown emails, so response time does not reveal which emails exist
    ok = bcrypt.checkpw(_prehash(password), (hashed or _DUMMY_HASH).encode())
    return ok and hashed is not None


def make_token(user_id: int) -> str:
    payload = {"sub": str(user_id), "exp": now() + timedelta(days=config.TOKEN_DAYS)}
    return jwt.encode(payload, config.jwt_secret(), algorithm="HS256")


def current_user(creds: HTTPAuthorizationCredentials | None = Depends(bearer),
                 db: Session = Depends(get_db)) -> User:
    if creds is None:
        raise HTTPException(401, "Not authenticated")
    try:
        payload = jwt.decode(creds.credentials, config.jwt_secret(), algorithms=["HS256"])
        user = db.get(User, int(payload["sub"]))
    except (jwt.PyJWTError, KeyError, ValueError):
        raise HTTPException(401, "Invalid or expired token")
    if user is None:
        raise HTTPException(401, "Invalid or expired token")
    return user


class LoginLimiter:
    """Blocks password guessing: max_fails failures per key within the window."""

    def __init__(self, max_fails: int = 8, window_s: int = 300):
        self.max_fails, self.window_s = max_fails, window_s
        self.fails: dict[str, list[float]] = {}

    def check(self, key: str):
        recent = [t for t in self.fails.get(key, []) if time.time() - t < self.window_s]
        self.fails[key] = recent
        if len(recent) >= self.max_fails:
            raise HTTPException(429, "Too many failed attempts. Try again in a few minutes.")

    def fail(self, key: str):
        self.fails.setdefault(key, []).append(time.time())

    def reset(self, key: str):
        self.fails.pop(key, None)


login_limiter = LoginLimiter()
