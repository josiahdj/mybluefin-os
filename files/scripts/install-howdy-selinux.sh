#!/usr/bin/env bash
set -euo pipefail

echo "Installing Howdy SELinux policy..."

# Create directory for SELinux policy
mkdir -p /usr/share/selinux/howdy

# Copy the SELinux policy file
cp -f /tmp/files/selinux/howdy_gdm.te /usr/share/selinux/howdy/

# Create the setup script that will be run at boot
cat > /usr/libexec/howdy-selinux-setup << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

WRK="/run/howdy"

log(){ logger -t "howdy-selinux-setup" -- "$*"; }

# Resolve semodule path (prefer absolute), bail quietly if missing
SEM="/usr/sbin/semodule"
[ -x "$SEM" ] || SEM="$(command -v semodule || true)"
if [ -z "${SEM:-}" ]; then
  log "semodule not found; is policycoreutils installed? skipping"
  exit 0
fi

# Only act on SELinux-enabled systems
if ! sestatus >/dev/null 2>&1 || ! sestatus 2>/dev/null | grep -q 'enabled'; then
  exit 0
fi

# Exit if already installed
if "$SEM" -l | awk '{print $1}' | grep -qx howdy_gdm; then
  exit 0
fi

install -d -m0755 "$WRK"
cp -f "/usr/share/selinux/howdy/howdy_gdm.te" "$WRK/"

# Prefer devel Makefile; else fall back to raw toolchain (module ver 21)
if [ -f /usr/share/selinux/devel/Makefile ]; then
  log "compiling policy using devel Makefile..."
  make -f /usr/share/selinux/devel/Makefile -C "$WRK" howdy_gdm.pp
else
  log "compiling policy using raw toolchain..."
  cd "$WRK"
  checkmodule -M -m -o howdy_gdm.mod howdy_gdm.te
  semodule_package -o howdy_gdm.pp -m howdy_gdm.mod
fi

# Install compiled policy
log "installing compiled policy..."
"$SEM" -i "$WRK/howdy_gdm.pp"

log "Howdy SELinux policy installed successfully"
EOF

chmod 0755 /usr/libexec/howdy-selinux-setup

echo "Howdy SELinux setup script installed"