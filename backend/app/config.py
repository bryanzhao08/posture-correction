import json
import os
import secrets
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA_DIR = Path(os.environ.get("FORMCOACH_DATA_DIR", ROOT / "backend" / "data"))
DATA_DIR.mkdir(parents=True, exist_ok=True)

DATABASE_URL = os.environ.get("FORMCOACH_DATABASE_URL", f"sqlite:///{DATA_DIR / 'formcoach.db'}")
PROFILES = json.loads((ROOT / "shared" / "sport_profiles.json").read_text())

TOKEN_DAYS = 30
CHECKPOINT_EVERY = 5

# Email goes through Resend's HTTP API (https://resend.com). Without a key, messages are written
# to OUTBOX_DIR so the whole flow can be exercised locally.
RESEND_API_KEY = os.environ.get("RESEND_API_KEY", "")
EMAIL_FROM = os.environ.get("FORMCOACH_EMAIL_FROM", "FormCoach <onboarding@resend.dev>")
OUTBOX_DIR = DATA_DIR / "outbox"

MAX_KEYPOINT_BYTES = 25 * 1024 * 1024


def jwt_secret() -> str:
    env = os.environ.get("FORMCOACH_JWT_SECRET")
    if env:
        return env
    path = DATA_DIR / "jwt_secret"
    if not path.exists():
        path.write_text(secrets.token_urlsafe(48))
        path.chmod(0o600)
    return path.read_text().strip()
