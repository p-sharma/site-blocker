# Site Blocker (macOS)

A tiny, transparent website blocker for macOS that:

- Blocks sites by adding entries to `/etc/hosts`
- Reads the block list from a plain text file you can edit anytime
- Can be toggled on/off from the menu bar via [xbar](https://xbarapp.com)
- Can optionally auto-block/unblock on a schedule (e.g. block during work hours)

No third-party service, no daemon phoning home — just `launchd`, `/etc/hosts`, and a text file.

## How it works

```
┌─────────────────────┐     writes      ┌──────────────────────────┐
│  xbar menu bar item  │ ──────────────► │ site_blocker_state file  │
│  (click to toggle)   │                 │ (just contains "block"   │
└─────────────────────┘                  │  or "unblock")           │
                                          └────────────┬─────────────┘
                                                        │ watched by
                                                        ▼
┌─────────────────────┐     reads       ┌──────────────────────────┐
│ blocked_sites.txt    │ ◄────────────── │  hostswatcher LaunchDaemon│
│ (~/SiteBlocker/)      │                 │  (runs as root)          │
└─────────────────────┘                  └────────────┬─────────────┘
                                                        │ rewrites
                                                        ▼
                                          ┌──────────────────────────┐
                                          │       /etc/hosts         │
                                          └──────────────────────────┘
```

Your user account only ever writes to files it owns (`site_blocker_state`,
`blocked_sites.txt`). A root-owned `LaunchDaemon` watches both files and
is the only thing that actually edits `/etc/hosts`. That's why toggling
from the menu bar never prompts for a password.

## Requirements

- macOS
- [Homebrew](https://brew.sh) (to install xbar)
- [xbar](https://xbarapp.com) — `brew install --cask xbar`

## Install

```bash
git clone https://github.com/YOUR_USERNAME/site-blocker.git
cd site-blocker
chmod +x install.sh uninstall.sh
./install.sh
```

The installer will:

1. Create `~/SiteBlocker/blocked_sites.txt` (won't overwrite it if it already exists)
2. Install helper scripts to `/usr/local/bin` (asks for `sudo`)
3. Install and load three `LaunchDaemons` to `/Library/LaunchDaemons` (asks for `sudo`)
4. Install the xbar plugin, if xbar is already installed

## Usage

- Click the xbar menu bar icon (🚫 Blocked / 🌐 Unblocked) to toggle
- Click **Edit blocked sites** in the menu to open your list in a text editor
- Or edit directly: `~/SiteBlocker/blocked_sites.txt` — one domain per line, `#` for comments

Changes to the list take effect immediately if blocking is currently active — no toggle needed.

### Manual toggle (without xbar)

```bash
echo block   > /usr/local/etc/site_blocker_state
echo unblock > /usr/local/etc/site_blocker_state
```

### Optional: scheduled auto block/unblock

Two additional LaunchDaemons are installed but **disabled by default logic** —
they just flip the state file at fixed times. Edit the times in:

- `launchdaemons/com.user.blocksites.plist` (default: 9:00 AM → block)
- `launchdaemons/com.user.unblocksites.plist` (default: 6:00 PM → unblock)

then re-run `./install.sh` to reinstall them with your new times.

## Uninstall

```bash
./uninstall.sh          # removes daemons/scripts, keeps your block list
./uninstall.sh --purge  # also deletes ~/SiteBlocker
```

## Limitations

- Only blocks plain-domain DNS resolution — subdomains not listed
  explicitly (e.g. `old.reddit.com`) won't be blocked. Add every
  subdomain you care about to the list.
- Browsers using DNS-over-HTTPS (DoH) — Firefox and Chrome, in some
  configurations — can bypass `/etc/hosts` entirely. Disable DoH in
  browser settings if you need this to be airtight.
- This is a friction tool, not a lock. Anyone with terminal access
  (i.e. you) can toggle it off in one click. For a harder-to-bypass
  version, look at dedicated apps like Cold Turkey or Freedom.

## License

MIT — do whatever you want with it.
