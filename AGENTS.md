# Notes for AI Agents

This repo builds a personal Fedora Atomic image (`ghcr.io/josiahdj/mybluefin-os`)
with BlueBuild. `recipes/recipe.yml` is the entry point. Scripts in
`files/scripts/` run at build time, and the `files` module copies
`files/system/*` into the image root.

## Topic Docs

- **Howdy face unlock / IR camera** (including switching to a new camera):
  [docs/howdy/README.md](docs/howdy/README.md)
- **VFIO GPU passthrough**: [docs/vfio-passthrough/README.md](docs/vfio-passthrough/README.md)

## Things That Commonly Trip Agents Up

- Changes to files under `/etc` in the image only reach fresh installs.
  rpm-ostree keeps host-modified `/etc` files (including
  `/etc/howdy/config.ini` and `/etc/pam.d/*`), so host fixes must be applied
  on the host, not just in the image.
- `sudo` and GUI auth prompts on this machine trigger a Howdy face scan, which
  turns on the IR camera. Before running anything that authenticates, tell the
  user to look at the camera, and wait until they are ready.
- Validate recipe changes with `bluebuild validate recipes/recipe.yml`.
