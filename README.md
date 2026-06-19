# sleepwork

Hand a task to Claude Code now, have it run **unattended on your own Mac** at a set time — typically overnight — with zero input from you.

```
/sleepwork rebuild the dashboard export to stream CSV instead of buffering, at 2am
```

You go to bed. At 02:00 your Mac wakes (if asleep), runs the full Claude Code agent headless against a brief built from your request, tests its own work, writes a `RESULT.md`, and deletes its own scheduled job. In the morning you read the result.

macOS only (it uses `launchd`).

---

## What it actually is

A skill is just a folder of instructions. This one teaches Claude Code to:

1. Turn your loose request into a **self-contained brief** (exploring the target files first, so the brief references real paths and functions — a vague brief fails when nobody's watching).
2. Write a **launchd one-shot** that fires at your chosen time.
3. At fire time, run `claude -p --permission-mode bypassPermissions --model <model>` on that brief, in your chosen working directory, with `ANTHROPIC_API_KEY` stripped so it bills against your **Claude Code subscription**, not API credits.
4. Log everything, write a completion note, and **remove its own job** so it can't fire twice.

Modes: create (default), `list`, `cancel <slug>`, `result <slug>`.

---

## Why this exists — it's a wrapper, and that's the point

Claude Code already ships several ways to run things on a schedule. **None of them does exactly what sleepwork does**, which is: run *locally*, with *full file access*, *unsupervised*, *without an app or session staying open*. Here's the landscape and where each one stops short:

| Option | Where it runs | Local files? | Needs app/session open? | Verdict for overnight local build/test |
|---|---|---|---|---|
| **`/schedule` → Routines** | Anthropic cloud | ❌ fresh clone, no local FS | No (survives shutdown) | ❌ Wrong machine — can't touch your files or local servers |
| **Desktop scheduled tasks** | Your Mac | ✅ full | **Yes** — Desktop app must stay open + awake | ⚠️ Closest built-in, but the open-app requirement is the friction |
| **`/loop`** | Your Mac | ✅ full | **Yes** — session/terminal must stay open | ❌ Closing the terminal kills it |
| **`CronCreate` / `ScheduleWakeup`** | Your Mac | ✅ full | **Yes** — session-scoped helpers under `/loop` | ❌ Same limit — not standalone |
| **GitHub Actions / Agent SDK** | CI runner / your orchestration | ⚠️ repo / custom | n/a | ✅ Viable but more setup; repo-driven, not "my whole machine" |
| **Headless `claude -p` + launchd** | Your Mac | ✅ full | **No** | ✅ This is what sleepwork wraps |

The genuinely native equivalent is **Desktop scheduled tasks + "keep computer awake"** — but that needs the Desktop app running the whole time. sleepwork uses the documented **headless CLI** primitive instead, scheduled at the OS level with `launchd`, so nothing has to stay open. The machine can be asleep; launchd fires the job on next wake.

So sleepwork isn't reinventing scheduling — it's a thin convenience layer over option 6 (headless + launchd) that the built-in UI options don't expose:

- builds the brief for you (explore → spec → schedule in one command),
- self-cleans the one-shot after it runs,
- strips the API key for subscription billing,
- raises the file-descriptor limit (launchd's default 256 crashes the Node-based CLI),
- and gives you `list` / `cancel` / `result` management.

---

## Install

```
/plugin marketplace add leechild4/sleepwork-plugin
/plugin install sleepwork
```

Or copy `skills/sleepwork/` into `~/.claude/skills/` manually — a skill is portable files.

### One thing to check after install

`run-job.sh` finds the `claude` binary via `PATH` (it adds `~/.local/bin`, Homebrew, and `/usr/local/bin`). If your `claude` lives somewhere else, edit the `export PATH=...` line in `skills/sleepwork/run-job.sh`. Confirm with `command -v claude`.

---

## The two caveats (it tells you these every time)

- **The Mac must be able to wake and ideally be plugged in.** Fully shut down = it won't run.
- **`bypassPermissions` means fully unsupervised file-writes and shell** in the working directory. That's the cost of "no input from me". The brief scopes the work and forbids git commits by default, so blast radius is contained — but it's real. Don't point it at anything you wouldn't let an agent change unsupervised.

---

## Files

```
skills/sleepwork/
  SKILL.md         the instructions Claude follows
  create-job.sh    builds + loads one launchd job
  run-job.sh       generic runner launchd executes; self-cleans
```

## License

Free for personal, non-commercial use only — see [LICENSE](LICENSE).
