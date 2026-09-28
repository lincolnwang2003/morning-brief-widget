# Morning Brief Widget

An AI agent that reads my **Canvas**, **school email**, and **Google Calendar** every morning, decides what matters most, and puts one ranked to-do list on my Mac desktop.

## The problem

Every morning I had to check three places to figure out what I needed to do:

- **Canvas** for assignment deadlines
- **Gmail** for professor/TA emails, quiz retakes, schedule changes
- **Google Calendar** for classes, team meetings, advisor sessions

Each one shows only part of the picture, and important things hide in the gaps. A quiz retake announced by email never appears in Canvas. A meeting invite sits in both my inbox and my calendar. Clicking through all three every day took time, and I still missed things.

## What it does

When I open my laptop, a widget in the corner of my desktop shows:

- **Today**: what I must do or attend today, ranked by importance
- **Next 3 days**: upcoming deadlines and events, grouped by day
- A one-sentence summary of my day

Items are color-coded (🔴 high, 🟡 medium, ⚪ low), each has a short reason ("Team deliverable due in 2 days"), and clicking one opens the Canvas page, email, or meeting link.

## How it works

```
Every day at 7:00 (and at login)
        │
        ├─ Canvas calendar feed ──► Python downloads upcoming assignments
        │
        ▼
   Claude agent (Claude Code, headless)
        ├─ reads Google Calendar through the Calendar connector (MCP)
        ├─ reads recent school email through the Gmail connector (MCP)
        └─ merges duplicates, ranks by urgency and importance, writes a reason
        │
        ▼
   data/today.json ──► Übersicht desktop widget
```

The AI does more than collect data. It understands it. It can tell that an email from a TA asking me to reschedule is urgent, that a newsletter isn't, and that a Canvas assignment, its reminder email, and a calendar block are all the same task.

Ranking rules live in plain English in [`prompt.md`](prompt.md), so they're easy to read and change.

| File | Purpose |
|---|---|
| `canvas.py` | Downloads and parses the Canvas calendar feed (.ics) |
| `prompt.md` | Instructions for the agent: sources, ranking rules, output format |
| `run.py` | Pipeline: Canvas → Claude agent → `data/today.json` |
| `widget/daily-todo.widget/` | Übersicht desktop widget |
| `launchd/` | macOS schedule (7:00 daily + at login) |
| `install.sh` | Installs the widget and the schedule |

## Setup

Requirements: macOS, Python 3, [Claude Code](https://claude.com/claude-code) signed in with a Claude account, and [Übersicht](https://tracesof.net/uebersicht/).

1. **Connect Gmail and Google Calendar**: run `claude`, type `/mcp`, and authenticate **claude.ai Gmail** and **claude.ai Google Calendar**.
2. **Get your Canvas feed link**: Canvas → Calendar → *Calendar Feed* (bottom right), then copy the `.ics` URL.
3. **Configure**: `cp config.example.json config.json` and paste the link into `canvas_ics_url`.
4. **Install Übersicht**: `brew install --cask ubersicht`
5. **Install**: `./install.sh`. This links the widget and schedules the daily run.
6. Test once by hand: `python3 run.py`

The paths in `widget/daily-todo.widget/index.jsx` and `launchd/*.plist` point to this project's folder. Edit them if you clone it somewhere else.

## Safety

The agent can only use **read-only** tools (search/read email, list calendar events). It cannot send email, create drafts, or change calendar events. Those tools are left off the allow-list in `config.json`, and Bash, file editing, and web access are explicitly blocked.

`config.json` (private Canvas link), `data/` (my tasks), and `logs/` are git-ignored.

## Challenges & limitations

- **Results vary between runs.** The same inputs produced "0 today / 6 upcoming" on one run and "1 today / 5 upcoming" on the next. AI judgment on borderline items isn't perfectly consistent.
- **Canvas feed doesn't know what I've submitted.** Finished assignments still appear until their due date passes. The full Canvas API would fix this but needs a personal access token.
- **"Importance" is subjective.** The rules in `prompt.md` are my own heuristics; the agent can still misjudge an email's urgency.
- **Only runs when my Mac is on.** If the laptop is off at 7:00, it updates at the next login instead.
- **Privacy trade-off.** My email and calendar are read by an AI model every morning. I limited it to read-only access and a 2-day email window.
- **Speed.** Each run takes ~30 seconds because the agent makes several tool calls. That's fine for a morning job but too slow for instant refresh.

## Built with AI

This project was 100% vibe-coded: every line was written by Claude (Claude Code) from natural-language requests. My role was defining the problem, making design decisions, and testing.
