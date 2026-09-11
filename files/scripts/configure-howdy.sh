#!/usr/bin/env bash
set -euo pipefail

echo "Configuring Howdy..."

CONFIG="/etc/howdy/config.ini"

# Announce the face scan before the camera turns on. Besides telling the user
# to look at the camera, this is what makes GNOME's polkit dialog appear during
# the scan: GNOME only opens that dialog once PAM sends a message, so without
# the notice the scan runs with nothing on screen and usually times out.
sed -i -E 's/^detection_notice\s*=.*/detection_notice = true/' "$CONFIG"

# Fail the build if upstream renamed or dropped the option
if ! grep -qx 'detection_notice = true' "$CONFIG"; then
  echo "detection_notice not found in $CONFIG" >&2
  exit 1
fi

echo "Howdy configured"
