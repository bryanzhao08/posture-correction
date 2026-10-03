# Pickleball Data Collection Protocol

Since no public pickleball stroke or pose dataset currently exists, this protocol outlines how to collect and label a validation set to tune and verify the FormCoach pickleball engine.

## 1. What to Record

**Players & Demographics**
* Recruit at least 10–15 players.
* Ensure a balanced skill mix: roughly half beginners and half experts (e.g., 4.0+ DUPR rating).

**Target Strokes**
For each player, capture roughly 15–20 reps of each of the following strokes on both the **forehand** and **backhand** wings:
* Dink
* Drive
* Volley
* Overhead
* Serve

**"Should Not Count" Footage (Negative Examples)**
To tune out false positives, record several minutes per player of:
* Standing idle or resting.
* Walking around the court.
* Bending to pick up balls.
* Bouncing the ball with the paddle or hand.
* Fidgeting: twirling the paddle, stretching, waving, adjusting clothing.

Note that full shadow swings are real strokes and the engine counts them by design (the tennis
validation set is shadow swings), so do not record them as negatives.

## 2. How to Record

To ensure the data exactly matches what the iOS app sees in production, adhere to these constraints:
* **Camera Placement:** Phone mounted on a tripod, chest height, approximately 3 to 5 meters away from the player.
* **Framing:** Face-on to the player, **portrait** orientation. The player's full body (head to toes) must remain in the frame.
* **Isolation:** Only one player should be visible in the frame at a time.
* **Settings:** Use 60 fps if available, with even lighting (avoid heavy backlighting from the sun).

## 3. Labeling and Extraction

**Cheap Labeling via CSV**
Log the captured clips into a simple CSV file with one row per stroke event. The required columns are:
`clip_file, start_time, contact_time, stroke_type, hand, player_id, skill_level`

**App Pose Upload (Alternative to Video)**
If you are collecting data using the FormCoach app in a beta capacity, you can skip storing heavy video files entirely by enabling the app's opt-in pose upload. The app will `POST /sessions/{id}/keypoints` directly to the backend containing the mathematical 13-joint coordinates for every frame. The CSV label `clip_file` can simply reference the saved `.json.gz` recording ID.

## 4. How the Data Will Be Used

The collected dataset will be fed into the `ml/fit_reference.py` and `ml/validate.py` pipelines. 

**Data Splitting**
* The data will be divided into a **Train** split (used to fit reference ranges) and a **Verification** split (used to test accuracy).
* This split must be strictly **player-level**: a `player_id` present in the training set cannot appear in the verification set.

**Target Metrics**
Mirroring our other sports, the test suite will report:
* **Count Accuracy:** The percentage of reps counted exactly once, missed, or double-counted.
* **Rejection Accuracy:** False counts per minute of idle / "should not count" footage.
* **Type Accuracy:** Percentage of correctly classified stroke types. The engine currently
  classifies forehand, backhand and overhead; the dink/drive/volley labels let us measure each
  stroke family's counting accuracy separately and decide whether finer classes are feasible.
* **Skill Separation:** AUC metric comparing the form scores of the held-out experts against the beginners (1.00 = perfect separation).

## 5. Consent and Privacy

* **Explicit Consent:** Obtain explicit, documented consent from all players before recording.
* **Transparency:** Clearly explain that this data is being collected solely to train a motion-tracking algorithm. If using the beta app, clarify whether raw video is being saved or only skeletal keypoints. Uploaded keypoints are
  linked to the player's account (not anonymous) and are deleted with the account.
* **Data Security:** Store raw video securely, limit access to the core ML engineers, and do not share or publish the footage externally.
