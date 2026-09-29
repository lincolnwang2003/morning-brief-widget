#!/usr/bin/env python3
"""Morning pipeline: Canvas feed -> Claude agent (Gmail + Calendar connectors) collects tasks
-> tasks.py groups them by date -> Kev-4B ranks them locally -> data/today.json.

The Übersicht widget reads data/today.json. launchd runs this every morning.
"""
import fcntl
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import date, datetime, timedelta
from pathlib import Path

import canvas
import tasks
from local import kev_rank

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "data"
LOGS = ROOT / "logs"
OUTPUT = DATA / "today.json"


def log(msg):
    LOGS.mkdir(exist_ok=True)
    line = f"[{datetime.now():%Y-%m-%d %H:%M:%S}] {msg}"
    print(line)
    with open(LOGS / "run.log", "a") as f:
        f.write(line + "\n")


def load_config():
    path = ROOT / "config.json"
    if not path.exists():
        sys.exit("config.json not found - copy config.example.json and fill it in.")
    return json.loads(path.read_text())


def write_output(payload):
    DATA.mkdir(exist_ok=True)
    tmp = OUTPUT.with_suffix(".tmp")
    tmp.write_text(json.dumps(payload, indent=2, ensure_ascii=False))
    tmp.replace(OUTPUT)  # atomic, so the widget never reads a half-written file


def write_status(status, error=None):
    """Update status fields but keep the last good task list on screen."""
    try:
        payload = json.loads(OUTPUT.read_text())
    except (OSError, json.JSONDecodeError):
        payload = {"summary": "", "today": [], "upcoming": []}
    payload["status"] = status
    payload["error"] = error
    write_output(payload)


def build_prompt(cfg, canvas_items):
    now = datetime.now().astimezone()
    lookahead = cfg.get("lookahead_days", 3)
    template = (ROOT / "prompt.md").read_text()
    return template.format(
        today=now.strftime("%A, %Y-%m-%d"),
        now=now.strftime("%H:%M"),
        tz=now.tzname(),
        lookahead=lookahead,
        end_date=(now + timedelta(days=lookahead)).strftime("%Y-%m-%d"),
        canvas_json=json.dumps(canvas_items, indent=2, ensure_ascii=False),
        language=cfg.get("language", "English"),
    )


def run_agent(cfg, prompt):
    claude = cfg.get("claude_path") or shutil.which("claude") or str(Path.home() / ".local/bin/claude")
    cmd = [
        claude, "-p", prompt,
        "--output-format", "json",
        "--max-turns", "20",
        "--allowedTools", *cfg["allowed_tools"],
        "--disallowedTools", "Bash", "Edit", "Write", "NotebookEdit", "WebFetch", "WebSearch",
    ]
    if cfg.get("model"):
        cmd += ["--model", cfg["model"]]
    # Run from a neutral directory so project settings/CLAUDE.md don't leak in.
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=600, cwd=DATA)
    if proc.returncode != 0:
        raise RuntimeError(f"claude exited {proc.returncode}: {proc.stderr.strip() or proc.stdout.strip()}")
    envelope = json.loads(proc.stdout)
    if envelope.get("is_error"):
        raise RuntimeError(f"agent error: {envelope.get('result')}")
    return envelope["result"]


def parse_result(text):
    # The agent is told to return bare JSON, but tolerate code fences or stray prose.
    match = re.search(r"\{.*\}", text, re.DOTALL)
    if not match:
        raise ValueError(f"no JSON in agent reply: {text[:200]}")
    result = json.loads(match.group(0))
    if not isinstance(result.get("items"), list):
        raise ValueError("agent reply missing list 'items'")
    return result


def main():
    DATA.mkdir(exist_ok=True)
    lock = open(DATA / ".lock", "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        log("another run is in progress, skipping")
        return

    cfg = load_config()
    log("start")
    write_status("running")
    try:
        canvas_items = canvas.upcoming(cfg["canvas_ics_url"], days=cfg.get("lookahead_days", 3) + 1)
        log(f"canvas: {len(canvas_items)} items")
        (DATA / "canvas.json").write_text(json.dumps(canvas_items, indent=2, ensure_ascii=False))

        reply = parse_result(run_agent(cfg, build_prompt(cfg, canvas_items)))
        today = date.today()
        items = tasks.normalize(reply["items"], today, cfg.get("lookahead_days", 3))
        log(f"agent: {len(reply['items'])} items, {len(items)} in range")

        ranker = "Claude"
        if cfg.get("local_ranker") == "kev":
            try:
                ranker = kev_rank.rank(items, log)
            except Exception as e:  # the local model is optional: keep Claude's priorities
                log(f"kev ranking skipped: {e}")
                ranker = "Claude (local model unavailable)"

        today_items, upcoming = tasks.split(items, today)
        result = {"summary": reply.get("summary", ""), "today": today_items, "upcoming": upcoming,
                  "ranker": ranker, "status": "ok", "error": None,
                  "generated_at": datetime.now().isoformat(timespec="minutes")}
        write_output(result)
        log(f"done: {len(result['today'])} today, {len(result['upcoming'])} upcoming")
    except Exception as e:  # keep yesterday's list visible and show the error in the widget
        log(f"FAILED: {e}")
        write_status("error", str(e)[:300])
        sys.exit(1)


if __name__ == "__main__":
    main()
