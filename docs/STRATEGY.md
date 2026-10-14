# FormCoach strategy: standing out, stroke nuance, and different bodies

Written 2026-10-13 from our own measurements (ml/reports/) and Antigravity's market research
(docs/research/; its figures are as cited there and not all independently re-checked).

## 1. Standing out next to SwingVision

SwingVision is a **match-analytics** product: ball tracking, shot speed, line calls, match stats and
highlights, for tennis/pickleball on a court, with the phone on the fence. Pro is about $14.99/month
(docs/research/competitors.md). We should not try to out-track the ball. We win on **form for everyone**:

| What FormCoach owns | Why a general audience cares | Status |
|---|---|---|
| Works without a court or a ball (shadow swings in a backyard, garage, living room) | Most practice time is not match time | Done (all 4 sports) |
| The fix drawn on your own body (white = you, cyan = the fix), not a metric dump | "Elbow at nose height" is understood at a glance | Done (web + iOS) |
| Plain-language, 2–4 word spoken tips for when you're far from the phone | You're deep in the court, not reading a screen | Done |
| Four sports in one app, one price ($4.99/mo vs ~$15) | Families and multi-sport players | Done |
| Zero install: browser link, camera, done | Share a link to a friend or student | Done (password beta) |
| Video never leaves the phone | Parents, kids, privacy-minded users | Done |
| Drills with a rep counter and a consistency score | Clear homework from a coach | Done (drills by another session) |

**Next features with the best impact for effort** (from the research's ranked gaps, filtered by what we
can ship): coach share link (send a session summary + fix cards to a coach), weekly progress email
(the checkpoint emails already exist in the backend), auto "flaw reel" of the reps that needed work
(replay clips exist on iOS), streaks/goals, and an Apple Watch companion (below).

## 2. Stroke nuance (forehand vs backhand vs serve, slice vs topspin)

Measured on THETIS with players held out (ml/reports/strokes.md):

| Question | Accuracy | Ship it? |
|---|---|---|
| Stroke family (forehand / one-handed backhand / two-handed backhand / volley / serve / smash) | 77% overall; forehand 89%, two-handed backhand 100%, serve 89% | Yes, with confidence shown |
| Slice vs flat/topspin on groundstrokes | 93% | Yes |
| Serve type (flat / kick / slice) | 45% | No, not reliable from one 2D camera |
| Volleys | 30% as a class, and only 12% of forehand volleys get counted at all | Not from the front camera |

Why volleys fail: filmed from the front, a volley is a short punch **toward the camera**, which a flat
image barely sees. Fix: recommend the **side view** for volleys and collect side-view volley clips to
validate (THETIS is front-only). Serve type needs racket-face or ball-spin information, which is the
case for a wearable or a higher-frame-rate side camera.

What would raise accuracy most: (a) phone-camera clips from side and back views with stroke labels
(our own beta users, with consent, are the best source); (b) per-player calibration (below);
(c) an optional wrist/racket motion sensor for serve type and spin.

## 3. Different bodies (tall, short, heavier, lighter)

What already adapts:
- Every distance is measured in the player's **own torso lengths**, so a 6'4" and a 5'2" player are
  judged on the same scale without asking their height.
- **Level** (beginner → pro) widens or tightens tolerances; **height** shifts the few metrics where coaches
  expect a difference (e.g. leg drive on a jump shot); **drills** reweight what is being practised
  (ml/formcoach/personalize.py, ported to iOS and web).

What to add, in order:
1. **Measure the body, not just the height.** Arm and leg length relative to the torso vary a lot between
   people of the same height. Reach metrics (spacing, contact out front, release height) should be judged
   in arm lengths, measured during the 1-second "hold still" setup check that already exists. A study of
   whether our current scores are biased by proportions is in progress (ml/reports/body_types.md).
2. **Personal baseline after a few sessions.** After ~5 sessions, show "your normal" bands next to the pro
   reference and coach the change from *your* baseline. This absorbs build and mobility differences
   without guessing them.
3. **Mobility-aware targets** (optional): a one-time shoulder-turn and knee-bend range test, so a stiff
   or heavier player isn't told to turn further than they can.
4. Never infer weight or body type from the camera. Let people opt in to say "limited mobility" instead.

## 4. Wearables and finding the player relative to the phone

From docs/research/wearables.md:
- **Browser:** iPhone Safari has no Web Bluetooth, so a wristband can't connect to the web demo on iPhones.
  The camera is the only sensor there; Chrome on Android/desktop could add an optional sensor later.
- **iOS app, recommended:** an **Apple Watch companion** streaming wrist motion. No hardware to sell; it adds
  precise impact timing, swing tempo and wrist rotation (helps serve type and spin).
- **Later, power users:** a small BLE motion tag on the racket butt cap or club grip (nRF52 + IMU class
  hardware, roughly $10–15 parts).
- **Position relative to the phone:** BLE signal strength is too noisy for court positioning; UWB (iPhone
  NearbyInteraction) works but needs a UWB tag. The camera already knows where you are in the frame and,
  with your height entered, roughly how far away you are, which covers the setup guidance we need.

## 5. Beta and money

- Web beta behind a password (changeable: `cd web && npm run set-password -- "new password"`, push).
- Free trial clock (3 months, `web/src/config.ts`), Plans page ($4.99 / $39.99 / $99.99), sign-up list
  emailed to the owner through the relay (relay/, docs/SIGNUP_RELAY.md).
- Payments: hosted checkout (Stripe Payment Links) on the web; Apple In-App Purchase inside the iOS app.
  We never collect or email card numbers (docs/PAYMENTS.md).
