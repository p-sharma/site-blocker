#!/bin/bash
#
# install.sh — sets up Site Blocker on this Mac.
#
# What it does:
#   1. Copies blocked_sites.txt to ~/SiteBlocker/blocked_sites.txt
#      (only if it doesn't already exist there, so you won't clobber edits)
#   2. Installs the two helper scripts + the watcher script to /usr/local/bin
#   3. Installs the LaunchDaemon plists to /Library/LaunchDaemons,
#      substituting your actual home directory path
#   4. Creates the state file
#   5. Loads the LaunchDaemons
#   6. Symlinks the xbar plugin into your xbar plugins folder (if xbar is installed)
#
# Safe to re-run.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SITES_DIR="$HOME/SiteBlocker"
SITES_FILE="$SITES_DIR/blocked_sites.txt"
STATE_FILE="/usr/local/etc/site_blocker_state"

echo "==> Installing Site Blocker for $(whoami)"
echo "    Home: $HOME"
echo "    Sites file will live at: $SITES_FILE"
echo

# 1. Sites config
mkdir -p "$SITES_DIR"
if [ -f "$SITES_FILE" ]; then
  echo "==> $SITES_FILE already exists, leaving it alone"
else
  cp "$REPO_DIR/config/blocked_sites.txt" "$SITES_FILE"
  echo "==> Copied default blocked_sites.txt to $SITES_FILE"
fi

# 2. Helper scripts -> /usr/local/bin
echo "==> Installing scripts to /usr/local/bin (requires sudo)"
sudo install -m 755 "$REPO_DIR/scripts/block_sites.sh" /usr/local/bin/block_sites.sh
sudo install -m 755 "$REPO_DIR/scripts/unblock_sites.sh" /usr/local/bin/unblock_sites.sh

# apply_hosts_state.sh needs SITES_FILE substituted before install
TMP_APPLY=$(mktemp)
sed "s|__SITES_FILE__|$SITES_FILE|g" "$REPO_DIR/scripts/apply_hosts_state.sh" > "$TMP_APPLY"
sudo install -m 755 "$TMP_APPLY" /usr/local/bin/apply_hosts_state.sh
rm -f "$TMP_APPLY"

# 3. State file
echo "==> Creating state file at $STATE_FILE"
sudo mkdir -p /usr/local/etc
if [ ! -f "$STATE_FILE" ]; then
  sudo touch "$STATE_FILE"
  echo "unblock" | sudo tee "$STATE_FILE" > /dev/null
fi
sudo chown "$(whoami):staff" "$STATE_FILE"

# 4. LaunchDaemons -> /Library/LaunchDaemons (substituting paths)
echo "==> Installing LaunchDaemons (requires sudo)"
for plist in com.user.hostswatcher com.user.blocksites com.user.unblocksites; do
  TMP_PLIST=$(mktemp)
  sed "s|__SITES_FILE__|$SITES_FILE|g" "$REPO_DIR/launchdaemons/${plist}.plist" > "$TMP_PLIST"
  sudo install -m 644 "$TMP_PLIST" "/Library/LaunchDaemons/${plist}.plist"
  sudo chown root:wheel "/Library/LaunchDaemons/${plist}.plist"
  rm -f "$TMP_PLIST"

  # Unload first in case this is a re-run, then load fresh
  sudo launchctl unload "/Library/LaunchDaemons/${plist}.plist" 2>/dev/null || true
  sudo launchctl load "/Library/LaunchDaemons/${plist}.plist"
  echo "    Loaded ${plist}"
done

# 5. xbar plugin
XBAR_PLUGINS_DIR="$HOME/Library/Application Support/xbar/plugins"
if [ -d "$XBAR_PLUGINS_DIR" ]; then
  TMP_XBAR=$(mktemp)
  sed "s|__SITES_FILE__|$SITES_FILE|g" "$REPO_DIR/xbar-plugin/site_blocker.10s.sh" > "$TMP_XBAR"
  install -m 755 "$TMP_XBAR" "$XBAR_PLUGINS_DIR/site_blocker.10s.sh"
  rm -f "$TMP_XBAR"
  echo "==> Installed xbar plugin. Open xbar and Refresh All to see it."
else
  echo "==> xbar plugins folder not found — install xbar first (brew install --cask xbar),"
  echo "    then re-run this script, or manually copy xbar-plugin/site_blocker.10s.sh there"
  echo "    (replacing __SITES_FILE__ with: $SITES_FILE)"
fi

echo
echo "==> Done. Edit your block list anytime at: $SITES_FILE"
echo "    Toggle blocking from the xbar menu, or manually with:"
echo "      echo block   > $STATE_FILE"
echo "      echo unblock > $STATE_FILE"
