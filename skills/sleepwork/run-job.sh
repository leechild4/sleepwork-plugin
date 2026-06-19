#!/bin/zsh
# Generic sleepwork runner. Fired by launchd. One arg: the per-job run dir.
# Runs claude headless on the subscription (no API key), logs, self-cleans the launchd job.
set -u

RUN_DIR="${1:?usage: run-job.sh <run_dir>}"
[[ -f "$RUN_DIR/job.env" ]] || { echo "no job.env in $RUN_DIR"; exit 1; }
source "$RUN_DIR/job.env"   # sets LABEL, WORKDIR, MODEL

BRIEF="$RUN_DIR/brief.md"
LOG="$RUN_DIR/run.log"
RESULT="$RUN_DIR/RESULT.md"
MARKER="$RUN_DIR/.ran"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
UID_NUM=$(id -u)

# Idempotency: never run twice.
if [[ -f "$MARKER" ]]; then
  echo "$(date) — already ran, skipping." >> "$LOG"
  rm -f "$PLIST" 2>/dev/null
  launchctl bootout "gui/${UID_NUM}/${LABEL}" 2>/dev/null
  exit 0
fi

# Subscription billing: claude CLI must NOT see an API key.
unset ANTHROPIC_API_KEY

# launchd hands jobs a minimal PATH. Add the common install locations so `claude`
# (and node, git, etc.) resolve, then locate the binary.
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
CLAUDE="$(command -v claude || true)"
if [[ -z "$CLAUDE" ]]; then
  echo "$(date) — claude CLI not found on PATH. Set PATH in this script to where claude lives." >> "$LOG"
  touch "$MARKER"
  echo "claude CLI not found on PATH — could not run. Edit run-job.sh PATH." > "$RESULT"
  rm -f "$PLIST" 2>/dev/null
  launchctl bootout "gui/${UID_NUM}/${LABEL}" 2>/dev/null
  exit 1
fi

# launchd hands jobs a 256 soft file-descriptor limit; the claude CLI (Node) needs
# far more and crashes with "low max file descriptors". Hard limit is unlimited,
# so raise the soft limit. Step down if a value is rejected.
for fd in 1048576 262144 65536 10240; do
  ulimit -n "$fd" 2>/dev/null && break
done

cd "$WORKDIR" || { echo "$(date) — cannot cd to $WORKDIR" >> "$LOG"; touch "$MARKER"; exit 1; }

echo "==== sleepwork '$LABEL' start: $(date) (model $MODEL, wd $WORKDIR) ====" >> "$LOG"

cat "$BRIEF" | "$CLAUDE" -p \
  --model "$MODEL" \
  --permission-mode bypassPermissions \
  --output-format stream-json \
  --verbose \
  >> "$LOG" 2>&1
ec=$?

echo "==== sleepwork '$LABEL' end: $(date) (exit $ec) ====" >> "$LOG"
touch "$MARKER"
[[ -f "$RESULT" ]] || echo "Run finished (exit $ec) but the agent wrote no RESULT.md. Check run.log." > "$RESULT"

# One-shot: remove the launchd job so it cannot fire again.
# Delete the plist FIRST — `bootout` tears down this very process, so anything
# after it may not execute.
rm -f "$PLIST" 2>/dev/null
launchctl bootout "gui/${UID_NUM}/${LABEL}" 2>/dev/null
exit 0
