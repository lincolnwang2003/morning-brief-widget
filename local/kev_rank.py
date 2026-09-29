"""Rank tasks with Kev-4B running locally.

Asking Kev one fuzzy question ("high, medium or low?") gave 41-61% confidence. Instead Kev answers several concrete
yes/no questions it is good at (is this an exam? a graded deliverable? did a professor ask?), with calibrated
probabilities, and the priority rules in prompt.md are applied to those facts in code. The date part (how many days
away) is plain arithmetic, so no model is asked about it.

The server is started only for the ranking (~6.6 GB RAM) and stopped afterwards, unless one was already running.
"""
import json
import subprocess
import time
import urllib.request
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PORT = 8009
URL = f"http://127.0.0.1:{PORT}"
YES = 0.5  # a fact counts as true above this probability

FACTS = {
    # Worded to exclude reviews: "Is this an exam, quiz or test...?" scored a "progress review" meeting 0.86.
    "exam": "Is the item itself a test (exam, quiz or midterm) that the student takes, as opposed to a meeting, "
            "review or discussion?",
    "graded": "Is this a graded assignment, project, paper or team deliverable that the student has to submit?",
    "asked": "Is a professor, TA or instructor directly asking the student to do something or reply?",
    "action": "Does the student have to prepare, submit or reply to something, rather than just show up?",
    "meeting": "Is this a meeting or event with other people that the student is expected to attend?",
    "optional": "Is this optional, for information only, or a routine class the student attends anyway?",
}


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
    (ROOT / "logs").mkdir(exist_ok=True)
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


def _state(item):
    lines = [f"Item: {item['title']}", f"Found in: {', '.join(item.get('sources') or []) or 'unknown'}"]
    if item.get("context"):
        lines.append(f"Details: {item['context']}")
    return "\n".join(lines)


def _when(days):
    return {0: "today", 1: "tomorrow"}.get(days, f"in {days} days")


def decide(p, days):
    """The prompt.md rules, applied to Kev's facts. -> (priority, reason, confidence of the deciding fact)."""
    yes = {k: v >= YES for k, v in p.items()}
    sure = lambda k: p[k] if yes[k] else 1 - p[k]
    when = _when(days)

    if yes["exam"] and days <= 3:
        return "high", f"Exam · {when}", sure("exam")
    if yes["graded"] and days <= 2:
        return "high", f"Graded · due {when}", sure("graded")
    if yes["asked"]:
        return "high", "Professor/TA request", sure("asked")
    # Before "to do today": RSVPing to an optional event is an action, but still optional.
    if yes["optional"] and not (yes["exam"] or yes["graded"]):
        return "low", "Optional / FYI", sure("optional")
    if days == 0 and yes["action"]:
        return "high", "To do today", sure("action")
    if yes["graded"] or yes["exam"]:
        k = "exam" if yes["exam"] else "graded"
        return "medium", f"{'Exam' if k == 'exam' else 'Graded'} · {when}", sure(k)
    if yes["action"]:
        return "medium", "Needs a reply or prep", sure("action")
    if yes["meeting"]:
        return "medium", "Meeting", sure("meeting")
    return "low", "FYI", min(sure(k) for k in p)


def score(item, today):
    resp = _post("/v1/systemone", {
        "state": _state(item),
        "model": "kev-latest",
        "questions": {k: {"type": "noul", "instructions": q} for k, q in FACTS.items()},
    })
    p = {k: resp["answers"][k]["noul"] for k in FACTS}
    days = (date.fromisoformat(item["date"]) - today).days
    item["claude_priority"], item["claude_reason"] = item.get("priority"), item.get("reason")
    item["priority"], item["reason"], conf = decide(p, days)
    item["confidence"] = round(conf, 2)
    item["facts"] = {k: round(v, 2) for k, v in p.items()}
    return item


def rank(items, log):
    """Score every item in place. Returns a label for the widget footer, or raises."""
    today = date.today()
    proc = start_server(log)
    try:
        t0 = time.time()
        for item in items:
            score(item, today)
        log(f"kev: scored {len(items)} items in {time.time() - t0:.1f}s")
    finally:
        if proc:  # only stop a server we started
            proc.terminate()
            proc.wait(timeout=30)
    changed = sum(i["priority"] != i["claude_priority"] for i in items)
    return f"Kev-4B (local) · {changed} changed from Claude"


if __name__ == "__main__":
    # Re-rank the current data/today.json by hand and compare with Claude: python3 local/kev_rank.py
    b = json.loads((ROOT / "data" / "today.json").read_text())
    items = b["today"] + b["upcoming"]
    for i in items:
        i.setdefault("date", date.today().isoformat())
        i["priority"] = i.get("claude_priority") or i.get("priority")
    print(rank(items, print))
    for i in items:
        facts = " ".join(f"{k}={v:.2f}" for k, v in i["facts"].items())
        print(f"{i['priority']:6} {i['confidence']:.0%} (claude:{i['claude_priority']:6}) {i['date'][5:]} "
              f"{i['title'][:40]:40} | {i['reason']:22} | {facts}")
