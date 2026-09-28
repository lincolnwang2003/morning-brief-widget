"""Download the Canvas calendar feed (.ics) and return upcoming items as plain dicts.

Canvas -> Calendar -> "Calendar Feed" gives a private URL that contains every
assignment due date and course event. No API token needed.
"""
import re
import urllib.request
from datetime import date, datetime, timedelta, timezone


def _unfold(text):
    # ICS wraps long lines: a line starting with a space continues the previous one.
    return re.sub(r"\r?\n[ \t]", "", text).splitlines()


def _unescape(value):
    return (value.replace("\\n", "\n").replace("\\N", "\n")
                 .replace("\\,", ",").replace("\\;", ";").replace("\\\\", "\\"))


def _parse_dt(params, value):
    """Return (local datetime, is_all_day)."""
    if "VALUE=DATE" in params or len(value) == 8:
        d = datetime.strptime(value[:8], "%Y%m%d")
        return d, True
    if value.endswith("Z"):
        utc = datetime.strptime(value, "%Y%m%dT%H%M%SZ").replace(tzinfo=timezone.utc)
        return utc.astimezone().replace(tzinfo=None), False
    # TZID=... times: Canvas uses the user's zone, treat as local.
    return datetime.strptime(value[:15], "%Y%m%dT%H%M%S"), False


def parse_ics(text):
    events, current = [], None
    for line in _unfold(text):
        if line == "BEGIN:VEVENT":
            current = {}
        elif line == "END:VEVENT":
            if current is not None and "start" in current:
                events.append(current)
            current = None
        elif current is not None and ":" in line:
            key_part, value = line.split(":", 1)
            key, _, params = key_part.partition(";")
            if key == "DTSTART":
                current["start"], current["all_day"] = _parse_dt(params, value)
            elif key == "SUMMARY":
                current["summary"] = _unescape(value)
            elif key == "DESCRIPTION":
                current["description"] = _unescape(value)
            elif key == "URL":
                current["url"] = value
    return events


def _split_course(summary):
    # Canvas titles look like "Homework 3 [PM 4001]"
    m = re.match(r"^(.*?)\s*\[(.+)\]\s*$", summary)
    return (m.group(1), m.group(2)) if m else (summary, None)


def upcoming(ics_url, days=4, now=None):
    now = now or datetime.now()
    with urllib.request.urlopen(ics_url, timeout=30) as resp:
        text = resp.read().decode("utf-8", errors="replace")

    start = datetime.combine(now.date(), datetime.min.time())
    end = start + timedelta(days=days)
    items = []
    for ev in parse_ics(text):
        if not (start <= ev["start"] < end):
            continue
        title, course = _split_course(ev.get("summary", "(untitled)"))
        items.append({
            "title": title,
            "course": course,
            "due": ev["start"].strftime("%Y-%m-%d") if ev["all_day"]
                   else ev["start"].strftime("%Y-%m-%d %H:%M"),
            "is_assignment": "assignment" in ev.get("url", "") or "assignment" in ev.get("description", "").lower(),
            "url": ev.get("url"),
            "details": ev.get("description", "")[:300],
        })
    items.sort(key=lambda i: i["due"])
    return items


if __name__ == "__main__":
    import json, sys
    print(json.dumps(upcoming(sys.argv[1]), indent=2, ensure_ascii=False))
