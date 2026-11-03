#!/bin/bash
#
# install.sh — sets up Site Blocker on this Mac.
#
# What it does:
#   1. Copies blocked_sites.txt and schedule.conf to ~/SiteBlocker/
#      (only if they don't already exist there, so you won't clobber edits)
#   2. Installs the helper scripts to /usr/local/bin and the shared
#      schedule library to /usr/local/lib/site_blocker
#   3. Creates the state file
#   4. Installs the hostswatcher and schedulewatcher LaunchDaemons to
#      /Library/LaunchDaemons, substituting your actual home directory path.
#      The block/unblock schedule daemons are generated from schedule.conf
#      by apply_schedule.sh, not installed from this repo.
#   5. Loads the LaunchDaemons
#   6. Installs the xbar plugin into your xbar plugins folder (if xbar is installed)
#
# Safe to re-run.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SITES_DIR="$HOME/SiteBlocker"
SITES_FILE="$SITES_DIR/blocked_sites.txt"
SCHEDULE_FILE="$SITES_DIR/schedule.conf"
STATE_FILE="/usr/local/etc/site_blocker_state"
LIB_DIR="/usr/local/lib/site_blocker"

# Substitutes path placeholders in a repo file, writing to stdout
render() {
  sed -e "s|__SITES_FILE__|$SITES_FILE|g" -e "s|__SCHEDULE_FILE__|$SCHEDULE_FILE|g" "$1"
}

# bootout can return before the job is fully gone, and an immediate
# bootstrap then fails with "Input/output error", so wait for it.
reload_daemon() {
  local label="$1" i
  if sudo launchctl bootout "system/$label" 2>/dev/null; then
    for i in 1 2 3 4 5 6 7 8 9 10; do
      sudo launchctl print "system/$label" > /dev/null 2>&1 || break
      sleep 0.5
    done
  fi
  sudo launchctl bootstrap system "/Library/LaunchDaemons/${label}.plist"
}

echo "==> Installing Site Blocker for $(whoami)"
echo "    Home: $HOME"
echo "    Sites file will live at: $SITES_FILE"
echo "    Schedule file will live at: $SCHEDULE_FILE"
echo

# 1. User config
mkdir -p "$SITES_DIR"
if [ -f "$SITES_FILE" ]; then
  echo "==> $SITES_FILE already exists, leaving it alone"
else
  cp "$REPO_DIR/config/blocked_sites.txt" "$SITES_FILE"
  echo "==> Copied default blocked_sites.txt to $SITES_FILE"
fi
if [ -f "$SCHEDULE_FILE" ]; then
  echo "==> $SCHEDULE_FILE already exists, leaving it alone"
else
  cp "$REPO_DIR/config/schedule.conf" "$SCHEDULE_FILE"
  echo "==> Copied default schedule.conf to $SCHEDULE_FILE (schedule is disabled by default)"
fi

# 2. Helper scripts -> /usr/local/bin, schedule library -> /usr/local/lib
echo "==> Installing scripts to /usr/local/bin (requires sudo)"
sudo install -d -m 755 "$LIB_DIR"
sudo install -m 644 "$REPO_DIR/scripts/schedule_lib.sh" "$LIB_DIR/schedule_lib.sh"
sudo install -m 755 "$REPO_DIR/scripts/block_sites.sh" /usr/local/bin/block_sites.sh
sudo install -m 755 "$REPO_DIR/scripts/unblock_sites.sh" /usr/local/bin/unblock_sites.sh

for script in apply_hosts_state.sh apply_schedule.sh set_schedule.sh; do
  TMP_SCRIPT=$(mktemp)
  render "$REPO_DIR/scripts/$script" > "$TMP_SCRIPT"
  sudo install -m 755 "$TMP_SCRIPT" "/usr/local/bin/$script"
  rm -f "$TMP_SCRIPT"
done

# 3. State file
echo "==> Creating state file at $STATE_FILE"
sudo mkdir -p /usr/local/etc
if [ ! -f "$STATE_FILE" ]; then
  sudo touch "$STATE_FILE"
  echo "unblock" | sudo tee "$STATE_FILE" > /dev/null
fi
sudo chown "$(whoami):staff" "$STATE_FILE"

# 4. LaunchDaemons -> /Library/LaunchDaemons (substituting paths)
#    schedulewatcher runs at load, so it immediately generates (or, if the
#    schedule is disabled, removes) the blocksites/unblocksites daemons —
#    including static ones left behind by older versions of this installer.
echo "==> Installing LaunchDaemons (requires sudo)"
for plist in com.user.hostswatcher com.user.schedulewatcher; do
  TMP_PLIST=$(mktemp)
  render "$REPO_DIR/launchdaemons/${plist}.plist" > "$TMP_PLIST"
  sudo install -m 644 "$TMP_PLIST" "/Library/LaunchDaemons/${plist}.plist"
  sudo chown root:wheel "/Library/LaunchDaemons/${plist}.plist"
  rm -f "$TMP_PLIST"

  reload_daemon "$plist"
  echo "    Loaded ${plist}"
done

# 5. xbar plugin
XBAR_PLUGINS_DIR="$HOME/Library/Application Support/xbar/plugins"
if [ -d "$XBAR_PLUGINS_DIR" ]; then
  TMP_XBAR=$(mktemp)
  render "$REPO_DIR/xbar-plugin/site_blocker.10s.sh" > "$TMP_XBAR"
  install -m 755 "$TMP_XBAR" "$XBAR_PLUGINS_DIR/site_blocker.10s.sh"
  rm -f "$TMP_XBAR"
  echo "==> Installed xbar plugin. Open xbar and Refresh All to see it."
else
  echo "==> xbar plugins folder not found — install xbar first (brew install --cask xbar),"
  echo "    then re-run this script, or manually copy xbar-plugin/site_blocker.10s.sh there"
  echo "    (replacing __SITES_FILE__ with: $SITES_FILE"
  echo "     and __SCHEDULE_FILE__ with: $SCHEDULE_FILE)"
fi

echo
echo "==> Done. Edit your block list anytime at: $SITES_FILE"
echo "    Set a schedule from the xbar Schedule menu, or edit: $SCHEDULE_FILE"
echo "    Toggle blocking from the xbar menu, or manually with:"
echo "      echo block   > $STATE_FILE"
echo "      echo unblock > $STATE_FILE"
