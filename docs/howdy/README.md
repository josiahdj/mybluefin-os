# Howdy Face Authentication

Howdy (3.0 beta, from the `starfish/howdy-beta` COPR) unlocks sudo, GNOME
polkit prompts, the GDM login screen and the lock screen with an IR camera.

## Current Hardware

- **Camera**: iContact Camera Pro Hello, plugged into the Microsoft Surface
  Thunderbolt 4 Dock. It shows up as two USB devices behind a small built-in
  hub:

  | USB device | Interface | Stream | Formats | Used by Howdy |
  |------------|-----------|--------|---------|---------------|
  | Realtek `0bda:5856` "iContact Camera Pro Hello Color Camera", serial `YHTEK` | `00` | RGB | MJPG/YUYV 640x480 | no |
  | Realtek `0bda:5856` (same device) | `02` | **IR** | **GREY** 640x480, 640x360 | **yes** |
  | Sunplus `1bcf:2d3e` "iContact Camera Pro Hello" | `00` | RGB 4K (plus a mic) | MJPG/YUYV up to 3840x2160 | no |

  The names are misleading: the device called "Color Camera" is the one
  carrying the IR stream, and the one called "Hello" is the 4K webcam.

- **Howdy `device_path`**:
  `/dev/v4l/by-id/usb-DECXIN_iContact_Camera_Pro_Hello_Color_Camera_YHTEK-if02-video-index0`

## Where Each Piece Lives

| Piece | Location | Shipped in image? |
|-------|----------|-------------------|
| `howdy`, `howdy-gtk` packages | `recipes/recipe.yml` (dnf module) | yes |
| `detection_notice = true` | `files/scripts/configure-howdy.sh` | default only (see below) |
| SELinux module `howdy_gdm` (lets GDM/lock screen map the camera) | `files/selinux/howdy_gdm.te`, `files/scripts/install-howdy-selinux.sh`, `howdy-selinux-install.service` | yes, loaded at boot |
| `-ifNN` by-id camera links | `files/system/usr/lib/udev/rules.d/70-v4l-by-id-interface.rules` | yes |
| `device_path`, `timeout`, `certainty`, etc. | `/etc/howdy/config.ini` | **host only** |
| Enrolled face models | `/etc/howdy/models/` | **host only** |
| `auth sufficient pam_howdy.so` | `/etc/pam.d/system-auth` (hand-edited, not authselect) | **host only** |

`/etc/howdy/config.ini` is a `%config(noreplace)` file that has been edited on
the host. rpm-ostree's `/etc` merge keeps the host copy, so changing the
image's default does nothing on an existing install. Edit it on the host with
`sudo howdy config` or `sed`.

## Switching to a Different IR Camera

No image rebuild is needed for a USB camera. The udev rule and the SELinux
module both work for any camera.

1. **Plug the camera in and find its IR stream.** It is the node that offers
   a greyscale format (`gray`, `8-bit Greyscale`; sometimes `y16`). Nodes with
   no formats are UVC metadata nodes; ignore them. Listing formats only
   queries the driver; it does not start a capture.

   ```bash
   for d in /dev/video*; do
     echo "== $d: $(cat /sys/class/video4linux/${d#/dev/}/name)"
     ffmpeg -hide_banner -f v4l2 -list_formats all -i "$d" 2>&1 | grep -E 'Raw|Compressed'
   done
   ```

   Some IR cameras advertise their IR stream as YUYV instead of greyscale. If
   no node shows greyscale, try each candidate with `sudo howdy test` after
   step 3. The IR image looks monochrome and flickers as the emitter pulses.

2. **Get its stable name.** Use the `-ifNN-` link from our udev rule:

   ```bash
   udevadm info -q symlink /dev/videoN | tr ' ' '\n' | grep -- '-if'
   ```

   Do not use the plain `...-video-index0` by-id link unless the camera has
   only one video interface. Otherwise several streams claim it, and it can
   point at the RGB stream after a reboot. To see every claimant of a link,
   run `ls /run/udev/links/*<serial>*/`.

   Avoid `/dev/videoN`: the numbers follow probe order and change when devices
   enumerate in a different order (for example after a dock reset). Avoid
   `/dev/v4l/by-path/` too: it changes if the camera moves to another port.

