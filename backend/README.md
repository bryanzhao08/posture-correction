# FormCoach Backend

The FormCoach backend is a FastAPI application that provides an API for the iOS app. It uses SQLite via SQLAlchemy, JWT for authentication, and Resend for emails.

## Running Locally

1. **Create and activate a virtual environment:**
   ```bash
   cd /path/to/FormCoach
   python3 -m venv .venv
   source .venv/bin/activate
   ```

2. **Install dependencies:**
   ```bash
   pip install -r backend/requirements.txt
   pip install -r backend/requirements-dev.txt
   ```

3. **Start the server:**
   Navigate into the `backend` directory and run:
   ```bash
   cd backend
   uvicorn app.main:app --reload
   ```
   The API will be available at `http://127.0.0.1:8000`.

## Running Tests

From the repository root (with the virtual environment activated), run:
```bash
python -m pytest backend/tests -q
```

## Environment Variables

You can configure the backend by setting these environment variables (see `.env.example`):
- `FORMCOACH_DATA_DIR`: Directory for the SQLite database, generated JWT secrets, and outbox emails (default: `backend/data`).
- `FORMCOACH_DATABASE_URL`: SQLAlchemy connection string (default: SQLite in `FORMCOACH_DATA_DIR`).
- `FORMCOACH_JWT_SECRET`: Secret key for JWTs. If unset, a secure random key is generated and saved to `jwt_secret` in the data directory.
- `RESEND_API_KEY`: API key for email delivery.
- `FORMCOACH_EMAIL_FROM`: Sender address for emails.

## Emails & Resend API

FormCoach uses the [Resend HTTP API](https://resend.com) for sending session reports and checkpoints.

To send real emails:
1. Create a free account at Resend.
2. Verify your sending domain in the Resend dashboard.
3. Obtain an API key and set `RESEND_API_KEY`.

**Local Outbox:** If `RESEND_API_KEY` is not set, the backend will not attempt to send real emails. Instead, it will write the JSON payloads and HTML bodies directly to `backend/data/outbox/` for local inspection.

## Docker

The production image runs a non-root user and serves Uvicorn on port 8000. 

Because the backend relies on `shared/sport_profiles.json` relative to the repository root, **the Docker build context must be the repository root**, not the `backend/` directory:

```bash
# Build from the repository root:
docker build -t formcoach-backend -f backend/Dockerfile .

# Run the image, mounting a local directory for data persistence:
docker run -d -p 8000:8000 \
  -v $(pwd)/data:/app/data \
  --name formcoach formcoach-backend
```

## Before Real Users Checklist

Before exposing this backend to real users, ensure you have:
- [ ] **HTTPS:** Placed a reverse proxy (like Nginx or Caddy) in front of the container to provide HTTPS.
- [ ] **JWT Secret:** Set a strong, fixed `FORMCOACH_JWT_SECRET` in your environment (if it regenerates, all users will be logged out).
- [ ] **Postgres:** Switched `FORMCOACH_DATABASE_URL` from SQLite to a robust Postgres instance.
- [ ] **Backups:** Configured regular backups of the database volume.
- [ ] **Rate Limiting Note:** Be aware that the in-memory login limiter is per-process. If you scale to multiple Uvicorn workers, rate limits will apply independently to each worker.
