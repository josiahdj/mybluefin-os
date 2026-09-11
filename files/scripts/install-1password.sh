#!/usr/bin/env bash
set -euo pipefail

echo "Installing 1Password..."

# Can be "beta" or "stable"
RELEASE_CHANNEL="${ONEPASSWORD_RELEASE_CHANNEL:-stable}"

# Must be over 1000
GID_ONEPASSWORD="${GID_ONEPASSWORD:-1500}"
GID_ONEPASSWORDCLI="${GID_ONEPASSWORDCLI:-1600}"

mkdir -p /var/opt

# Setup repo
cat << EOF > /etc/yum.repos.d/1password.repo
[1password]
name=1Password ${RELEASE_CHANNEL^} Channel
baseurl=https://downloads.1password.com/linux/rpm/${RELEASE_CHANNEL}/\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://downloads.1password.com/linux/keys/1password.asc
EOF

rpm --import https://downloads.1password.com/linux/keys/1password.asc

rpm-ostree install 1password 1password-cli

# Clean up the yum repo (updates are baked into new images)
rm -f /etc/yum.repos.d/1password.repo

# chrome-sandbox requires the setuid bit to be specifically set.
# See https://github.com/electron/electron/issues/17972
chmod 4755 /opt/1Password/chrome-sandbox

# BrowserSupport binary needs setgid. This gives no extra permissions to the
# binary, it only hardens it against environmental tampering.
BROWSER_SUPPORT_PATH="/opt/1Password/1Password-BrowserSupport"
chgrp "${GID_ONEPASSWORD}" "${BROWSER_SUPPORT_PATH}"
chmod g+s "${BROWSER_SUPPORT_PATH}"

# onepassword-cli also needs its own group and setgid, like the other helpers.
chgrp "${GID_ONEPASSWORDCLI}" /usr/bin/op
chmod g+s /usr/bin/op

# NOTE: unlike upstream blue-build's bling "1password" installer, we
# intentionally do NOT manually run `xdg-desktop-menu install .../1password.desktop`
# here. As of 1password-8.12.36, the RPM already ships the desktop entries and
# icons directly as regular package files:
#   /usr/share/applications/1password.desktop
#   /usr/share/applications/com.onepassword.OnePassword.desktop
#   /usr/share/icons/hicolor/*/apps/1password.png
# The old /opt/1Password/resources/1password.desktop path bling relies on was
# renamed upstream to com.onepassword.OnePassword.desktop, which breaks
# bling's hardcoded xdg-desktop-menu call. Since the RPM already installs the
# menu entry and icons for us, that step is unnecessary here.

# Dynamically create the required groups via sysusers.d
# and set the GID based on the files we just chgrp'd.
# (Groups can't be created directly during the ostree build, since they'd
# disappear from the running system.)
cat >/usr/lib/sysusers.d/onepassword.conf <<EOF
g onepassword ${GID_ONEPASSWORD}
EOF
cat >/usr/lib/sysusers.d/onepassword-cli.conf <<EOF
g onepassword-cli ${GID_ONEPASSWORDCLI}
EOF

# Remove the sysusers.d entries created by the onepassword RPMs.
# They don't set the GID the way we need them to.
rm -f /usr/lib/sysusers.d/30-rpmostree-pkg-group-onepassword.conf
rm -f /usr/lib/sysusers.d/30-rpmostree-pkg-group-onepassword-cli.conf

echo "1Password installed successfully"
