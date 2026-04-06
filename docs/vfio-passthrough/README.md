# VFIO GPU Passthrough Configuration Backup

This directory preserves the configuration for NVIDIA RTX 4060 Ti passthrough
to a Windows 11 VM using Looking Glass + KVM/VFIO.

## Hardware

- **CPU**: AMD Ryzen (Raphael / Zen 4) with integrated GPU
- **Passthrough GPU**: NVIDIA RTX 4060 Ti 16GB (AD106)
  - PCI `01:00.0` — VGA controller — ID `10de:2805`
  - PCI `01:00.1` — HD Audio — ID `10de:22bd`
  - IOMMU Group 12 (both devices isolated together)
- **Host display**: AMD Raphael iGPU (while passthrough was active)

## Kernel Arguments (set via `rpm-ostree kargs`)

| Arg | Purpose |
|-----|---------|
| `amd_iommu=on` | Enable AMD IOMMU |
| `iommu=pt` | IOMMU passthrough mode (reduces DMA translation overhead) |
| `rd.driver.pre=vfio_pci` | Pre-load vfio-pci in initramfs so it claims the GPU before NVIDIA does |
| `vfio_pci.disable_vga=1` | Disable VGA legacy I/O on the passed-through GPU |
| `vfio-pci.ids=10de:2805,10de:22bd` | Bind NVIDIA GPU + audio to vfio-pci driver |
| `kvm.ignore_msrs=1` | Ignore unhandled MSRs (required for Windows stability) |
| `kvm.report_ignored_msrs=0` | Suppress MSR ignore messages in kernel log |
| `kvmfr.static_size_mb=128` | Looking Glass shared memory size (128MB = sufficient for 4K SDR) |

## Other Config Files

- `/etc/modprobe.d/vhost.conf`: `options vhost max_mem_regions=509`
  (high memory slot limit, useful for VMs with many virtio devices)

## Files in This Directory

- `win11-vfio.xml` — Full libvirt VM definition with GPU passthrough + Looking Glass
- `restore-vfio.sh` — Script to re-apply the VFIO kernel args
- `README.md` — This file

## Restoring Passthrough

1. Change `base-image` in `recipes/recipe.yml` back to `ghcr.io/ublue-os/bluefin-dx`
2. Remove or update the `kargs` module to include the VFIO args
3. Build + push + rebase to the image
4. Run `bash docs/vfio-passthrough/restore-vfio.sh`
5. Restore the VM: `sudo virsh --connect qemu:///system define docs/vfio-passthrough/win11-vfio.xml`
6. Reboot

## Looking Glass

- Client binary: `~/.local/bin/looking-glass-client`
- Shell alias: `looking-glass='looking-glass-client -s -S -f -k'`
- Shared memory device: `/dev/kvmfr0` (kernel module: `kvmfr`, static 128MB)
- The Windows VM needs the Looking Glass host application installed in Windows
