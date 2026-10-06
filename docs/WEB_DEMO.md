# FormCoach web demo

Live: **https://bryanzhao08.github.io/posture-correction/**

## What it is

The web demo is FormCoach running in a web browser, no app install needed. It uses your camera
and tracks your body pose **on your own device**: the video never leaves the phone or computer.
It runs the same counting and scoring engine as the iPhone app.

- Sessions are saved **only in that browser** on that device.
- There is no login and no emails. Accounts, uploads and progress emails are features of the iOS
  app and the backend (`backend/`).

## How deploys happen

You do not need to deploy by hand. Every push to `main` that changes anything in `web/` or
`shared/` (or the workflow file `.github/workflows/pages.yml`) rebuilds the site and publishes it
to the URL above, usually within a few minutes.

To watch progress, open the repository on GitHub and click the **Actions** tab, then the
"Deploy web demo to GitHub Pages" run. A green check means the new version is live. You can also
start a deploy manually from that page with **Run workflow**.

### One-time setting

GitHub must be told to publish from Actions. On GitHub go to **Settings → Pages → Build and
deployment → Source** and choose **GitHub Actions**. This may already be set; if so, there is
nothing to do.

## Run it on your computer

Needs Node.js 23 or newer and an internet connection the first time (it downloads the pose
model).

```bash
cd web
npm install
npm run dev
```

Open the URL it prints (for example `http://localhost:5173/posture-correction/`). The browser only
allows the camera on `https://` pages or on `localhost`, so use that address rather than your
computer's network IP.

## Test it on a phone

1. Open https://bryanzhao08.github.io/posture-correction/ in Safari (iPhone) or Chrome (Android).
2. Allow camera access when asked.
3. Optional: tap **Share → Add to Home Screen** so it opens like an app.

Put the phone on a tripod in front of you (face-on), portrait, with your whole body in frame,
the same as the iOS app.

## Alternative: host on Vercel

1. On vercel.com, **Add New → Project** and import this repository.
2. Set **Root Directory** to `web`.
3. Build command: `npm run build`. Output directory: `dist`.
4. Add an environment variable `BASE_PATH` with the value `/` (Vercel serves the site at the root
   of its domain, not under `/posture-correction/`).

## Checking the web engine matches Python

The web engine is a TypeScript port of the Python reference engine. To confirm they produce the
same reps, metrics and scores (from the repository root, with the Python environment from the
main README set up):

```bash
.venv/bin/python -m pytest ml/tests/test_parity.py -k web
```

## Limitations

- Browser pose tracking is slightly less accurate than Apple Vision in the iOS app.
- Older phones run it more slowly, which can make fast motions harder to catch.
- No holograms or replay clips yet.
- History does not sync between devices or browsers; clearing browser data deletes it.
