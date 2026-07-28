#!/bin/bash
#
# xbar plugin — shows Blocked/Unblocked in the menu bar and lets you
# toggle by clicking. Refreshes every 10 seconds (see filename).
#
# Install: symlink or copy this file into your xbar plugins folder:
#   ~/Library/Application Support/xbar/plugins/

STATE_FILE="/usr/local/etc/site_blocker_state"
SITES_FILE="__SITES_FILE__"

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
echo "Edit blocked sites | bash='/usr/bin/open' param1='-e' param2='$SITES_FILE' terminal=false"
echo "Refresh | refresh=true"
