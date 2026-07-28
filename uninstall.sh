#!/bin/bash
#
# uninstall.sh — removes all Site Blocker components from this Mac.
# Does NOT delete your ~/SiteBlocker/blocked_sites.txt (your data),
# unless you pass --purge.

set -euo pipefail

echo "==> Unloading and removing LaunchDaemons (requires sudo)"
for plist in com.user.hostswatcher com.user.blocksites com.user.unblocksites; do
  sudo launchctl unload "/Library/LaunchDaemons/${plist}.plist" 2>/dev/null || true
  sudo rm -f "/Library/LaunchDaemons/${plist}.plist"
done

echo "==> Removing scripts from /usr/local/bin"
sudo rm -f /usr/local/bin/block_sites.sh /usr/local/bin/unblock_sites.sh /usr/local/bin/apply_hosts_state.sh

echo "==> Clearing any active block from /etc/hosts"
sudo sed -i '' "/# BLOCKLIST START/,/# BLOCKLIST END/d" /etc/hosts
dscacheutil -flushcache
sudo killall -HUP mDNSResponder 2>/dev/null || true

echo "==> Removing state file"
sudo rm -f /usr/local/etc/site_blocker_state

XBAR_PLUGIN="$HOME/Library/Application Support/xbar/plugins/site_blocker.10s.sh"
if [ -f "$XBAR_PLUGIN" ]; then
  echo "==> Removing xbar plugin"
  rm -f "$XBAR_PLUGIN"
fi

if [ "${1:-}" == "--purge" ]; then
  echo "==> --purge passed, removing ~/SiteBlocker as well"
  rm -rf "$HOME/SiteBlocker"
else
  echo "==> Leaving ~/SiteBlocker/blocked_sites.txt in place (pass --purge to remove it too)"
fi

echo "==> Uninstall complete."
