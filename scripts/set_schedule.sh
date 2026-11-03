#!/bin/bash
#
# set_schedule.sh
#
# User-side helper behind the xbar Schedule menu. Only writes
# SCHEDULE_FILE — the schedulewatcher LaunchDaemon picks up the change
# and regenerates the block/unblock LaunchDaemons as root.
#
# Usage:
#   set_schedule.sh enable
#   set_schedule.sh disable
#   set_schedule.sh preset HH:MM HH:MM DAYS   (DAYS e.g. 1,2,3,4,5; 0=Sun)
#   set_schedule.sh custom                    (prompts via dialogs)

set -euo pipefail

SCHEDULE_FILE="__SCHEDULE_FILE__"

source /usr/local/lib/site_blocker/schedule_lib.sh

FULL_DAY_NAMES=(Sunday Monday Tuesday Wednesday Thursday Friday Saturday)

# Sets CUR_BLOCK, CUR_UNBLOCK (HH:MM) and CUR_DAYS (comma list) from the
# current schedule, falling back to weekdays 09:00-18:00.
load_current() {
  if sched_parse "$SCHEDULE_FILE" 2> /dev/null; then
    CUR_BLOCK=$(sched_minutes_to_time "$SCHED_BLOCK")
    CUR_UNBLOCK=$(sched_minutes_to_time "$SCHED_UNBLOCK")
    CUR_DAYS=$(echo "$SCHED_DAYS" | tr ' ' ',')
  else
    CUR_BLOCK="09:00"
    CUR_UNBLOCK="18:00"
    CUR_DAYS="1,2,3,4,5"
  fi
}

# Values are passed to AppleScript via argv, never interpolated into it.
alert() {
  osascript -e 'on run argv' \
    -e 'display alert "Site Blocker" message (item 1 of argv) as warning' \
    -e 'end run' "$1" > /dev/null
}

ask_time() {
  osascript -e 'on run argv' \
    -e 'text returned of (display dialog (item 1 of argv) default answer (item 2 of argv) with title "Site Blocker Schedule")' \
    -e 'end run' "$1" "$2"
}

# ask_days "1,2,3" — prints selected day names, one per line
ask_days() {
  local defaults=() d
  for d in $(echo "$1" | tr ',' ' '); do
    defaults+=("${FULL_DAY_NAMES[$d]}")
  done
  osascript -e 'on run argv' \
    -e 'set picked to choose from list {"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"} with title "Site Blocker Schedule" with prompt "Block on these days:" default items argv with multiple selections allowed' \
    -e 'if picked is false then error number -128' \
    -e 'set AppleScript'"'"'s text item delimiters to linefeed' \
    -e 'return picked as text' \
    -e 'end run' ${defaults[@]+"${defaults[@]}"}
}

# save ENABLED BLOCK UNBLOCK DAYS
save() {
  local err
  if ! err=$(sched_write "$SCHEDULE_FILE" "$@" 2>&1); then
    alert "Schedule not saved: $err"
    exit 1
  fi
}

custom() {
  local block unblock names name days="" i
  load_current

  # Cancelling any dialog makes osascript exit non-zero; treat as abort.
  block=$(ask_time "Start blocking at (24h HH:MM):" "$CUR_BLOCK") || exit 0
  unblock=$(ask_time "Stop blocking at (24h HH:MM):" "$CUR_UNBLOCK") || exit 0
  names=$(ask_days "$CUR_DAYS") || exit 0

  while IFS= read -r name; do
    for i in 0 1 2 3 4 5 6; do
      if [ "${FULL_DAY_NAMES[$i]}" == "$name" ]; then
        days="${days:+$days,}$i"
      fi
    done
  done <<< "$names"

  save 1 "$(echo "$block" | tr -d '[:space:]')" "$(echo "$unblock" | tr -d '[:space:]')" "$days"
}

case "${1:-}" in
  enable)
    load_current
    save 1 "$CUR_BLOCK" "$CUR_UNBLOCK" "$CUR_DAYS"
    ;;
  disable)
    load_current
    save 0 "$CUR_BLOCK" "$CUR_UNBLOCK" "$CUR_DAYS"
    ;;
  preset)
    [ $# -eq 4 ] || { echo "usage: $0 preset HH:MM HH:MM DAYS" >&2; exit 2; }
    save 1 "$2" "$3" "$4"
    ;;
  custom)
    custom
    ;;
  *)
    echo "usage: $0 enable|disable|preset HH:MM HH:MM DAYS|custom" >&2
    exit 2
    ;;
esac
