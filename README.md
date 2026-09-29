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
        └─ merges duplicates, writes a short context for each task
        │
        ▼
   Kev-4B, running locally on my Mac (optional)
        └─ scores each task high / medium / low with a probability
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
| `run.py` | Pipeline: Canvas → Claude agent → Kev → `data/today.json` |
| `local/kev_server.py` | Local Kev-4B server using the 8-bit MLX weights |
| `tasks.py` | Groups tasks by date, removes duplicates and finished tasks (no AI) |
| `local/kev_rank.py` | Scores each task with Kev and applies the priority rules |
| `app/` | Experimental native menu bar app + widget + DMG (see below) |
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

## Local ranking with Kev-4B

Claude is great at reading messy email, but its judgment varies from run to run. So the final ranking step runs on a
small local model: [Kev-4B](https://huggingface.co/jaredpalmer/kev-4b), in the 8-bit MLX build
[RoderickQiu/kev-4b-mlx-8bit](https://huggingface.co/RoderickQiu/kev-4b-mlx-8bit). Kev is a *decision model*: it can't
chat or call tools, but it answers a multiple-choice question with calibrated probabilities.

For every task Claude collected, Kev answers six concrete yes/no questions (is it an exam? a graded deliverable?
did a professor ask? does it need prep or a reply? is it a meeting? is it optional?). Code then applies the rules
from `prompt.md` to those facts plus the number of days until the date, and writes a readable reason such as
"Exam · tomorrow · 91%". `claude_priority` keeps Claude's original answer for comparison.

- **Same input, same answer.** Two runs on the same tasks gave identical scores.
- **It sometimes follows the rules better.** A professor asked every team to schedule a project review. Claude
  said medium; Kev said high, which is what my rule says for "a professor asks you to do something".
- **Loaded only when needed.** `run.py` starts the server, scores, and stops it, so the ~6.6 GB of memory is
  used for about a minute each morning. If anything fails, Claude's order is kept.

Setup (Apple silicon, ~5 GB disk):

```bash
git clone https://github.com/jaredpalmer/kev.git vendor/kev
git -C vendor/kev checkout 5920c5fe4ca8e0970ed4209ac2c9b8e18bea5109   # the commit the 8-bit weights were built with
uv sync --project vendor/kev --extra serve
```

Set `"local_ranker": "kev"` in `config.json` (or `""` to use Claude's ranking only).

## Native app (experimental)

`app/` holds a SwiftUI menu bar app with a setup wizard (Claude Code → Canvas link → Gmail/Calendar) and a native
desktop widget, packaged as a DMG by `app/build-dmg.sh`, so classmates could use it without a terminal. I switched
back to Übersicht because macOS dims native desktop widgets whenever another window is in front, and the dimmed
widget was unreadable. It doesn't include the Kev ranking.

## Safety

The agent can only use **read-only** tools (search/read email, list calendar events). It cannot send email, create drafts, or change calendar events. Those tools are left off the allow-list in `config.json`, and Bash, file editing, and web access are explicitly blocked.

`config.json` (private Canvas link), `data/` (my tasks), and `logs/` are git-ignored.

## Challenges & limitations

### Problems I found and fixed

**1. The same data gave different lists.**
*Problem:* Claude decided what counted as "today", so identical inputs produced "0 today / 6 upcoming" on one run and
"1 today / 5 upcoming" on the next.
*Fix:* Claude now only collects tasks with their dates. Plain code (`tasks.py`) groups them by day, drops past ones,
and removes duplicates. Date math doesn't need AI.
*Still true:* which emails Claude decides are worth collecting can vary a little between runs.

**2. The local model wasn't sure of itself.**
*Problem:* asking Kev one fuzzy question ("high, medium or low?") gave only 41–61% confidence, where 33% is a guess.
*Fix:* I split it into six concrete yes/no questions ("is this an exam?", "did a professor ask?"). Kev answers
those with 53–92% confidence, and code applies my rules. The widget now shows *why*: "Exam · tomorrow · 91%".
*What testing caught:* the first wording flagged a "final project progress review" meeting as an exam (86%).
Asking "is the item itself a test, as opposed to a meeting, review or discussion?" dropped it to 7% while real
quizzes stayed at 79–91%. A rule-order bug also made an optional RSVP "high"; optional now wins over "do today".

**3. Finished assignments kept showing up.**
*Problem:* the Canvas calendar feed doesn't know what I've submitted.
*Fix:* a ✓ button on each task. Checked tasks disappear right away and stay hidden on later runs (they have a
stable id built from the Canvas/Gmail link). Undo is in the footer.
*Still true:* it's manual. The Canvas API could check submissions automatically but needs a personal access token.

### Limitations I accepted

- **Local isn't fully local.** Reading Gmail and Calendar still goes through Claude in the cloud; only the ranking
  runs on my Mac. That's a deliberate split: the cloud model reads messy email well, the local model ranks
  consistently. Fully offline would need a local model that can use tools, plus my own Google sign-in.
- **"Importance" is my opinion.** The rules are my own heuristics. They're now written as explicit, checkable rules
  in `local/kev_rank.py`, which makes them easy to change, but not objective.
- **Slow and heavy.** On an M2 with 16 GB and a nearly full disk, a morning run takes about 2 minutes (Kev ~4 s per
  task) and the model needs ~5 GB of disk. Fine for a job that runs before I'm awake, too slow for instant refresh.
- **Only runs when my Mac is on.** If the laptop is off at 7:00, it updates at the next login instead.
- **Privacy trade-off.** My email and calendar are read by an AI model every morning. I limited it to read-only
  access and a 2-day email window.

