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

# --noscripts: the rpm's %post runs `udevadm control --reload-rules` under
# `set -e`, which fails in a build container (no udev daemon to talk to) and
# aborts the whole rpm-ostree transaction ("Failed to send reload request").
# That scriptlet only reloads udev and refreshes icon caches, none of which
# applies at image build time; the udev rule is loaded at boot anyway.
rpm --install --noscripts "${workdir}/${OPENLOGI_RPM}"

# The rpm ships /etc/udev/rules.d/70-openlogi.rules (hidraw/uinput/input-event
# access for the active seat user) and /usr/lib/systemd/user/openlogi-agent.service.
# Enabling the agent is a per-user opt-in step in OpenLogi's own docs, so this
# doesn't override that.
echo "OpenLogi installed successfully."
echo "NOTE: OpenLogi and Solaar can't run at the same time; both fight over HID++ access."
echo "NOTE: after rebasing, enable the background agent for your user session with:"
echo "  systemctl --user enable --now openlogi-agent.service"
