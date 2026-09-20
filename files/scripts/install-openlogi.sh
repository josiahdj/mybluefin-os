#!/usr/bin/env bash
set -oue pipefail

# OpenLogi (https://openlogi.org) -- local-first Logitech device manager,
# replaces Solaar/Logi Options+. Only distributed as GitHub release
# artifacts, no dnf repo or COPR, so this fetches the .rpm directly and
# checks it against upstream's published SHA256SUMS for that release.
# Pinned to a specific version (rather than /latest) so image builds stay
# reproducible; bump both when updating.
OPENLOGI_VERSION="0.8.3"
OPENLOGI_RPM="openlogi-v${OPENLOGI_VERSION}-linux-amd64.rpm"
OPENLOGI_URL="https://github.com/AprilNEA/OpenLogi/releases/download/v${OPENLOGI_VERSION}/${OPENLOGI_RPM}"
OPENLOGI_SHA256="778fa4969bbc948a755ec2f994d7eecd4585dab5fc7ad128bd48242ec30e3748"

echo "Installing OpenLogi v${OPENLOGI_VERSION}..."

workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

curl --fail --silent --show-error --location \
  "${OPENLOGI_URL}" \
  -o "${workdir}/${OPENLOGI_RPM}"

echo "${OPENLOGI_SHA256}  ${workdir}/${OPENLOGI_RPM}" | sha256sum --check --status

rpm-ostree install "${workdir}/${OPENLOGI_RPM}"

# The rpm already ships /etc/udev/rules.d/70-openlogi.rules (hidraw/uinput/
# input-event access for the active seat user) and
# /usr/lib/systemd/user/openlogi-agent.service. Neither the udev rule reload
# nor the systemd unit is enabled by installing the package -- OpenLogi's own
# docs treat enabling the agent as a per-user opt-in step, not something the
# package does for you, so this doesn't override that.
echo "OpenLogi installed successfully."
echo "NOTE: OpenLogi and Solaar can't run at the same time; both fight over HID++ access."
echo "NOTE: after rebasing, enable the background agent for your user session with:"
echo "  systemctl --user enable --now openlogi-agent.service"
