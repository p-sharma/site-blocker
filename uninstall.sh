#!/bin/bash
#
# uninstall.sh — removes all Site Blocker components from this Mac.
# Does NOT delete your ~/SiteBlocker/ (block list and schedule),
# unless you pass --purge.

set -euo pipefail

# schedulewatcher goes first so it can't regenerate the schedule daemons
# while they're being removed.
echo "==> Unloading and removing LaunchDaemons (requires sudo)"
for plist in com.user.schedulewatcher com.user.hostswatcher com.user.blocksites com.user.unblocksites; do
  sudo launchctl bootout "system/${plist}" 2>/dev/null || true
  sudo rm -f "/Library/LaunchDaemons/${plist}.plist"
done

echo "==> Removing scripts from /usr/local/bin and /usr/local/lib/site_blocker"
sudo rm -f /usr/local/bin/block_sites.sh /usr/local/bin/unblock_sites.sh /usr/local/bin/apply_hosts_state.sh \
  /usr/local/bin/apply_schedule.sh /usr/local/bin/set_schedule.sh
sudo rm -rf /usr/local/lib/site_blocker

echo "==> Clearing any active block from /etc/hosts"
sudo sed -i '' "/# BLOCKLIST START/,/# BLOCKLIST END/d" /etc/hosts
dscacheutil -flushcache
sudo killall -HUP mDNSResponder 2>/dev/null || true

echo "==> Removing state file and log"
sudo rm -f /usr/local/etc/site_blocker_state /var/log/site_blocker.log

XBAR_PLUGIN="$HOME/Library/Application Support/xbar/plugins/site_blocker.10s.sh"
if [ -f "$XBAR_PLUGIN" ]; then
  echo "==> Removing xbar plugin"
  rm -f "$XBAR_PLUGIN"
fi

if [ "${1:-}" == "--purge" ]; then
  echo "==> --purge passed, removing ~/SiteBlocker as well"
  rm -rf "$HOME/SiteBlocker"
else
  echo "==> Leaving ~/SiteBlocker/ (block list and schedule) in place (pass --purge to remove it too)"
fi

echo "==> Uninstall complete."