3. **Point Howdy at it**:

   ```bash
   # step 2 prints the link without /dev/, e.g. v4l/by-id/usb-...-if02-video-index0
   sudo sed -i 's|^device_path *=.*|device_path = /dev/<link from step 2>|' /etc/howdy/config.ini
   ```

4. **Re-enroll your face.** Models are specific to the camera that recorded
   them. Look at the camera during `add`:

   ```bash
   sudo howdy clear
   sudo howdy add
   ```

5. **Test**, looking at the camera each time: `sudo howdy test` (live
   preview), then `sudo -k; sudo true`, then lock the screen (Super+L). If
   frames are rejected as too dark, lower `dark_threshold` in the config.

6. **Update the "Current Hardware" section above.**

A non-USB camera (e.g. a laptop's built-in MIPI IR camera) would not get an
`-ifNN` link. Check `udevadm info /dev/videoN` for a stable property and
extend the udev rule.

## Troubleshooting

- **Logs**: `journalctl -b -t pam_howdy`. The syslog identifier is
  `pam_howdy`, so `journalctl -g pam_howdy` misses most lines. "Failed to read
  files from glob: 3" followed by "No such file or directory" is Howdy's
  laptop-lid check failing on a desktop, and is harmless.
- **"Attempting facial authentication" but the camera stays off**:
  - Check that the configured device exists:
    `ls -l "$(sed -n 's/^device_path *= *//p' /etc/howdy/config.ini)"`
  - Check that the camera enumerated: `lsusb`
  - The camera sits behind the dock. If the dock gets wedged, it loops
    through USB resets (kernel log shows `error -71` and repeated
    `USB disconnect`; count them with
    `journalctl -k -b | grep -c 'USB disconnect'`). Rebooting the PC does not
    fix that, because the dock stays powered. Unplug the dock's power for
    about 30 seconds.
- **sudo works, but GDM/lock screen does not**: this points at SELinux. The
  journal shows `AVC denied { map } ... scontext=...xdm_t ... v4l_device_t`
  and `failed mmap(...): errno=13`.
  - Check the setup service: `systemctl status howdy-selinux-install.service`.
    On every boot it verifies that the running kernel policy contains the
    rule. If it doesn't, the service fails and logs why.
  - Check the module is installed: `sudo semodule -l | grep howdy_gdm`
  - Check for denials: `sudo ausearch -m avc -ts recent | grep -E 'v4l|video'`
  - Fedora runs every display manager as `xdm_t`; there are no
    `gdm_t`/`sddm_t` types.
- **Module installed, but the kernel still denies `map`**: look for a stale
  compiled policy with `ls -l /etc/selinux/targeted/policy/`. The kernel loads
  the highest-numbered `policy.N` it supports, and `semodule` writes the version
  its own toolchain defaults to. In Sep 2026 this machine had a leftover
  `policy.35` from Feb 2026, while the image's toolchain wrote `policy.34`. So
  every boot loaded February's policy, and every module installed since was
  ignored. Host `/etc` survives rebases, so the file never went away. Fix:
  `sudo mv /etc/selinux/targeted/policy/policy.35 /root/` then
  `sudo load_policy`. To confirm, without root:
  ```bash
  python3 -c 'import selinux as s; c=s.string_to_security_class("chr_file"); a=s.av_decision(); s.security_compute_av("system_u:system_r:xdm_t:s0-s0:c0.c1023","system_u:object_r:v4l_device_t:s0",c,0,a); print("map allowed:", bool(a.allowed & s.string_to_av_perm(c,"map")))'
  ```
- **GNOME's polkit dialog only appears after the scan has timed out**:
  `detection_notice` must be `true`. GNOME opens the dialog only once PAM
  sends a message, so without the notice the scan runs with nothing on
  screen.
- **Face scans happen twice per sudo attempt**: `pam_howdy.so` is listed in
  both `/etc/pam.d/sudo` and `/etc/pam.d/system-auth`, which sudo includes.
  Keep it only in `system-auth`.
