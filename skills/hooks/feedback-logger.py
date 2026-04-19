#!/usr/bin/env python3
"""Scan UserPromptSubmit payload for behavioral-feedback phrases and
append candidates to ~/.claude/feedback-pending.jsonl for later review."""
import json
import os
import re
import sys
import time
from pathlib import Path

CORRECTION = [
    r"\bdon'?t\s+(do|use|run|call|add|write|create|include|include)",
    r"\bstop\s+(doing|using|calling|running|adding|writing)",
    r"\bnever\s+(do|use|run|call|include)",
    r"\bthat'?s\s+wrong\b",
    r"\bwrong\s+(approach|answer|direction|thing)",
    r"\bno,?\s+(not|don'?t|never)",
    r"\bactually,?\s+(you\s+should|let'?s|please)",
    r"\bi\s+told\s+you\b",
    r"\bi\s+already\s+said\b",
    r"\bplease\s+stop\b",
    r"\brevert\b",
    r"\bundo\b",
]

SUCCESS = [
    r"\bperfect\b",
    r"\bexactly\s+(right|what)",
    r"\bnice\s+(work|job)",
    r"\bgreat\s+(work|job|call)",
    r"\blooks?\s+good\b",
    r"\bthat\s+works\b",
    r"\byes,?\s+(exactly|that'?s)",
    r"\bkeep\s+(doing|that)",
    r"\bright\s+call\b",
    r"\bwell\s+done\b",
    r"\bthanks?,?\s+(that|that'?s)\s+(was|perfect|great)",
]

def read_last_assistant_snippet(transcript_path: str, chars: int = 600) -> str:
    """Return a short snippet of the last assistant turn from a JSONL transcript."""
    if not transcript_path or not os.path.exists(transcript_path):
        return ""
    try:
        lines = Path(transcript_path).read_text(errors="ignore").splitlines()
    except Exception:
        return ""
    for line in reversed(lines):
        try:
            d = json.loads(line)
        except Exception:
            continue
        msg = d.get("message") or d
        if not isinstance(msg, dict):
            continue
        if msg.get("role") != "assistant":
            continue
        content = msg.get("content", "")
        if isinstance(content, list):
            parts = []
            for b in content:
                if isinstance(b, dict) and b.get("type") == "text":
                    parts.append(b.get("text", ""))
            content = " ".join(parts)
        text = str(content).strip()
        if text:
            return text[:chars]
    return ""

def main() -> int:
    try:
        d = json.load(sys.stdin)
    except Exception:
        return 0

    prompt = str(d.get("prompt", "")).strip()
    if not prompt or len(prompt) > 2000:
        return 0

    low = prompt.lower()
    kind = None
    matched = None
    for pat in CORRECTION:
        m = re.search(pat, low)
        if m:
            kind = "correction"
            matched = m.group(0)
            break
    if not kind:
        for pat in SUCCESS:
            m = re.search(pat, low)
            if m:
                kind = "success"
                matched = m.group(0)
                break
    if not kind:
        return 0

    # Skip if the user is clearly asking a question
    if prompt.strip().startswith(("what", "why", "how", "when", "where", "who", "is ", "are ")):
        if "?" in prompt[:200]:
            return 0

    transcript = d.get("transcript_path", "") or ""
    snippet = read_last_assistant_snippet(transcript)

    entry = {
        "ts": int(time.time()),
        "kind": kind,
        "matched": matched,
        "prompt": prompt[:500],
        "assistant_snippet": snippet,
    }

    log = Path(os.path.expanduser("~/.claude/feedback-pending.jsonl"))
    log.parent.mkdir(parents=True, exist_ok=True)

    try:
        if log.exists() and log.stat().st_size > 1_500_000:
            keep = log.read_text(errors="ignore").splitlines()[-300:]
            log.write_text("\n".join(keep) + "\n")
    except Exception:
        pass

    with log.open("a") as f:
        f.write(json.dumps(entry) + "\n")
    return 0

if __name__ == "__main__":
    sys.exit(main())
