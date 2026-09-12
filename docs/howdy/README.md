# Howdy Face Authentication

Howdy (3.0 beta, from the `starfish/howdy-beta` COPR) unlocks sudo, GNOME
polkit prompts, the GDM login screen and the lock screen with an IR camera.

## Current Hardware

- **Camera**: Logitech BRIO (`046d:085e`, serial `511030C9`), plugged
  straight into a PC USB port (controller `0000:16:00.4`), not the dock. It
  is one UVC function, so all four video nodes hang off interface `00`, and
  the `video-indexN` suffix tells them apart:

  | Node | Stream | Formats | Used by Howdy |
  |------|--------|---------|---------------|
  | `-if00-video-index0` | RGB | MJPG/YUYV up to 1920x1080 | no |
  | `-if00-video-index1` | metadata | none | no |
  | `-if00-video-index2` | **IR** | **GREY** 340x340 | **yes** |
  | `-if00-video-index3` | metadata | none | no |

- **Howdy `device_path`**:
  `/dev/v4l/by-id/usb-046d_Logitech_BRIO_511030C9-if00-video-index2`

- **Previous camera** (until Sep 2026): iContact Camera Pro Hello on the
  dock. That was a composite of two USB devices. Its IR stream was the Realtek
  `0bda:5856` "Color Camera" (serial `YHTEK`), interface `02`, at
  `/dev/v4l/by-id/usb-DECXIN_iContact_Camera_Pro_Hello_Color_Camera_YHTEK-if02-video-index0`.
  The names were misleading: the "Color Camera" carried the IR stream, and the
  Sunplus `1bcf:2d3e` "Hello" device was the 4K RGB webcam.

## Where Each Piece Lives

| Piece | Location | Shipped in image? |
|-------|----------|-------------------|
| `howdy`, `howdy-gtk` packages | `recipes/recipe.yml` (dnf module) | yes |
| `detection_notice = true` | `files/scripts/configure-howdy.sh` | default only (see below) |
| `device_path` (current camera; previous cameras as commented-out lines) | `files/scripts/configure-howdy.sh` (`DEVICE_PATH`, `PREVIOUS_DEVICE_PATHS`) | default only (see below) |
| SELinux module `howdy_gdm` (lets GDM/lock screen map the camera) | `files/selinux/howdy_gdm.te`, `files/scripts/install-howdy-selinux.sh`, `howdy-selinux-install.service` | yes, loaded at boot |
| `-ifNN` by-id camera links | `files/system/usr/lib/udev/rules.d/70-v4l-by-id-interface.rules` | yes |
| `timeout`, `certainty`, etc., and the live `device_path` | `/etc/howdy/config.ini` | **host only** |
| Enrolled face models | `/etc/howdy/models/` | **host only** |
| `auth sufficient pam_howdy.so` | `/etc/authselect/custom/howdy/system-auth`, surfaced at `/etc/pam.d/system-auth` (see [PAM and authselect](#pam-and-authselect)) | **host only** |
| `auth sufficient pam_howdy.so` (login/lock screen) | `/etc/pam.d/gdm-password`, `gdm-fingerprint`, `gdm-autologin` — not authselect-managed | **host only** |

`/etc/howdy/config.ini` is a `%config(noreplace)` file that has been edited on
the host. rpm-ostree's `/etc` merge keeps the host copy, so changing the
image's default does nothing on an existing install. Edit it on the host with
`sudo howdy config` or `sed`.

## PAM and authselect

Howdy needs one line, `auth sufficient pam_howdy.so`, in `system-auth`. That
file is owned by authselect, so the line is carried by a custom authselect
profile rather than by editing the file.

**Do not hand-edit `/etc/pam.d/system-auth`.** Between Sep 2025 and Sep 2026
this host was opted out of authselect entirely: `/etc/authselect/` was deleted
and the five managed files were left as frozen copies of authselect's output
with the Howdy line added. Because rpm-ostree preserves host `/etc` forever,
those copies never received Fedora's updates. The F42 to F44 rebase then broke
them: F44 replaced `pam_lastlog.so` with `pam_lastlog2.so`, so every login and
every `sudo` logged `PAM unable to dlopen(/usr/lib64/security/pam_lastlog.so)`
and `PAM adding faulty module`. Non-fatal, but it only degrades further.

The profile symlinks every template back to the base profile, so `system-auth`
is the only file it owns and Fedora's updates to the rest keep flowing:

```bash
sudo authselect create-profile howdy -b local \
    --symlink-meta --symlink-nsswitch --symlink-dconf \
    -s password-auth -s postlogin -s fingerprint-auth -s smartcard-auth
```

Then add this to `/etc/authselect/custom/howdy/system-auth`, immediately above
the `pam_fprintd.so` line:

```
auth        sufficient                                   pam_howdy.so                                           {include if "with-howdy"}
```

and select it (the features match what the Bluefin image ships, plus
fingerprint and Howdy):

```bash
sudo authselect select custom/howdy \
    with-silent-lastlog with-mdns4 with-fingerprint with-howdy --force
sudo dconf update
```

Notes:

- **`authselect test` renders the whole configuration without root and without
  writing anything.** Always diff it against the live files before running a
  `--force` select:
  `authselect test custom/howdy with-silent-lastlog with-mdns4 with-fingerprint with-howdy`
- `--force` is required because it overwrites `/etc/pam.d/{system,password,postlogin,fingerprint,smartcard,switchable}-auth`,
  `/etc/nsswitch.conf` and `/etc/dconf/db/distro.d/20-authselect`. Back those
  up first, and keep an already-authenticated root shell open in another
  terminal while you do it — it does not re-authenticate, so it is the way
  back in if the result is wrong.
- authselect keeps its own backup; `authselect backup-list` shows them.
- **Kill switch**: re-select without `with-howdy` to drop the line without
  editing anything. `sudo authselect select custom/howdy with-silent-lastlog
  with-mdns4 with-fingerprint --force`
- `authselect check` verifies the configuration is intact.
- GDM's own files (`gdm-password`, `gdm-fingerprint`, `gdm-autologin`) are not
  authselect-managed, so their Howdy lines are unaffected by any of this.
  Note `gdm-password` includes `password-auth`, not `system-auth`; `polkit-1`
  lives in `/usr/lib/pam.d/` and includes `system-auth`.
- The profile lives in `/etc`, so it reaches this host only. A fresh install
  from the image has to run the commands above again.

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

6. **Update the image default** so fresh installs use the new camera: in
   `files/scripts/configure-howdy.sh`, move the old `DEVICE_PATH` into
   `PREVIOUS_DEVICE_PATHS` and set `DEVICE_PATH` to the new link. This does not
   change the host (see "Where Each Piece Lives"); step 3 did that.

7. **Update the "Current Hardware" section above.**

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
  - If the camera is plugged into the dock (the previous camera was) and the
    dock gets wedged, it loops through USB resets (kernel log shows `error -71` and repeated
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
