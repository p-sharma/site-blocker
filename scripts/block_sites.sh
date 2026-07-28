#!/bin/bash
# Sets state to "block". Used by the scheduled LaunchDaemon and/or
# can be run manually. Does NOT touch /etc/hosts directly — the
# hostswatcher LaunchDaemon picks up the change and applies it as root.
echo "block" > /usr/local/etc/site_blocker_state
