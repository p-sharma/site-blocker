#!/bin/bash
#
# apply_schedule.sh
#
# Runs as root (via LaunchDaemon) whenever SCHEDULE_FILE changes, and
# once at boot (see com.user.schedulewatcher.plist). Regenerates the
# blocksites/unblocksites LaunchDaemons from the schedule, then sets the
# state the schedule calls for right now so changes take effect
# immediately. If the schedule is invalid, the existing daemons are
# left untouched.

set -euo pipefail

SCHEDULE_FILE="__SCHEDULE_FILE__"
STATE_FILE="/usr/local/etc/site_blocker_state"
DAEMON_DIR="/Library/LaunchDaemons"
BLOCK_LABEL="com.user.blocksites"
UNBLOCK_LABEL="com.user.unblocksites"

source /usr/local/lib/site_blocker/schedule_lib.sh

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') apply_schedule: $*"
}

# render_plist LABEL PROGRAM "WEEKDAYS" MINUTES
render_plist() {
  local label="$1" program="$2" days="$3" minutes="$4" d
  cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$label</string>
    <key>ProgramArguments</key>
    <array>
        <string>$program</string>
    </array>
    <key>StartCalendarInterval</key>
    <array>
EOF
  for d in $days; do
    cat <<EOF
        <dict>
            <key>Weekday</key>
            <integer>$d</integer>
            <key>Hour</key>
            <integer>$(( minutes / 60 ))</integer>
            <key>Minute</key>
            <integer>$(( minutes % 60 ))</integer>
        </dict>
EOF
  done
  cat <<EOF
    </array>
    <key>RunAtLoad</key>
    <false/>
</dict>
</plist>
EOF
}

# bootout can return before the job is fully gone, and an immediate
# bootstrap then fails with "Input/output error", so wait for it.
bootout_daemon() {
  local label="$1" i
  launchctl bootout "system/$label" 2>/dev/null || return 0
  for i in 1 2 3 4 5 6 7 8 9 10; do
    launchctl print "system/$label" > /dev/null 2>&1 || return 0
    sleep 0.5
  done
}

# install_daemon LABEL RENDERED_PLIST — no-op if already installed and loaded
install_daemon() {
  local label="$1" rendered="$2" dest="$DAEMON_DIR/$1.plist"
  if cmp -s "$rendered" "$dest" && launchctl print "system/$label" > /dev/null 2>&1; then
    return 0
  fi
  bootout_daemon "$label"
  install -m 644 "$rendered" "$dest"
  chown root:wheel "$dest"
  launchctl bootstrap system "$dest"
  log "loaded $label"
}

# The plist must be removed as well as booted out, or launchd would load
# it again at the next boot.
remove_daemon() {
  local label="$1"
  bootout_daemon "$label"
  rm -f "$DAEMON_DIR/$label.plist"
}

if [ ! -f "$SCHEDULE_FILE" ]; then
  log "$SCHEDULE_FILE not found, disabling schedule"
  remove_daemon "$BLOCK_LABEL"
  remove_daemon "$UNBLOCK_LABEL"
  exit 0
fi

if ! sched_parse "$SCHEDULE_FILE"; then
  log "invalid schedule, leaving current daemons in place"
  exit 1
fi

if [ "$SCHED_ENABLED" == "0" ]; then
  remove_daemon "$BLOCK_LABEL"
  remove_daemon "$UNBLOCK_LABEL"
  log "schedule disabled"
  exit 0
fi

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

render_plist "$BLOCK_LABEL" /usr/local/bin/block_sites.sh "$SCHED_DAYS" "$SCHED_BLOCK" > "$TMP_DIR/block.plist"
render_plist "$UNBLOCK_LABEL" /usr/local/bin/unblock_sites.sh "$(sched_unblock_days)" "$SCHED_UNBLOCK" > "$TMP_DIR/unblock.plist"
plutil -lint -s "$TMP_DIR/block.plist" "$TMP_DIR/unblock.plist"

install_daemon "$BLOCK_LABEL" "$TMP_DIR/block.plist"
install_daemon "$UNBLOCK_LABEL" "$TMP_DIR/unblock.plist"
log "schedule enabled: $(sched_describe)"

# Apply the state for the current moment. Only write when it differs so
# hostswatcher isn't triggered needlessly. Never create the state file
# here — it must stay user-owned so the xbar toggle can write it.
if sched_in_window_now; then
  DESIRED="block"
else
  DESIRED="unblock"
fi
if [ ! -f "$STATE_FILE" ]; then
  log "$STATE_FILE missing, not applying current state"
  exit 0
fi
CURRENT=$(tr -d '[:space:]' < "$STATE_FILE")
if [ "$CURRENT" != "$DESIRED" ]; then
  echo "$DESIRED" > "$STATE_FILE"
  log "state set to $DESIRED"
fi
