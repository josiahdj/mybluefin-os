#!/usr/bin/env bash

# Tell this script to exit if there are any errors.
set -oue pipefail

# The scottames/ghostty COPR build never ships /usr/share/ghostty/themes.
# ghostty itself works fine, but any `theme = <name>` config value is
# unresolvable, since there's nothing on disk to satisfy it. Upstream ghostty
# normally populates that directory at build time from a `themes` submodule
# pointing at mbadolato/iTerm2-Color-Schemes; this COPR build skips that step.
#
# Fetch that repo ourselves and copy in its `ghostty/` subdirectory, which is
# already in ghostty's native theme config format (plain `key = value` files,
# one per theme, no conversion needed).
#
# Pinned to a specific commit (rather than a branch) so image builds stay
# reproducible.
ITERM2_COLOR_SCHEMES_COMMIT="752a9c079396cc9939b86e893578ed81e80c140f"

echo "Installing ghostty themes (missing from the scottames/ghostty COPR build)..."

workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

curl --fail --silent --show-error --location \
  "https://github.com/mbadolato/iTerm2-Color-Schemes/archive/${ITERM2_COLOR_SCHEMES_COMMIT}.tar.gz" \
  -o "${workdir}/iterm2-color-schemes.tar.gz"

tar -xzf "${workdir}/iterm2-color-schemes.tar.gz" -C "${workdir}"

src_dir="${workdir}/iTerm2-Color-Schemes-${ITERM2_COLOR_SCHEMES_COMMIT}/ghostty"
dest_dir="/usr/share/ghostty/themes"

mkdir -p "${dest_dir}"
cp -a "${src_dir}/." "${dest_dir}/"

theme_count="$(find "${dest_dir}" -maxdepth 1 -type f | wc -l)"
echo "Installed ${theme_count} ghostty themes to ${dest_dir}"
