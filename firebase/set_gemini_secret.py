"""Store the key in gemini/geminiapi.js as a Firebase Functions secret.

Run after the Firebase project is upgraded to Blaze:
    python3 firebase/set_gemini_secret.py

The key is passed to Firebase CLI through stdin and is never printed or added
to the app bundle/repository.
"""

from pathlib import Path
import re
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
KEY_NOTE = ROOT / "gemini" / "geminiapi.js"
FIREBASE_CLI = ROOT / ".tools" / "firebase" / "node_modules" / ".bin" / "firebase"
PROJECT_ID = "pharmacare-a43c3"


def main() -> int:
    if not KEY_NOTE.is_file():
        print(f"Gemini key note not found: {KEY_NOTE}", file=sys.stderr)
        return 1
    match = re.search(r"API Key\s+is here\s*:\s*(\S+)", KEY_NOTE.read_text())
    if match is None:
        print("Could not find the labeled Gemini API key in the key note.", file=sys.stderr)
        return 1
    if not FIREBASE_CLI.is_file():
        print(f"Firebase CLI not found: {FIREBASE_CLI}", file=sys.stderr)
        return 1

    result = subprocess.run(
        [
            str(FIREBASE_CLI),
            "functions:secrets:set",
            "GEMINI_API_KEY",
            "--data-file",
            "-",
            "--format",
            "string",
            "--project",
            PROJECT_ID,
        ],
        input=match.group(1),
        text=True,
        check=False,
    )
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
