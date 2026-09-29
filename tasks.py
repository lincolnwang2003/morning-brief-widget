"""Deterministic task handling: everything that doesn't need AI judgment.

Claude only collects tasks. Grouping into today / upcoming, dropping past or out-of-range items, de-duplicating,
stable ids and sorting happen here, so the same tasks always land in the same place.
"""
import hashlib
import json
import re
from datetime import date, datetime, timedelta
from pathlib import Path

DONE = Path(__file__).resolve().parent / "data" / "done.json"
RANK = {"high": 0, "medium": 1, "low": 2}


def task_id(item):
    """Stable across runs even when Claude words the title differently: Canvas/Gmail links are stable,
    titles are the fallback. Recurring meetings share a link, so the date is part of the id."""
    link = (item.get("link") or "").strip()
    base = link if link.startswith("http") else re.sub(r"[^a-z0-9]+", " ", item["title"].lower()).strip()
    return hashlib.sha1(f"{base}|{item['date']}".encode()).hexdigest()[:12]


def normalize(items, today, lookahead):
    """Validate dates, keep the window [today, today + lookahead], assign ids, merge exact duplicates."""
    end = today + timedelta(days=lookahead)
    out = {}
    for item in items:
        try:
            d = date.fromisoformat(str(item.get("date"))[:10])
        except ValueError:
            d = today  # an undated request ("please reply") is for today
        if not (today <= d <= end) or not item.get("title"):
            continue
        item["date"] = d.isoformat()
        item["id"] = task_id(item)
        if item["id"] in out:  # same task twice: keep one, remember every source
            prev = out[item["id"]]
            prev["sources"] = sorted(set(prev.get("sources") or []) | set(item.get("sources") or []))
            continue
        out[item["id"]] = item
    return list(out.values())


def load_done():
    try:
        return json.loads(DONE.read_text())
    except (OSError, json.JSONDecodeError):
        return {}


def split(items, today):
    """-> (today, upcoming), done items removed, each sorted by priority then time."""
    done = load_done()
    items = [i for i in items if i["id"] not in done]
    key = lambda i: (i["date"], RANK.get(i.get("priority"), 3), i.get("time") or "99:99")
    items.sort(key=key)
    t = today.isoformat()
    return [i for i in items if i["date"] == t], [i for i in items if i["date"] > t]


def mark_done(task, title=""):
    done = load_done()
    done[task] = {"title": title, "at": datetime.now().isoformat(timespec="seconds")}
    # Forget entries older than two weeks; their dates have passed anyway.
    cutoff = (datetime.now() - timedelta(days=14)).isoformat()
    done = {k: v for k, v in done.items() if v.get("at", "") >= cutoff}
    DONE.write_text(json.dumps(done, indent=2, ensure_ascii=False))


def undo_last():
    done = load_done()
    if done:
        last = max(done, key=lambda k: done[k].get("at", ""))
        del done[last]
        DONE.write_text(json.dumps(done, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    # Used by the widget: python3 tasks.py done <id> [title] | python3 tasks.py undo
    import sys
    if sys.argv[1:2] == ["done"]:
        mark_done(sys.argv[2], " ".join(sys.argv[3:]))
    elif sys.argv[1:2] == ["undo"]:
        undo_last()
