#!/bin/bash
#
# xbar plugin — shows Blocked/Unblocked in the menu bar and lets you
# toggle by clicking. Refreshes every 10 seconds (see filename).
#
# Install: symlink or copy this file into your xbar plugins folder:
#   ~/Library/Application Support/xbar/plugins/

STATE_FILE="/usr/local/etc/site_blocker_state"
SITES_FILE="__SITES_FILE__"
SCHEDULE_FILE="__SCHEDULE_FILE__"
SET_SCHEDULE="/usr/local/bin/set_schedule.sh"
SCHEDULE_LIB="/usr/local/lib/site_blocker/schedule_lib.sh"

STATE=$(cat "$STATE_FILE" 2>/dev/null | tr -d '[:space:]')

if [ "$STATE" == "block" ]; then
  echo "🚫 Blocked"
else
  echo "🌐 Unblocked"
fi

echo "---"

if [ "$STATE" == "block" ]; then
  echo "Unblock sites | bash='/bin/bash' param1=-c param2='echo unblock > $STATE_FILE' terminal=false refresh=true"
else
  echo "Block sites | bash='/bin/bash' param1=-c param2='echo block > $STATE_FILE' terminal=false refresh=true"
fi

echo "---"

# Schedule submenu. Each action only writes the schedule file; the
# schedulewatcher LaunchDaemon applies it as root a few seconds later.
echo "Schedule"
if [ -f "$SCHEDULE_LIB" ] && source "$SCHEDULE_LIB" && sched_parse "$SCHEDULE_FILE" 2>/dev/null; then
  if [ "$SCHED_ENABLED" == "1" ]; then
    echo "--$(sched_describe) (on)"
    echo "--Disable schedule | bash='$SET_SCHEDULE' param1=disable terminal=false refresh=true"
  else
    echo "--$(sched_describe) (off)"
    echo "--Enable schedule | bash='$SET_SCHEDULE' param1=enable terminal=false refresh=true"
  fi
else
  echo "--No valid schedule"
fi
echo "-----"
echo "--Weekdays 09:00-18:00 | bash='$SET_SCHEDULE' param1=preset param2=09:00 param3=18:00 param4=1,2,3,4,5 terminal=false refresh=true"
echo "--Weekdays 09:00-17:00 | bash='$SET_SCHEDULE' param1=preset param2=09:00 param3=17:00 param4=1,2,3,4,5 terminal=false refresh=true"
echo "--Every day 09:00-18:00 | bash='$SET_SCHEDULE' param1=preset param2=09:00 param3=18:00 param4=0,1,2,3,4,5,6 terminal=false refresh=true"
echo "--Custom... | bash='$SET_SCHEDULE' param1=custom terminal=false refresh=true"

echo "---"
echo "Edit blocked sites | bash='/usr/bin/open' param1='-e' param2='$SITES_FILE' terminal=false"
echo "Refresh | refresh=true"
