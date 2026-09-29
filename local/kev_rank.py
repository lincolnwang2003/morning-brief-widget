"""Re-rank the agent's task list with Kev-4B running locally.

Claude collects and merges tasks from Canvas, Gmail and Calendar. Kev then answers, for each task, a typed
question with calibrated probabilities: "high / medium / low priority?". The answer is deterministic, so the same
inputs always give the same order, and the probability says how sure the model is.

The server is started only for the ranking (~6.6 GB RAM) and stopped afterwards, unless one was already running.
"""
import json
import subprocess
import time
import urllib.request
from datetime import date, datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PORT = 8009
URL = f"http://127.0.0.1:{PORT}"

# The same rules prompt.md gives Claude, as Kev's answer options.
PRIORITY = {
    "type": "choice",
    "instructions": "How should a busy university student prioritize this item right now?",
    "criteria": {
        "high": "Must be done or attended today or before tomorrow morning; an exam or quiz within 3 days; "
                "a large project, paper or team deliverable due within 2 days; a professor or TA asking the "
                "student to do or reply to something",
        "medium": "Regular homework due in 2-3 days; an email that needs a reply but is not urgent; "
                  "a meeting with other people",
        "low": "A routine class the student attends anyway, an optional event, or information only",
    },
}
ACTION = {"type": "noul", "instructions": "Does this require the student to prepare, submit or reply to something, "
                                          "rather than just show up?"}


def _get(path, timeout=2):
    with urllib.request.urlopen(URL + path, timeout=timeout) as r:
        return json.loads(r.read())


def _post(path, body, timeout=120):
    req = urllib.request.Request(URL + path, json.dumps(body).encode(), {"content-type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())


def server_up():
    try:
        return bool(_get("/v1/models").get("models"))
    except Exception:
        return False


def start_server(log, timeout=300):
    """Start the local Kev server; returns the process (or None if one was already running)."""
    if server_up():
        return None
    out = open(ROOT / "logs" / "kev.log", "a")
    proc = subprocess.Popen(
        ["uv", "run", "--project", str(ROOT / "vendor" / "kev"), "python", str(ROOT / "local" / "kev_server.py"),
         "--port", str(PORT)],
        stdout=out, stderr=subprocess.STDOUT, cwd=ROOT)
    deadline = time.time() + timeout
    while time.time() < deadline:
        if proc.poll() is not None:
            raise RuntimeError(f"Kev server exited with {proc.returncode}; see logs/kev.log")
        if server_up():
            log("kev: server ready")
            return proc
        time.sleep(1)
    proc.terminate()
    raise RuntimeError("Kev server did not start in time; see logs/kev.log")


def _state(item, today):
    """The text Kev reads for one task. Day counts are spelled out: Kev is better with explicit ones."""
    when = item.get("date") or today.isoformat()
    days = (date.fromisoformat(when) - today).days
    rel = {0: "today", 1: "tomorrow"}.get(days, f"in {days} days")
    sources = ", ".join(item.get("sources") or []) or "unknown"
    lines = [
        f"Today is {today:%A, %B %d, %Y}.",
        f"Item: {item['title']}",
        f"When: {when}{' at ' + item['time'] if item.get('time') else ''} ({rel})",
        f"Found in: {sources}",
    ]
    if item.get("context"):
        lines.append(f"Details: {item['context']}")
    return "\n".join(lines)


def score(item, today):
    resp = _post("/v1/systemone", {
        "state": _state(item, today),
        "model": "kev-latest",
        "questions": {"priority": PRIORITY, "action": ACTION},
    })
    p = resp["answers"]["priority"]["probabilities"]
    item["claude_priority"] = item.get("priority")
    item["priority"] = max(p, key=p.get)
    item["confidence"] = round(p[item["priority"]], 2)
    item["needs_action"] = round(resp["answers"]["action"]["noul"], 2)
    item["_urgency"] = 2 * p.get("high", 0) + p.get("medium", 0)
    return item


def rerank(brief, log):
    """Score every item with Kev and re-sort. Returns the brief with ranker info, or raises."""
    today = date.today()
    proc = start_server(log)
    try:
        t0 = time.time()
        for item in brief["today"] + brief["upcoming"]:
            score(item, today)
        log(f"kev: scored {len(brief['today']) + len(brief['upcoming'])} items in {time.time() - t0:.1f}s")
    finally:
        if proc:  # only stop a server we started
            proc.terminate()
            proc.wait(timeout=30)

    brief["today"].sort(key=lambda i: (-i["_urgency"], i.get("time") or "99:99"))
    brief["upcoming"].sort(key=lambda i: (i.get("date") or "", -i["_urgency"], i.get("time") or "99:99"))
    for item in brief["today"] + brief["upcoming"]:
        del item["_urgency"]
    changed = sum(i["priority"] != i["claude_priority"] for i in brief["today"] + brief["upcoming"])
    brief["ranker"] = f"Kev-4B (local) · {changed} changed from Claude"
    return brief


if __name__ == "__main__":
    # Re-rank the current data/today.json by hand: python3 local/kev_rank.py
    path = ROOT / "data" / "today.json"
    b = rerank(json.loads(path.read_text()), print)
    for i in b["today"] + b["upcoming"]:
        print(f"{i['priority']:6} {i['confidence']:.2f} (claude: {i['claude_priority']:6}) {i.get('date', 'today')} {i['title']}")
