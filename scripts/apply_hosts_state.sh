#!/bin/bash
#
# apply_hosts_state.sh
#
# Runs as root (via LaunchDaemon). Reads the current desired state
# ("block" or "unblock") and the list of sites to block, then rewrites
# the managed block in /etc/hosts accordingly.
#
# This script is triggered automatically whenever STATE_FILE or
# SITES_FILE changes (see com.user.hostswatcher.plist), so it should
# never need to be run manually.

set -euo pipefail

HOSTS_FILE="/etc/hosts"
STATE_FILE="/usr/local/etc/site_blocker_state"
SITES_FILE="__SITES_FILE__"
MARKER_START="# BLOCKLIST START"
MARKER_END="# BLOCKLIST END"

STATE=$(cat "$STATE_FILE" 2>/dev/null | tr -d '[:space:]' || echo "unblock")

# Always strip any existing managed block first (idempotent)
sed -i '' "/$MARKER_START/,/$MARKER_END/d" "$HOSTS_FILE"

if [ "$STATE" == "block" ] && [ -f "$SITES_FILE" ]; then
  {
    echo "$MARKER_START"
    grep -vE '^\s*#|^\s*$' "$SITES_FILE" | while read -r site; do
      site=$(echo "$site" | tr -d '[:space:]')
      echo "127.0.0.1 $site"
    done
    echo "$MARKER_END"
  } >> "$HOSTS_FILE"
fi

dscacheutil -flushcache
killall -HUP mDNSResponder 2>/dev/null || true
