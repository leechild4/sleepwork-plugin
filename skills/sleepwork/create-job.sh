#!/bin/zsh
# Create + load a one-shot overnight "sleepwork" job.
# Usage: create-job.sh <slug> <workdir> <hour> <minute> <model> <brief_src_path>
set -u

SKILL_DIR="${0:A:h}"

slug="${1:?slug required}"
workdir="${2:?workdir required}"
hour=$((10#${3:?hour required}))      # strip any leading zero (02 -> 2)
minute=$((10#${4:?minute required}))
model="${5:-sonnet}"
brief_src="${6:?brief source path required}"

[[ -d "$workdir" ]]    || { echo "ERROR: workdir does not exist: $workdir"; exit 1; }
[[ -f "$brief_src" ]]  || { echo "ERROR: brief not found: $brief_src"; exit 1; }
(( hour >= 0 && hour <= 23 ))   || { echo "ERROR: hour out of range: $hour"; exit 1; }
(( minute >= 0 && minute <= 59 ))|| { echo "ERROR: minute out of range: $minute"; exit 1; }

label="com.claude.sleepwork-${slug}"
run_dir="$HOME/.claude/sleepwork/${slug}"
plist="$HOME/Library/LaunchAgents/${label}.plist"

if [[ -e "$run_dir" ]]; then
  echo "ERROR: a job named '$slug' already exists at $run_dir. Pick another slug or cancel it first:"
  echo "  launchctl bootout gui/$(id -u)/$label; rm -rf '$run_dir' '$plist'"
  exit 1
fi

mkdir -p "$run_dir"
cp "$brief_src" "$run_dir/brief.md"

# Standardised unattended footer — guarantees the headless run knows the rules + where to report.
cat >> "$run_dir/brief.md" <<FOOTER

---
## Environment (auto-added by sleepwork — read this)
- Working directory: $workdir
- You are running fully headless and unattended. Nobody can answer questions. Never wait for input; make sensible decisions and proceed.
- You have full tool access (read, write, edit, run shell), auto-approved. Stay within the working directory unless the task clearly requires otherwise.
- TEST your work before finishing. Do not stop on a known-broken state. If a part cannot be made to work after a few honest attempts, leave the rest working and say so in your note.
- When finished, write a concise completion note to: $run_dir/RESULT.md
  Cover: what was done, files changed, commands/tests run and their results, anything skipped or left incomplete and why.
- Do not commit to git unless the brief above explicitly tells you to.
FOOTER

# Per-job config read by run-job.sh
cat > "$run_dir/job.env" <<ENV
LABEL="$label"
WORKDIR="$workdir"
MODEL="$model"
ENV

# launchd plist
cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$label</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/zsh</string>
        <string>$SKILL_DIR/run-job.sh</string>
        <string>$run_dir</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key><integer>$hour</integer>
        <key>Minute</key><integer>$minute</integer>
    </dict>
    <key>StandardOutPath</key><string>$run_dir/launchd.log</string>
    <key>StandardErrorPath</key><string>$run_dir/launchd.log</string>
    <key>RunAtLoad</key><false/>
</dict>
</plist>
PLIST

uid=$(id -u)
launchctl bootout "gui/$uid/$label" 2>/dev/null
launchctl bootstrap "gui/$uid" "$plist" || { echo "ERROR: failed to load launchd job"; exit 1; }

printf "OK: scheduled '%s' for %02d:%02d (model: %s)\n" "$label" "$hour" "$minute" "$model"
echo "  one-shot: runs once then removes itself (missed runs fire on next wake)"
echo "  brief:   $run_dir/brief.md"
echo "  result:  $run_dir/RESULT.md   (written when it finishes)"
echo "  log:     $run_dir/run.log"
