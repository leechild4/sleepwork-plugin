---
name: sleepwork
description: Schedule a task to run unattended on your Mac at a set time (e.g. overnight). Use when the user types /sleepwork followed by a task and a time, or says "run this while I sleep", "do this overnight", "schedule this to run at <time> with no input from me". Turns a loose request into a self-contained brief and sets up a self-cleaning local launchd one-shot that runs `claude` headless. Also handles listing and cancelling scheduled sleepwork jobs.
---

# Sleepwork — unattended scheduled local runs

The user wants to hand off a task now and have it execute later on their Mac with zero input
from them (typically overnight). This runs the full Claude Code agent **headless and local**,
so it has their files, the subscription-billing `claude` CLI, and can start/test local
servers — none of which a cloud routine (`/schedule`) can do. That is why this is local
launchd, not `/schedule`. (See the README for the full comparison of the built-in options.)

It cannot get stuck waiting on the user: headless `claude -p` has no input channel and runs
with `--permission-mode bypassPermissions`, so no permission prompt and no question can block it.

## Modes

Read the args after `/sleepwork`:
- **Create** (default): a task description, usually with a time. Build and schedule it.
- **`list`**: show scheduled jobs — `ls -1 ~/.claude/sleepwork 2>/dev/null` and
  `launchctl list | grep sleepwork`. Report slug, and whether a RESULT.md exists yet.
- **`cancel <slug>`**: `launchctl bootout gui/$(id -u)/com.claude.sleepwork-<slug>`,
  then `rm -rf ~/.claude/sleepwork/<slug> ~/Library/LaunchAgents/com.claude.sleepwork-<slug>.plist`.
- **`result <slug>`**: `cat ~/.claude/sleepwork/<slug>/RESULT.md` (fall back to tailing `run.log`).

## Create flow

1. **Parse the task and the time.** Convert the time to 24h hour + minute (e.g. "2am" -> 2 0,
   "11:30pm" -> 23 30, "tonight at 1" -> 1 0). If no time is given, ask once for it (single
   short question). launchd uses the machine's local time, so no timezone conversion is needed.

2. **Decide the working directory.** This is the folder the task operates in. Infer it from
   the task (a named project, or the current session's cwd). If genuinely ambiguous, ask once.
   It must be an existing absolute path.

3. **For any code task, EXPLORE THE TARGET NOW.** Read the key files the task will touch
   (server, the modules involved, the frontend, data shape) before writing the brief. A vague
   brief fails unattended. The brief must reference real file paths, real function names, and
   the actual patterns in the codebase. Spend real effort here — this is the make-or-break step.

4. **Write a self-contained brief** to a temp file (e.g. `/tmp/sleepwork-<slug>-brief.md`).
   The brief is the whole spec the overnight agent follows. Include, as relevant:
   - **Goal** in one or two lines.
   - **Architecture / files** it must respect, with paths and the role of each.
   - **Concrete steps** — backend, frontend, data model, in order.
   - **Constraints** — match existing code style, no new dependencies unless needed. The user's
     own global instructions (their `CLAUDE.md`) still apply automatically inside the run.
   - **Verification it must run before finishing** — explicit commands: syntax check, start the
     server in the BACKGROUND (never foreground — it would block the agent) + curl it + kill it,
     check no orphan element ids, etc. "Do not finish on a red test."
   - **Scope guards** — what NOT to touch, and "do not commit to git" unless the user wants commits.
   Do not restate the unattended rules or the result-file path — `create-job.sh` appends those
   automatically. Aim for the depth of a real implementation brief, not a one-liner.

5. **Pick a model + execution model.**
   - **Larger code tasks:** consider an orchestrator pattern — pass `opus` to `create-job.sh`
     and put an "## Execution model" block near the top of the brief instructing the run to act
     as orchestrator (plan, review, integrate, own the final end-to-end test + completion note)
     and delegate the actual coding to subagents with tight self-contained sub-briefs (split
     e.g. backend vs frontend, parallel where safe, serialise where one depends on another).
     Keep any LLM calls the app itself makes on whatever model the app specifies — the split is
     about HOW it builds, not what the app calls.
   - **Non-code or trivial tasks:** plain `sonnet`, no orchestration block. Use plain `opus`
     (no delegation) only for pure-judgement work (analysis, planning, writing) where there is
     nothing to delegate.
   - State which model + execution model you chose and why.

6. **Make a slug** — short kebab-case from the task (e.g. `landing-copy`, `api-refactor`).
   Must be unique; if the run dir already exists, add `-2`.

7. **Create and load the job:**
   ```
   ~/.claude/skills/sleepwork/create-job.sh <slug> <workdir> <hour> <minute> <model> <brief_path>
   ```
   Quote any argument containing spaces. It writes the brief + config + plist, loads the
   launchd job, and prints the fire time and file paths.

8. **Confirm back to the user** (concise, bullets): what it will do, the fire time, the model,
   and the result + log paths to check in the morning, plus the two caveats below.

## What the scheduled job does

- Fires at the set time via launchd. If the Mac is asleep at that moment, launchd runs it on
  next wake. One-shot: after it runs it removes its own launchd job and plist (a `.ran` marker
  is a second safety against double-firing).
- Runs `claude -p --permission-mode bypassPermissions --model <model>` on the brief, in the
  working dir, with `ANTHROPIC_API_KEY` stripped so it bills against the Claude Code
  subscription (not API credits).
- Everything is logged to `~/.claude/sleepwork/<slug>/run.log`. The agent writes a completion
  note to `~/.claude/sleepwork/<slug>/RESULT.md`.

## Caveats to always tell the user

- **Machine must be awake or able to wake, and ideally plugged in.** If the Mac is fully shut
  down it won't run.
- **bypassPermissions = fully unsupervised file-write + shell in the working dir.** That is the
  cost of "no input from me". The brief scopes it and forbids git commits by default, so blast
  radius is contained, but it is real. Don't point sleepwork at anything you wouldn't let an
  agent change unsupervised.

## Files in this skill
- `create-job.sh` — builds + loads one job (called per invocation).
- `run-job.sh` — generic runner the launchd job executes; do not edit per-job.
