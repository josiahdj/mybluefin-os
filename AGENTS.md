# Notes for AI Agents

This repo builds a personal Fedora Atomic image (`ghcr.io/josiahdj/mybluefin-os`)
with BlueBuild. `recipes/recipe.yml` is the entry point. Scripts in
`files/scripts/` run at build time, and the `files` module copies
`files/system/*` into the image root.

## Topic Docs

- **Howdy face unlock / IR camera** (including switching to a new camera):
  [docs/howdy/README.md](docs/howdy/README.md)
- **VFIO GPU passthrough**: [docs/vfio-passthrough/README.md](docs/vfio-passthrough/README.md)

## Releases

A successful build on `main` cuts a release. The `release` job in
`.github/workflows/build.yml` derives the next version from the Conventional
Commit subjects since the last `vX.Y.Z` tag (`feat:` bumps the minor, a `!` or
a `BREAKING CHANGE:` footer bumps the major, everything else bumps the patch),
adds that tag to the image already in the registry, and creates the GitHub
Release. Commit messages must therefore follow Conventional Commits.

The nightly schedule rebuilds onto a refreshed upstream base with no commits of
our own, so the job skips the release when the digest it just pushed already
matches the digest behind the previous version tag.

Preview the next version locally with
`git fetch --tags && .github/scripts/next-version.sh`.

## Things That Commonly Trip Agents Up

- Changes to files under `/etc` in the image only reach fresh installs.
  rpm-ostree keeps host-modified `/etc` files (including
  `/etc/howdy/config.ini` and `/etc/pam.d/*`), so host fixes must be applied
  on the host, not just in the image.
- `sudo` and GUI auth prompts on this machine trigger a Howdy face scan, which
  turns on the IR camera. Before running anything that authenticates, tell the
  user to look at the camera, and wait until they are ready.
- Validate recipe changes with `bluebuild validate recipes/recipe.yml`.
