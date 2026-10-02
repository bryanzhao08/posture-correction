import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
os.environ["FORMCOACH_DATA_DIR"] = tempfile.mkdtemp(prefix="formcoach-test-")
os.environ.pop("RESEND_API_KEY", None)
sys.path.insert(0, str(ROOT / "backend"))
sys.path.insert(0, str(ROOT / "ml"))
