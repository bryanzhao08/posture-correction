"""Outbound email via the Resend HTTP API, with a local outbox when no API key is configured."""
import json
import logging
import time

import httpx

from . import config

log = logging.getLogger("formcoach.email")


def send(to: str, subject: str, html: str, text: str) -> None:
    if not config.RESEND_API_KEY:
        config.OUTBOX_DIR.mkdir(parents=True, exist_ok=True)
        stem = config.OUTBOX_DIR / f"{time.time_ns()}"
        stem.with_suffix(".json").write_text(json.dumps({"to": to, "subject": subject, "text": text}, indent=2))
        stem.with_suffix(".html").write_text(html)
        log.info("RESEND_API_KEY not set; wrote email for %s to %s", to, stem)
        return
    try:
        r = httpx.post(
            "https://api.resend.com/emails",
            headers={"Authorization": f"Bearer {config.RESEND_API_KEY}"},
            json={"from": config.EMAIL_FROM, "to": [to], "subject": subject, "html": html, "text": text},
            timeout=15,
        )
        r.raise_for_status()
    except httpx.HTTPError as e:
        # runs in a background task after the session is already saved; a mail failure must not lose data
        log.error("email to %s failed: %s", to, e)
