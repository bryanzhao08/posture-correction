# Data Sources

| Name | URL | Contents | View Angle | Size | License | Free Download | Verdict | Reason |
|---|---|---|---|---|---|---|---|---|
| CaddieSet 2025 | CVPR 2025 | Human joint info + ball trajectory | Mixed | Unknown | Unknown | No | no | Gated dataset requiring academic request. |
| GolfPose (GolfSwing) | https://github.com/MingHanLee/GolfPose | 3D/2D golf swing poses | Mixed | Unknown | Unknown | No | no | Gated dataset requiring an email request to the author. |
| minwookim/golf-swing-phase-image-dataset | Kaggle | Golf swing phases | Mixed | ~40MB | CC0 | Yes | no | Contains static images only, lacking the temporal video/pose data needed by the engine. |
| UCF101 | https://www.crcv.ucf.edu/data/UCF101.php | Human action videos (incl. GolfSwing) | Mixed | ~6.5GB | Custom | Yes | no | Exceeds the 3GB limit and contains mixed/random angles (not strictly face-on). |
| Henu-MultiSubjects | Hugging Face: Henu-Software/Henu-MultiSubjects | Amateur basketball action recognition | Mixed | Unknown | Unknown | No | no | Gated dataset requiring an email request. |
| muyu111/basketball (SHOT) | Hugging Face: muyu111/basketball | Basketball clips for group intention | 5 views (broadcast) | 15.4GB | Unknown | Yes | no | Exceeds 3GB and focuses on multi-player broadcast angles, not individual face-on jump shots. |
| amathislab/SHOT7M2 | Hugging Face: amathislab/SHOT7M2 | 7.2M synthetic basketball frames & 3D poses | Synthetic | 4.6GB | CC BY-NC-SA 4.0 | Yes | no | Exceeds 3GB and consists of synthetic generated poses rather than real amateurs. |
| leharris3/basketball-shot-test-dataset | Hugging Face: leharris3/basketball-shot-test-dataset | NBA basketball shots (made/missed) | Broadcast | ~417MB | MIT | Yes | no | Contains broadcast footage of professional players, not amateurs. |
| ShuttleSet | https://github.com/wywyWang/CoachAI-Projects | Badminton rally/stroke metadata | Broadcast | Small | MIT | Yes | no | Contains hit locations and metadata, but lacks player pose coordinates or video. |
| OpenTTGames | https://github.com/osai-ai/OpenTTGames | Table tennis videos (120fps) and ball events | High-angle | Large | CC BY-NC-SA 4.0 | Yes | no | Captured from a high, fixed broadcast angle rather than face-on, designed primarily for ball tracking. |
| TTStroke-21 | MediaEval / University of Bordeaux | Table tennis strokes (20 classes) | Broadcast | Unknown | Restricted | No | no | Private/Restricted access due to athlete privacy regulations. |
