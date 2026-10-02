# FormCoach interface contracts

Three parts are built in parallel against this file. Do not change a contract here without
updating every side.

| Part | Path | Owner |
|---|---|---|
| Analysis engine (Python reference + Swift port) | `ml/formcoach/`, `ios/FormCore/` | Claude |
| Backend API | `backend/` | Claude (email templates: Antigravity) |
| iOS app | `ios/FormCoach/`, `ios/project.yml` | Codex |
| Sport profiles (thresholds, pro targets, cue text) | `shared/sport_profiles.json` | Claude |

All JSON is **snake_case on the wire**. Swift types use explicit `CodingKeys`. Never use
`convertToSnakeCase` / `convertFromSnakeCase`: those strategies also rewrite dictionary keys,
which corrupts metric ids such as `tempo_ratio`.

## 1. FormCore (Swift package at `ios/FormCore`, product `FormCore`)

Pure Swift, Foundation only, no UIKit/Vision. The app feeds it pose joints; it returns reps.

```swift
import FormCore

public struct JointObservation {           // normalised image coords, origin TOP-LEFT, y down
    public var x: Double, y: Double, confidence: Double
    public init(x: Double, y: Double, confidence: Double)
}

public enum Handedness: String, Codable { case right, left }
public enum EngineState: String { case noPerson = "no_person", moving, ready, active }
//  noPerson: body not visible      moving: visible but not yet still (will not count)
//  ready:    still, armed          active: a motion is in progress

public struct Profiles: Decodable {
    public static func load(from data: Data) throws -> Profiles   // data = sport_profiles.json
    public let joints: [String]            // the 13 joint names, in the order push() expects
    public let sports: [String: SportProfile]   // keys: golf, basketball, tennis, pickleball
}
public struct SportProfile: Decodable {
    public let label: String               // "Golf"
    public let camera: String              // tripod placement instruction to show the user
    public let metrics: [MetricSpec]
}
public struct MetricSpec: Decodable {
    public let id: String, label: String, unit: String
    public let mean: Double, std: Double, tol: Double   // professional target range
}

public struct Rep: Codable {
    public let tStart: Double, tEnd: Double        // "t_start", "t_end"
    public let type: String                         // swing | shot | forehand | backhand | serve | overhead
    public let events: [String: Double]             // e.g. address/top/impact/finish -> seconds
    public let metrics: [String: Double]            // metric id -> raw value
    public let scores: [String: Double]             // metric id -> 0...100
    public let score: Double                        // 0...100
    public let cues: [String]                       // up to 2 coaching sentences
    public let peakSpeed: Double                    // "peak_speed"
}

public enum EngineEvent { case rep(Rep), rejected(reason: String) }

public struct MetricSummary: Codable { public let mean: Double, sd: Double, score: Double; public let n: Int }
public struct SessionSummary: Codable {
    public let sport: String
    public let repCount: Int                        // "rep_count"
    public let rejected: [String: Int]              // reason -> count of motions NOT counted
    public let types: [String: Int]
    public let score: Double?                       // nil when no reps
    public let formScore: Double?                   // "form_score"
    public let consistency: Double?
    public let metrics: [String: MetricSummary]
    public let topCues: [String]                    // "top_cues"
    public let activeS: Double, passiveS: Double    // "active_s", "passive_s"
}

public final class FormEngine {
    public init(profiles: Profiles, sport: String, handedness: Handedness)
    public private(set) var state: EngineState
    public private(set) var reps: [Rep]
    /// Call once per camera frame. `joints` has 13 entries in `profiles.joints` order
    /// (nil when Vision did not return that joint). `aspect` = frame width / height as displayed
    /// (portrait 1080x1920 -> 0.5625). `t` = seconds, monotonic (frame presentation timestamp).
    /// Not thread-safe: always call from the same serial queue.
    public func push(t: Double, joints: [JointObservation?], aspect: Double) -> [EngineEvent]
    public func summary() -> SessionSummary
}
```

