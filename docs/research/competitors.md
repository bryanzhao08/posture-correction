# FormCoach Competitor Analysis: Video AI, Wearables & Connected Sensors

This document provides a feature-by-feature teardown of primary and secondary competitors in computer-vision sports coaching, video analysis, smart sensors, and wearables across tennis, golf, and basketball. It evaluates current market offerings, hardware constraints, pricing models, and authentic user complaints scraped from Reddit and the Apple App Store, concluding with 10 defensible gaps FormCoach can own for a general audience.

---

## 1. SwingVision: Feature-by-Feature Teardown

[SwingVision](https://swing.vision) (developed by Mangolytics, Inc.) is the market leader in single-smartphone computer vision for tennis and pickleball. Originally launched as a tennis analytics app, it expanded to pickleball and padel, leveraging on-device Apple Neural Engine (ANE) processing.

### 1.1 Ball Tracking & Trajectory Estimation
* **Mechanism:** Single-camera monocular tracking running at 60 FPS or 120/240 FPS (depending on device and recording mode). Uses deep convolutional networks and CoreML to detect the ball in 2D image coordinates across consecutive frames, then fits physics-based projectile motion models to estimate 3D trajectory ([SwingVision Tech Overview](https://swing.vision/)).
* **Capabilities:** Plots ball trajectory over the net, 3D court landing position (depth and lateral placement), bounce locations, and shot arc height.
* **Limitations:** Dependent on continuous line of sight. When players obscure the ball at the moment of bounce, or when motion blur occurs under low indoor court lighting (<500 lux), tracking drops frames or hallucinates bounces.

### 1.2 Shot Speed Measurement
* **Measurement Point:** Measures initial exit velocity off the racket face (peak speed) and average speed across the net flight ([SwingVision Features](https://swing.vision/subscribe/compare)).
* **Accuracy:** Calibrated using court line homography (converting pixel distance to real-world meters using known court dimensions). Serve speeds are generally within ±3–5 mph of radar guns (Stalker/Pocket Radar) when mounted at recommended heights, but groundstroke speeds can fluctuate by ±6–10 mph if the camera is tilted or shaken by fence vibrations ([Functional Tennis Mount Review](https://www.functionaltennis.com/blogs/news/swing-vision-fence-mount-review)).

### 1.3 Line Calling & Challenges
* **Real-Time Audio Calls:** Uses on-device inference to determine whether a ball lands "In" or "Out". If configured, announces "Out" via the device speaker or paired AirPods/Apple Watch ([Apple App Store: SwingVision](https://apps.apple.com/us/app/swingvision-a-i-tennis-app/id989461317)).
* **Challenge Mechanism:** Players can challenge a close call by tapping their Apple Watch screen. The watch displays a top-down slow-motion graphic of the ball impact relative to the painted line (similar to Hawk-Eye).
* **Court Coverage Limits:** Full two-sided line calls are available on paid Pro/Max tiers only. In the Free tier or in "Ground Mode" (phone propped against a water bottle near the net), line calls are limited to the near court half or disabled entirely due to acute perspective distortion ([SwingVision Setup Guide](https://swing.vision/guides/set-up-your-recording)).

### 1.4 Auto-Highlights & Video Processing
* **Dead-Time Trimming:** Cuts out idle walking, ball bouncing, and between-point time. A standard 2-hour amateur match is automatically condensed down to 12–18 minutes of pure action ([SwingVision Video Highlights](https://swing.vision/subscribe/compare)).
* **Filtering & Tagging:** Automatically indexes video by shot type (forehand, backhand, serve, volley, overhead, smash), rally length (e.g., rallies > 8 shots), winners, and unforced errors. Users can export highlight reels directly to social media or MP4 files.

### 1.5 Match & Stroke Statistics
* **Metrics Tracked:** First/second serve percentage, serve speed distribution, forehand vs. backhand shot counts, shot depth (percentage landing past the service line vs. deep baseline zone), shot speed percentiles, and error breakdowns (net vs. long vs. wide).
* **Data Export:** Paid tiers allow CSV data export and shot coordinate heatmaps ([SwingVision Pricing](https://swing.vision/subscribe/compare)).

### 1.6 Pricing Tiers
SwingVision operates a multi-tiered subscription model ([SwingVision Subscriptions](https://swing.vision/subscribe/compare)):
* **Free Tier ($0/mo):**
  * Maximum 8 hours of HD recording per month.
  * Real-time audio line calls on the player's side of the net only.
  * Basic speed and depth tracking.
  * 5-minute maximum highlight video exports.
  * 7-day video cloud retention (videos deleted unless downloaded locally).
* **Pro Tier ($14.99/mo or $143.99/yr [$11.99/mo billed annually]):**
  * Up to 30 hours of video recording per month.
  * Full two-sided court line calling and unlimited challenge replays.
  * Unlimited video exports without SwingVision branding.
  * Technique review, stroke biomechanics categorization, and raw CSV data export.
  * Permanent cloud storage for match recordings.
  * Often bundled with a promotional "Swing Stick" phone mount with annual signup ([SwingVision Gift](https://swing.vision/gift)).
* **Max Tier (Scales up to team/family plans, ~$19.99/mo or $239.99/yr):**
  * Up to 60 hours per month.
  * 4K resolution processing and analysis.
  * Family Sharing support (up to 5 family members on one plan).
  * Advanced AI shot pattern recognition (e.g., inside-out forehand success rates).

### 1.7 Hardware, Device & Environmental Requirements
* **Supported Devices:** Requires iOS 18.0+ or iPadOS 18.0+ on Apple devices with A12 Bionic chip or newer (iPhone XS/XR and later; iPhone 12 Pro/13 Pro or newer strongly recommended for 60 FPS real-time processing) ([Apple App Store](https://apps.apple.com/us/app/swingvision-a-i-tennis-app/id989461317)). Android is not supported for real-time tracking.
* **Companion Hardware:** Apple Watch (Series 4 or newer, watchOS 10+) serves as a remote control, line call challenge screen, and scorekeeper.
* **Filming Setup & Placement:**
  * **Fence Mount (Standard):** Must be hooked onto the chain-link fence behind the baseline at a height of 6 to 10 feet (typically 6.5–7 ft) centered behind the court ([SwingVision Recording Guide](https://swing.vision/guides/set-up-your-recording)).
  * **Swing Stick / Telescopic Pole:** Used when fences are absent or wrapped with wind screens.
  * **Ground Mode:** Water bottle support at the net post (heavily restricted features).
  * **Lighting & Sun Angle:** Requires sunny or well-lit indoor courts (>400 lux). Direct sun glare pointing straight into the camera lens blinds the ball detector; high heat on outdoor courts causes thermal throttling.

---

## 2. Competitive Landscape: Video AI, Sensors & Wearables

### 2.1 OnForm ([onform.com](https://www.onform.com/))
* **Core Value Proposition:** Video analysis and coaching platform designed for coaches and athletes across golf, tennis, baseball, softball, track & field, and swimming ([OnForm Platform](https://www.onform.com/)).
* **Tech Stack:** High-speed 240 FPS video capture with manual shutter control, auto-capture triggered by motion/impact audio, 2D pose skeleton tracking overlaid on video, side-by-side split screen, telestration (drawing lines/angles), and integrated voiceover notes.
* **Hardware Setup:** Single tripod or multi-device wireless sync (up to 4 camera angles via Apple AirDrop/Wi-Fi).
* **Pricing:** Athlete/client viewing is free. Coach Basic is ~$29/mo; Coach Standard is $107.99/quarter (~$36/mo); Coach Pro is $161.99/quarter (~$54/mo) ([OnForm Pricing](https://onform.com/pricing/)).

### 2.2 Sportsbox AI ([sportsbox.ai](https://www.sportsbox.ai/))
* **Core Value Proposition:** Markerless 3D motion analysis for golf (Sportsbox 3D Golf) turning a single 2D smartphone video into an interactive 3D avatar with kinematic measurements ([Sportsbox 3D Golf](https://www.sportsbox.ai/)).
* **Tech Stack:** Deep learning 2D-to-3D lift network trained on laboratory 3D optical motion capture data. Allows users to rotate an avatar across 6 camera angles (Face-on, Down-the-line, Overhead, Below, Behind, Target).
* **Metrics:** Chest and pelvic turn/sway/lift/side-bend in degrees and inches, kinematic sequence curves, hand path, and shaft lean.
* **Pricing:** Free tier allows only 5 swing uploads/month. 3D Player Subscription is ~$110/yr (~$9.17–$15/mo). 3D Coach / Pro tier is $79.99/mo or $799.99/yr ([Old Duffer Golf Sportsbox Review](https://oldduffergolf.com/sportsbox-ai-review/)).

### 2.3 HomeCourt ([homecourt.ai](https://www.homecourt.ai/))
* **Core Value Proposition:** Single-smartphone AI basketball training app endorsed by the NBA, measuring shooting accuracy, dribbling drills, and agility ([HomeCourt](https://www.homecourt.ai/)).
* **Tech Stack:** Patented MobileVision platform running real-time CoreML on iOS. Identifies rim position, court lines, basketball location, and player 2D/3D skeletal keypoints.
* **Metrics:** Makes vs. misses, shot release time (seconds from catch to release), release angle, vertical jump height, court location shot chart, and dribbling cadence.
* **Pricing:** Free tier includes basic drills and shot counting. HomeCourt+ Individual is $7.99/mo or $69.99/yr; Teams plan is ~$1.50–$1.99/player/mo ([HomeCourt Pricing](https://www.homecourt.ai/membership)).

### 2.4 Zepp Tennis & Zepp Golf (Legacy Sensors)
* **Hardware:** 9-axis IMU (dual 3-axis accelerometers + 3-axis gyroscope) weighing ~7.7 grams, attached via rubber mount to racket butt cap or clipped onto a golf glove ([Zepp Sensors on Amazon](https://www.amazon.com/Zepp-Tennis-Swing-Analyzer-Retail/dp/B00KTYZ6M4)).
* **Metrics:** Racket/club head speed, ball spin rate (rpm estimate), backswing position, swing tempo ratio (backswing to downswing time), and impact position heatmap on racket face.
* **Post-Mortem & Demise:** Zepp was acquired by Huami / Zepp Health (Amazfit). Around 2020–2022, Zepp took down its tennis and golf cloud servers, pulled apps from iOS/Android app stores, and disabled user login authentication. Existing hardware was permanently bricked with no offline fallback ([Auratide Collective Post-Mortem 2026](https://www.auratidecollective.com/blogs/performance-lab/zepp-tennis-dead-what-still-works-2026), [Reddit r/tennis: Zepp is Dead](https://www.reddit.com/r/tennis/comments/16p1c9i/zepp_tennis_app_dead/)).

### 2.5 Babolat Play, Babolat POP & Wilson Connected Sensors
* **Babolat Play (Pure Drive Play / AeroPro Drive Play):** Racquets with micro-sensors, gyroscope, accelerometer, and Bluetooth embedded inside the racket handle ($399+ retail). Shut down permanently on December 31, 2021 ([Tennis Warehouse Forum: Babolat Play Shutdown](https://tt.tennis-warehouse.com/index.php?threads/babolat-play-app-discontinued.716182/)).
* **Babolat POP:** Wrist-worn neoprene strap holding a 9-axis PIQ sensor ($90 retail). Measured swing speed, PIQ score, and stroke count. App servers went offline in 2021; wrist placement suffered from chronic misclassification of slice vs. topspin and serve vs. overhead ([Tennis Warehouse: Babolat POP Discontinued](https://tt.tennis-warehouse.com/index.php?threads/babolat-pop-service-shutting-down.698514/)).
* **Wilson X Connected Basketball:** $200 smart basketball with internal Bluetooth accelerometer detecting makes/misses up to 7+ feet from the rim. Embedded non-replaceable battery rated for 100,000 shots. Wilson abandoned and removed the companion app from stores, turning the balls into inert $200 rubber basketballs ([The Verge: Wilson X Review](https://www.theverge.com/2015/10/28/9622982/wilson-x-connected-basketball-smart-sensor-hoops), [Reddit r/Basketball: Wilson X App Removed](https://www.reddit.com/r/Basketball/comments/1429v17/wilson_x_connected_basketball_app_gone/)).

### 2.6 Apple Watch Tennis & Golf Apps
* **Tennis Apps (SwingVision Apple Watch App, Tennis Keeper):** Uses Apple Watch CoreMotion accelerometer/gyroscope to detect swing impacts, count forehands/backhands, and track heart rate/active calories ([TennisKeeper on App Store](https://apps.apple.com/us/app/tenniskeeper-score-tracker/id1154564554)).
* **Golf Apps (Arccos Caddie, Golfshot, 18Birdies, SwingU):** Arccos pairs club butt-cap smart sensors ($199 bundle + $155.88–$199/yr subscription) with the Apple Watch to detect shots via acoustic microphone impact and motion ([Arccos Golf](https://www.arccosgolf.com/), [Reddit r/golf: Arccos Price Justification](https://www.reddit.com/r/golf/comments/1ty0lzo/i_cant_seem_to_justify_the_price_of_arccos/)). Standalone watch apps (Golfshot, 18Birdies) track GPS distances to the pin and rely on wrist acceleration to tag swing coordinates.

---

## 3. Comprehensive Competitor Comparison Table

| Product / Ecosystem | Retail Price & Tiers | Sports Supported | Filming & Hardware Setup | What It Measures | What Users Complain About (Scraped Reviews & Reddit Quotes) |
|---|---|---|---|---|---|
| **SwingVision** | Free (8 hrs/mo)<br>Pro: $14.99/mo or $143.99/yr<br>Max: ~$19.99/mo | Tennis, Pickleball, Padel | iPhone/iPad mounted 6–10 ft high on fence centered behind court, or telescopic Swing Stick. Apple Watch optional. | Ball speed, 3D bounce placement, in/out line calls, shot type (FH/BH/serve), rally count, auto-highlight trimming. | **Overheating in sun:** *"Phone shut down after 30 minutes in direct sunlight on a 90° day... had to rig a baby umbrella."* ([Reddit r/10s](https://www.reddit.com/r/10s/comments/13jkxgf/swingvision_phone_mount_on_a_very_sunny_day/))<br>**Bad line calls:** *"Great for highlights, but line calls on the far side are a total gamble. People get mad when you try to overrule human calls with it."* ([Reddit r/10s](https://www.reddit.com/r/10s/comments/1fm8eut/swingvision_line_calling_accuracy/))<br>**Paywall push:** *"Pushed full match exports and decent storage behind a pricey annual sub."* ([Reddit r/10s](https://www.reddit.com/r/10s/comments/17c1mda/swingvision_subscription_increase/)) |
| **OnForm** | Athlete: Free<br>Coach: $29/mo Basic, $107.99/qtr ($36/mo) Std, $161.99/qtr ($54/mo) Pro | Golf, Tennis, Baseball, Track, Swimming | iPhone/iPad on tripod (waist or chest height) or handheld by coach. Multi-cam WiFi sync. | 240 FPS slow-mo video, 2D AI skeleton overlay, manual angle drawings, voiceover feedback, launch monitor radar sync. | **No real-time audio:** *"It is purely a review tool after the fact. You cannot practice solo and get voice cues."* ([App Store Review](https://apps.apple.com/us/app/onform-video-analysis-app/id1490334045))<br>**Coach-centric cost:** *"Expensive if you just want to coach yourself; clearly priced for commercial golf academies."* ([Reddit r/golf](https://www.reddit.com/r/golf/comments/1b35x2r/video_analysis_apps_onform_vs_v1/)) |
| **Sportsbox AI** | Free (5 swings/mo)<br>Player: $110/yr (~$9.17/mo)<br>Coach: $79.99/mo or $799.99/yr | Golf | Smartphone on tripod 8 ft away, chest height, face-on or down-the-line orientation. Strictly square alignment. | Markerless 3D kinematics: pelvic/chest turn, sway, lift, side bend (degrees/inches), kinematic sequence curves. | **Data overload:** *"You get 40 different degree measurements and have no idea which one is actually ruining your ball strike."* ([Reddit r/golf](https://www.reddit.com/r/golf/comments/1g24oq3/anyone_still_using_sportsbox_ai/))<br>**Slow post-processing:** *"Takes 30 to 60 seconds to upload and render a single 3D swing; impossible to get into a practice rhythm."* ([App Store Review](https://apps.apple.com/us/app/sportsbox-3d-golf/id1534346048)) |
| **HomeCourt** | Free (basic drills)<br>HomeCourt+: $7.99/mo or $69.99/yr<br>Teams: ~$1.99/player/mo | Basketball | iPhone/iPad on tripod 5–6 ft high, placed near sideline/baseline with clear view of hoop and court key. | Shot makes/misses, shooting percentage by zone, release time, release angle, vertical jump, dribble cadence. | **Thermal throttle & battery:** *"Kills 50% battery in 30 minutes and turns phone into a hot brick on outdoor courts."* ([Reddit r/BasketballTips](https://www.reddit.com/r/BasketballTips/comments/17ctb0l/homecourt_app/))<br>**Missed makes/misses:** *"Misses swishes or counts a bounce off the backboard as a make if someone cuts in front of camera."* ([App Store Review](https://apps.apple.com/us/app/homecourt-the-basketball-app/id1258520424)) |
| **Zepp Tennis & Zepp Golf** | Discontinued ($149 original hardware retail) | Tennis, Golf | 7.7g IMU sensor clipped to racket butt cap or golf glove. Bluetooth connection to smartphone. | Swing speed, tempo ratio (backswing/downswing), racket face impact location, spin rate (rpm estimate). | **Bricked hardware e-waste:** *"Zepp turned my $150 sensor into a paperweight when they killed their servers. Can't even log in."* ([Auratide Collective](https://www.auratidecollective.com/blogs/performance-lab/zepp-tennis-dead-what-still-works-2026), [Reddit r/tennis](https://www.reddit.com/r/tennis/comments/16p1c9i/zepp_tennis_app_dead/))<br>**Sensor detachment:** *"Sensor flew off racket on a hard 110 mph serve into the back fence."* ([Tennis Warehouse](https://tt.tennis-warehouse.com/index.php?threads/zepp-sensor-falling-off.531234/)) |
| **Babolat Play & POP** | Discontinued ($399 racket, $90 POP band) | Tennis | Sensor embedded inside racket handle (Play) or 9-axis sensor on wrist strap (POP). | Stroke count (FH, BH, serve, smash), spin type (flat vs slice vs topspin), swing speed, "PIQ score". | **Total abandonment:** *"Racket still hits fine, but the smart handle I paid an extra $200 for has been dead since 2021."* ([Tennis Warehouse](https://tt.tennis-warehouse.com/index.php?threads/babolat-play-app-discontinued.716182/))<br>**Wrist sensor inaccuracies:** *"POP counted half my slice backhands as topspin and confused serves with overheads."* ([Tennis Warehouse](https://tt.tennis-warehouse.com/index.php?threads/babolat-pop-accuracy.556782/)) |
| **Wilson X Connected** | Discontinued ($199 ball retail) | Basketball | Sensor embedded inside regulation basketball bladder. | Makes vs misses from 7+ ft, shootaround shot charts, buzzer beater game. | **Unreplaceable battery + dead app:** *"Wilson deleted the app from the App Store. Ball is now an overpriced regular basketball. Battery can't even be replaced."* ([Reddit r/Basketball](https://www.reddit.com/r/Basketball/comments/1429v17/wilson_x_connected_basketball_app_gone/), [The Verge](https://www.theverge.com/2015/10/28/9622982/wilson-x-connected-basketball-smart-sensor-hoops))<br>**No close-range tracking:** *"Doesn't track layups or shots inside 7 feet."* ([Business Insider](https://www.businessinsider.com/wilson-x-smart-basketball-review-2015-11)) |
| **Apple Watch Golf/Tennis (Arccos, Golfshot, SwingVision)** | Hardware: $249–$799 watch.<br>Arccos: $199 sensors + $155.88–$199/yr sub. | Tennis, Golf | Apple Watch worn on dominant/lead wrist. Optional smart screws in club grips. | Swing detection via wrist IMU, acoustic impact audio, shot distance via GPS, tempo, heart rate. | **Wrist interference & accidental SOS:** *"My wrist bends on impact and constantly clicks the Digital Crown or triggers Emergency SOS."* ([Reddit r/golf](https://www.reddit.com/r/golf/comments/16z3vkm/apple_watch_accidental_crown_press_golf_swing/))<br>**Battery drain:** *"Watch is down 55% after 14 holes. Won't survive a full 18-hole round with GPS on."* ([Reddit r/AppleWatch](https://www.reddit.com/r/AppleWatch/comments/18m6v90/golf_apps_draining_battery/))<br>**Subscription fatigue:** *"Paying $200 a year for Arccos software when I already paid $200 for the hardware is insane."* ([Reddit r/golf](https://www.reddit.com/r/golf/comments/1ty0lzo/i_cant_seem_to_justify_the_price_of_arccos/)) |

---

## 4. Gaps FormCoach Can Own for a General Audience

Based on competitor blind spots (expensive hardware attachments, dead cloud servers, battery/thermal overheating, extreme setup friction, and high subscription fees), FormCoach has a unique opportunity to address everyday athletes who want immediate, practical coaching without friction.

Here are **10 concrete feature ideas**, ranked by **Impact vs. Effort**:

```mermaid
quadrantChart
    title Impact vs. Effort Prioritization Matrix
    x-axis Low Effort --> High Effort
    y-axis Low Impact --> High Impact
    quadrant-1 High Impact / High Effort (Strategic Bets)
    quadrant-2 High Impact / Low Effort (Quick Wins / Core Moats)
    quadrant-3 Low Impact / Low Effort (Nice-to-Haves)
    quadrant-4 Low Impact / High Effort (Avoid / Deprioritize)
    "1. Live Audio Whisper Coaching": [0.25, 0.95]
    "2. Ground/Bench Phone Setup": [0.30, 0.88]
    "3. Zero Hardware Lock-in": [0.15, 0.85]
    "4. Cross-Sport Progression": [0.35, 0.80]
    "5. Thermal-Safe Frame Throttling": [0.28, 0.75]
    "6. Instant Drill Rep Counter": [0.20, 0.70]
    "7. Explain-Like-I'm-12 Biomechanics": [0.40, 0.72]
    "8. Silent Auto-Clipped Highlight Export": [0.45, 0.68]
    "9. Offline-First Privacy Guarantee": [0.55, 0.82]
    "10. Web-First Zero-Install Practice": [0.65, 0.85]
```

### 1. Live Audio "Whisper" Coaching (Real-Time Earbud Feedback)
* **Impact:** High | **Effort:** Low
* **Description:** Competitors like Sportsbox and OnForm force users to stop, walk to their phone, and scrub through video. FormCoach delivers 1-sentence audio cues via Bluetooth earbuds immediately upon rep completion (e.g., *"Keep head still on impact"* or *"Extend follow-through higher"*).
* **Target Audience:** Solo recreational athletes practicing at the driving range, tennis backboard, or basketball court.

### 2. "Ground & Bench" Tolerant Camera Setup
* **Impact:** High | **Effort:** Low-Medium
* **Description:** SwingVision demands a 7-foot fence mount behind the court baseline; Sportsbox requires an exact 8-foot face-on tripod. FormCoach's pose engine normalizes camera height and perspective homography, allowing users to lean their phone against a water bottle, bag, or court bench.
* **Target Audience:** Casual players who don't own $100 telescopic mounting rigs.

### 3. Pure Software: Zero Hardware Lock-In / Immune to Bricking
* **Impact:** High | **Effort:** Low
* **Description:** Address the massive consumer distrust created by Zepp, Babolat, and Wilson bricking $150–$400 hardware. FormCoach runs on standard phone cameras or standard open wearables (Apple Watch / open BLE), guaranteeing lifetime functionality without proprietary sensor dongles.
* **Target Audience:** Burned former Zepp/Babolat/Arccos users.

### 4. Cross-Sport Athletic Engine (Golf, Tennis, Basketball, Pickleball)
* **Impact:** High | **Effort:** Medium
* **Description:** Competitors are siloed into single sports (SwingVision is tennis/pickleball only, Sportsbox/Arccos are golf only, HomeCourt is basketball only). FormCoach's unified 13-joint kinematic engine (`FormCore`) allows a multi-sport athlete to use one app for their morning golf range session and evening tennis match.
* **Target Audience:** Multi-sport recreational athletes and active families.

### 5. Thermal-Safe Dynamic Frame Throttling
* **Impact:** High | **Effort:** Low-Medium
* **Description:** Eliminate the #1 user complaint across SwingVision and HomeCourt (device shutdown from sun and processing heat). Instead of running full-resolution CV at 60 FPS continuously, FormCoach uses lightweight motion detection at 15 FPS while waiting, ramps up to 60 FPS during active reps, and skips video frames if device thermal state reaches `ProcessInfo.ThermalState.serious`.
* **Target Audience:** Outdoor players in hot climates (California, Florida, Texas, Mediterranean).

### 6. Instant "Drill Rep Counter" with Target Consistency Scoring
* **Impact:** Medium-High | **Effort:** Low
* **Description:** Rather than recording an entire match, focus on structured practice: *"Hit 10 crosscourt forehands with >75 form score"* or *"Shoot 15 free throws maintaining 60° release angle"*. Gives immediate haptic and audio confirmation when a rep meets pro target tolerances.
* **Target Audience:** High school players, self-taught adult beginners, and drill-focused trainers.

### 7. "Explain-Like-I'm-12" Actionable Cues over Metric Dumps
* **Impact:** High | **Effort:** Medium
* **Description:** Sportsbox AI overwhelms users with 40+ degree and inch measurements (pelvic sway, chest side-bend). FormCoach translates complex kinematics into plain English cues (e.g., *"You're dipping your left shoulder on backswing"* instead of *"Lead lateral flexion was -18°"*).
* **Target Audience:** Everyday amateurs without a PGA/USPTA certified instructor on retainer.

### 8. Silent Auto-Clipped Highlight & Flaw Reel
* **Impact:** Medium | **Effort:** Medium
* **Description:** Automatically extracts the user's best 3 reps and worst 3 reps of a session, overlaying ghost skeleton comparisons side-by-side. Ready for instant 10-second TikTok / Instagram Reels export with branded score badges.
* **Target Audience:** Social-media-engaged Gen Z and millennial players.

### 9. Privacy-First On-Device Edge Analysis (Zero Video Upload Requirement)
* **Impact:** High | **Effort:** Medium-High
* **Description:** Unlike cloud-reliant competitors, FormCore processes joint coordinates entirely on-device (`Foundation`/CoreML). Video frames never leave the phone unless the user explicitly backs them up. This complies with youth sports privacy guidelines (COPPA/GDPR) and works on public parks with zero cellular coverage.
* **Target Audience:** Parents of junior players, privacy-conscious adults, and players on poor cellular networks.

### 10. Web-First Zero-Install Browser Mode
* **Impact:** High | **Effort:** High
* **Description:** A browser-based version (`WEB_DEMO.md`) utilizing WebAssembly and WebGL pose estimation. A coach or friend can text a URL link to a player; the player opens Safari/Chrome, props the phone, and starts getting form feedback with zero App Store download friction.
* **Target Audience:** First-time trial users, coaches sharing quick drill links with students, and non-iOS users.
