#!/bin/sh

set -x

osascript -e 'tell application "WireGuardMultiTunnel" to quit' 2>/dev/null || true
osascript -e 'tell application "WireGuardStatusbar" to quit' 2>/dev/null || true

# Legacy privileged helpers (older bundle IDs / install paths)
for label in \
  nl.ijohan.WireGuardStatusbarHelper \
  WireGuardStatusbarHelper \
  WireGuardMultiTunnelHelper
do
  sudo launchctl bootout system "/Library/LaunchDaemons/${label}.plist" 2>/dev/null || \
    sudo launchctl unload "/Library/LaunchDaemons/${label}.plist" 2>/dev/null || true
  sudo rm -f "/Library/LaunchDaemons/${label}.plist"
  sudo rm -f "/Library/PrivilegedHelperTools/${label}"
done

# Remove applications (current and former names)
sudo rm -rf \
  /Applications/WireGuardMultiTunnel.app \
  /Applications/WireGuardStatusbar.app

# User settings (current and former domains)
for domain in WireGuardMultiTunnel WireGuardStatusbar WireGuardMultiTunnelHelper WireGuardStatusbarHelper
do
  defaults delete "$domain" 2>/dev/null || true
  sudo defaults delete "$domain" 2>/dev/null || true
done

exit 0
