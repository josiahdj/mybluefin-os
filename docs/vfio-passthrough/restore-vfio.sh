#!/bin/bash
# Restore NVIDIA RTX 4060 Ti VFIO GPU passthrough + Looking Glass
#
# This script re-applies the kernel args needed for GPU passthrough.
# Run it after rebasing back to the non-NVIDIA base image.
#
# Prerequisites:
#   1. In recipes/recipe.yml, set: base-image: ghcr.io/ublue-os/bluefin-dx
#      (and remove the kargs module, or remove the kvm args)
#   2. Build and push the image, then rebase to it
#   3. Run this script, then reboot
#
# To also restore the Windows VM config:
#   sudo virsh --connect qemu:///system define \
#     /path/to/mybluefin-os/docs/vfio-passthrough/win11-vfio.xml

set -e

echo "Re-applying VFIO passthrough kernel args..."

rpm-ostree kargs \
  --append-if-missing="rd.driver.pre=vfio_pci" \
  --append-if-missing="vfio_pci.disable_vga=1" \
  --append-if-missing="vfio-pci.ids=10de:2805,10de:22bd" \
  --append-if-missing="kvmfr.static_size_mb=128"

echo ""
echo "Done. Reboot to apply."
echo ""
echo "NVIDIA PCI IDs (for reference):"
echo "  GPU:   10de:2805  (RTX 4060 Ti, 01:00.0)"
echo "  Audio: 10de:22bd  (NVIDIA HD Audio, 01:00.1)"
