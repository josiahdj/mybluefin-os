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

# IR camera for face scans. docs/howdy/README.md covers finding a new camera's
# link ("Switching to a Different IR Camera").
DEVICE_PATH="/dev/v4l/by-id/usb-046d_Logitech_BRIO_511030C9-if00-video-index2"
# Cameras used before. They are written as commented-out device_path lines, so
# switching back only means swapping which line is commented.
PREVIOUS_DEVICE_PATHS=(
  # iContact Camera Pro Hello (IR stream on the Realtek "Color Camera" device)
  "/dev/v4l/by-id/usb-DECXIN_iContact_Camera_Pro_Hello_Color_Camera_YHTEK-if02-video-index0"
)

# Replace the first active device_path line. An existing real device on it is
# commented out rather than dropped; the stock "none" is simply replaced.
# Previous cameras already present as comments are not added again.
awk -v new="$DEVICE_PATH" -v prev="$(printf '%s\n' "${PREVIOUS_DEVICE_PATHS[@]}")" '
  /^#[ \t]*device_path[ \t]*=/ {
    v = $0; sub(/^#[ \t]*device_path[ \t]*=[ \t]*/, "", v); sub(/[ \t]+$/, "", v); seen[v] = 1
  }
  !done && /^device_path[ \t]*=/ {
    old = $0; sub(/^device_path[ \t]*=[ \t]*/, "", old); sub(/[ \t]+$/, "", old)
    if (old != "" && old != "none" && old != new && !(old in seen)) { print "# device_path = " old; seen[old] = 1 }
    n = split(prev, p, "\n")
    for (i = 1; i <= n; i++) if (p[i] != "" && p[i] != new && !(p[i] in seen)) { print "# device_path = " p[i]; seen[p[i]] = 1 }
    print "device_path = " new
    done = 1
    next
  }
  { print }
' "$CONFIG" > "$CONFIG.new"
# Write through the original file to keep its owner, mode and SELinux label
cat "$CONFIG.new" > "$CONFIG"
rm "$CONFIG.new"

# Fail the build if upstream renamed or dropped the option
if ! grep -qxF "device_path = $DEVICE_PATH" "$CONFIG"; then
  echo "device_path not found in $CONFIG" >&2
  exit 1
fi

echo "Howdy configured"