Joint order: `nose, l_shoulder, r_shoulder, l_elbow, r_elbow, l_wrist, r_wrist, l_hip, r_hip,
l_knee, r_knee, l_ankle, r_ankle` (l/r are the **person's** anatomical left/right, as Vision labels them).

Vision returns points with origin bottom-left: convert with `y = 1 - point.y`.

## 2. Backend REST API

Base URL is configurable in the app (default `http://localhost:8000`). Auth is
`Authorization: Bearer <access_token>`. Errors are `{"detail": "<message>"}` with a 4xx status.
Timestamps are ISO-8601 UTC strings.

| Method | Path | Auth | Body | Returns |
|---|---|---|---|---|
| GET | `/health` | no | | `{"status": "ok"}` |
| POST | `/auth/register` | no | `{email, password, name}` (password >= 8 chars) | 201 `AuthOut`; 409 if email exists |
| POST | `/auth/login` | no | `{email, password}` | 200 `AuthOut`; 401 on bad credentials |
| GET | `/me` | yes | | `User` |
| PATCH | `/me` | yes | any of `{name, handedness, email_reports}` | `User` |
| DELETE | `/me` | yes | | 204 (deletes the account and all its data) |
| GET | `/profiles` | no | | contents of `sport_profiles.json` |
| POST | `/sessions` | yes | `SessionIn` | 201 `SessionOut` (200 with the stored one if `client_id` was already uploaded) |
| GET | `/sessions?sport=&limit=50` | yes | | `[SessionListItem]`, newest first |
| GET | `/sessions/{id}` | yes | | `SessionOut` |
| POST | `/sessions/{id}/keypoints` | yes | `Recording` (raw pose frames, only if the user opted in) | 204 |
| GET | `/stats/{sport}` | yes | | `Stats` |
| GET | `/checkpoints?sport=` | yes | | `[Checkpoint]`, newest first |

```jsonc
// AuthOut
{"access_token": "...", "token_type": "bearer", "user": User}
// User
{"id": 1, "email": "a@b.com", "name": "Sam", "handedness": "right", "email_reports": true}

// SessionIn  (summary and reps are exactly FormCore's SessionSummary and [Rep] JSON)
{"client_id": "<uuid generated on the phone>", "sport": "golf", "handedness": "right",
 "started_at": "2026-10-02T18:00:00Z", "duration_s": 312.4,
 "summary": SessionSummary, "reps": [Rep], "app_version": "1.0", "device": "iPhone16,2"}

// SessionListItem
{"id": 12, "client_id": "...", "sport": "golf", "started_at": "...", "duration_s": 312.4,
 "rep_count": 14, "score": 78.2}

// SessionOut = SessionListItem + {"handedness", "summary", "reps", "comparison": Comparison,
//                                 "checkpoint": Checkpoint | null}   // checkpoint set when this session completed one

// Comparison  (this session against the user's own previous sessions and the pro target)
{"previous_sessions": 4, "previous_avg_score": 74.0, "score_delta": 4.2,
 "metrics": [MetricComparison]}
// MetricComparison
{"id": "tempo_ratio", "label": "Tempo (backswing : downswing)", "unit": "ratio",
 "value": 2.7, "previous": 2.4, "pro": 3.0, "score": 81.0,
 "direction": "better"}      // better | worse | same | null (null = no previous data)

// Stats
{"sport": "golf", "sessions": 9, "total_reps": 120, "avg_score": 75.1, "best_score": 88.0,
 "recent_avg_score": 79.0, "previous_avg_score": 73.0,     // last 5 sessions vs the 5 before
 "metrics": [MetricComparison],                             // value = recent avg, previous = prior avg
 "trend": [{"id": 3, "started_at": "...", "score": 71.0, "rep_count": 12}]}   // oldest first

// Checkpoint  (created every 5 sessions per sport, and emailed)
{"id": 2, "sport": "golf", "number": 2, "created_at": "...", "sessions": 5, "total_reps": 61,
 "avg_score": 79.0, "previous_avg_score": 73.0,
 "metrics": [MetricComparison], "focus_cues": ["..."]}

// Recording
{"sport": "golf", "handedness": "right", "aspect": 0.5625,
 "frames": [{"t": 0.033, "j": [[x, y, conf], ... 13 joints]}]}
```

## 3. Email templates (`backend/app/email_templates.py`)

Pure functions, no I/O, no network, standard library only. Each returns
`(subject, html_body, text_body)`.

```python
def session_email(user_name: str, sport_label: str, session: dict, comparison: dict) -> tuple[str, str, str]:
    """session: SessionListItem fields + "top_cues": [str].  comparison: Comparison (above)."""

def checkpoint_email(user_name: str, sport_label: str, checkpoint: dict) -> tuple[str, str, str]:
    """checkpoint: Checkpoint (above)."""
```

`previous`, `score_delta`, `previous_avg_score` and `direction` may be `None` (first session /
first checkpoint): the templates must render sensibly without them. All user-supplied strings
must be HTML-escaped.
