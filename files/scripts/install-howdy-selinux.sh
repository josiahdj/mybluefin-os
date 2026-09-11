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
warn(){ logger -t "howdy-selinux-setup" -p user.warning -- "$*"; }

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

SELINUXTYPE="$(sed -n 's/^SELINUXTYPE=//p' /etc/selinux/config 2>/dev/null)"
POLDIR="/etc/selinux/${SELINUXTYPE:-targeted}/policy"

# Exit 0 if the running kernel policy lets the display manager (xdm_t) mmap
# video devices, which is what howdy_gdm adds. 1 if not, 2 if we can't tell.
rule_active() {
  python3 - <<'PY'
import sys
try:
    import selinux
except ImportError:
    sys.exit(2)
cls = selinux.string_to_security_class("chr_file")
avd = selinux.av_decision()
selinux.security_compute_av("system_u:system_r:xdm_t:s0-s0:c0.c1023",
                            "system_u:object_r:v4l_device_t:s0", cls, 0, avd)
sys.exit(0 if avd.allowed & selinux.string_to_av_perm(cls, "map") else 1)
PY
}

# The policy.N version semodule writes: semanage.conf's policy-version if set,
# else libsepol's newest, which is libsemanage's default.
policy_write_version() {
  local v
  v="$(sed -n 's/^[[:space:]]*policy-version[[:space:]]*=[[:space:]]*//p' /etc/selinux/semanage.conf 2>/dev/null)"
  [ -n "$v" ] || v="$(python3 -c 'import ctypes; print(ctypes.CDLL("libsepol.so.2").sepol_policy_kern_vers_max())' 2>/dev/null)"
  echo "$v"
}

# The newest policy version the running kernel accepts.
kernel_policy_version() { cat /sys/fs/selinux/policyvers 2>/dev/null; }

# Name any policy.N file that outranks the version semodule writes. When
# loading, libselinux tries policy.<kernel max> and counts down, taking the
# first file that exists. So a file with write version < N <= kernel max (e.g.
# left in the host's /etc by an older image with a newer toolchain) shadows the
# current policy, and every module installed since is silently ignored.
report_stale_policy() {
  local f n writes kmax found=1
  writes="$(policy_write_version)"
  kmax="$(kernel_policy_version)"
  if ! [[ "$writes" =~ ^[0-9]+$ && "$kmax" =~ ^[0-9]+$ ]]; then
    warn "could not determine policy versions (semodule writes '$writes', kernel accepts '$kmax'); not checking $POLDIR for stale files"
    return 1
  fi
  for f in "$POLDIR"/policy.*; do
    n="${f##*.}"
    [[ -f "$f" && "$n" =~ ^[0-9]+$ ]] || continue
    if (( n > writes && n <= kmax )); then
      warn "stale policy file $f (modified $(date -r "$f" +%F)) outranks policy.$writes, which is what semodule writes; the kernel loads $f instead. If it is a leftover, move it out of $POLDIR and run load_policy. See docs/howdy/README.md in the image repo."
      found=0
    fi
  done
  return "$found"
}

if ! "$SEM" -l | awk '{print $1}' | grep -qx howdy_gdm; then
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
  log "Howdy SELinux policy installed"
fi

# `semodule -i` succeeding doesn't mean the kernel is enforcing the result, so
# check the running policy on every boot, including after the module is
# already installed.
status=0
rule_active || status=$?
case "$status" in
  0) log "howdy_gdm rule is active in the running policy" ;;
  2) warn "python3-libselinux unavailable; cannot verify howdy_gdm is active" ;;
  *)
    report_stale_policy ||
      warn "howdy_gdm is installed but its rule is not in the running policy; check 'semodule -l' and the files in $POLDIR"
    exit 1
    ;;
esac
EOF

chmod 0755 /usr/libexec/howdy-selinux-setup

echo "Howdy SELinux setup script installed"