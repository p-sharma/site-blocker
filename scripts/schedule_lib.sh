#!/bin/bash
#
# schedule_lib.sh
#
# Shared parsing/validation for schedule.conf. Sourced by
# apply_schedule.sh (as root) and by set_schedule.sh and the xbar
# plugin (as the user).
#
# schedule.conf is user-editable, so it is only ever parsed line by line
# against strict patterns — never sourced or eval'd. apply_schedule.sh
# renders LaunchDaemon plists from these values as root, so everything
# set here must be a validated integer.
#
# After a successful sched_parse these globals are set:
#   SCHED_ENABLED   0 or 1
#   SCHED_BLOCK     block time, minutes since midnight
#   SCHED_UNBLOCK   unblock time, minutes since midnight
#   SCHED_DAYS      space-separated launchd weekdays, sorted, unique (0=Sun)

SCHED_DAY_NAMES=(Sun Mon Tue Wed Thu Fri Sat)

# "HH:MM" (or "H:MM") -> minutes since midnight. Returns 1 if invalid.
sched_time_to_minutes() {
  local re='^([01]?[0-9]|2[0-3]):([0-5][0-9])$'
  [[ "$1" =~ $re ]] || return 1
  echo $(( 10#${BASH_REMATCH[1]} * 60 + 10#${BASH_REMATCH[2]} ))
}

sched_minutes_to_time() {
  printf '%02d:%02d\n' $(( $1 / 60 )) $(( $1 % 60 ))
}

# "5,1,3,1" -> "1 3 5". Returns 1 if invalid.
sched_normalize_days() {
  local re='^[0-6](,[0-6])*$'
  [[ "$1" =~ $re ]] || return 1
  echo "$1" | tr ',' '\n' | sort -nu | tr '\n' ' ' | sed 's/ $//'
}

sched_parse() {
  local file="$1" line key value
  local enabled="" block="" unblock="" days=""
  local re='^([a-z]+)=(.*)$'

  if [ ! -f "$file" ]; then
    echo "schedule file not found: $file" >&2
    return 1
  fi

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    line=$(echo "$line" | tr -d '[:space:]')
    [ -z "$line" ] && continue

    if ! [[ "$line" =~ $re ]]; then
      echo "invalid line in $file: $line" >&2
      return 1
    fi
    key="${BASH_REMATCH[1]}"
    value="${BASH_REMATCH[2]}"

    case "$key" in
      enabled)
        if [ "$value" != "0" ] && [ "$value" != "1" ]; then
          echo "invalid enabled value (expected 0 or 1): $value" >&2
          return 1
        fi
        enabled="$value"
        ;;
      block)
        block=$(sched_time_to_minutes "$value") || { echo "invalid block time: $value" >&2; return 1; }
        ;;
      unblock)
        unblock=$(sched_time_to_minutes "$value") || { echo "invalid unblock time: $value" >&2; return 1; }
        ;;
      days)
        days=$(sched_normalize_days "$value") || { echo "invalid days (expected e.g. 1,2,3,4,5): $value" >&2; return 1; }
        ;;
      *)
        echo "unknown key in $file: $key" >&2
        return 1
        ;;
    esac
  done < "$file"

  if [ -z "$enabled" ] || [ -z "$block" ] || [ -z "$unblock" ] || [ -z "$days" ]; then
    echo "schedule must set enabled, block, unblock and days" >&2
    return 1
  fi
  if [ "$block" -eq "$unblock" ]; then
    echo "block and unblock times must differ" >&2
    return 1
  fi

  SCHED_ENABLED="$enabled"
  SCHED_BLOCK="$block"
  SCHED_UNBLOCK="$unblock"
  SCHED_DAYS="$days"
}

sched_day_selected() {
  case " $SCHED_DAYS " in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
}

# Weekdays the unblock event fires on. For an overnight window (unblock
# earlier than block) the unblock lands on the following day.
sched_unblock_days() {
  local d out=""
  if [ "$SCHED_UNBLOCK" -gt "$SCHED_BLOCK" ]; then
    echo "$SCHED_DAYS"
    return
  fi
  for d in $SCHED_DAYS; do
    out="$out $(( (d + 1) % 7 ))"
  done
  echo $out | tr ' ' '\n' | sort -nu | tr '\n' ' ' | sed 's/ $//'
}

# sched_in_window WEEKDAY MINUTES — true if that moment falls inside a
# block window. An overnight window belongs to the day it starts on.
sched_in_window() {
  local today="$1" now="$2" yesterday=$(( ($1 + 6) % 7 ))
  if [ "$SCHED_BLOCK" -lt "$SCHED_UNBLOCK" ]; then
    sched_day_selected "$today" && [ "$now" -ge "$SCHED_BLOCK" ] && [ "$now" -lt "$SCHED_UNBLOCK" ]
  else
    { sched_day_selected "$today" && [ "$now" -ge "$SCHED_BLOCK" ]; } ||
      { sched_day_selected "$yesterday" && [ "$now" -lt "$SCHED_UNBLOCK" ]; }
  fi
}

sched_in_window_now() {
  local wday hour minute
  read -r wday hour minute <<< "$(date '+%w %H %M')"
  sched_in_window "$wday" $(( 10#$hour * 60 + 10#$minute ))
}

# Human-readable summary, e.g. "Weekdays 09:00-18:00"
sched_describe() {
  local days="" d
  case "$SCHED_DAYS" in
    "1 2 3 4 5")     days="Weekdays" ;;
    "0 1 2 3 4 5 6") days="Every day" ;;
    "0 6")           days="Weekends" ;;
    *)
      for d in $SCHED_DAYS; do
        days="${days:+$days,}${SCHED_DAY_NAMES[$d]}"
      done
      ;;
  esac
  echo "$days $(sched_minutes_to_time "$SCHED_BLOCK")-$(sched_minutes_to_time "$SCHED_UNBLOCK")"
}

# sched_write FILE ENABLED BLOCK UNBLOCK DAYS
# Writes a new schedule atomically, but only if it parses — the same
# validation the root side applies.
sched_write() {
  local file="$1" tmp
  tmp=$(mktemp "$(dirname "$file")/.schedule.conf.XXXXXX") || return 1
  cat > "$tmp" <<EOF
# Site Blocker schedule. Managed by the xbar plugin; safe to edit by hand.
# Times are 24h HH:MM. days uses launchd weekday numbers: 0=Sun 1=Mon ... 6=Sat
# If unblock is earlier than block, the window runs overnight.
enabled=$2
block=$3
unblock=$4
days=$5
EOF
  if ! sched_parse "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  chmod 644 "$tmp"
  mv -f "$tmp" "$file"
}
