#!/usr/bin/env bash
#
# Derive the next semantic version from the conventional commits made since the
# last release tag, and print it to stdout as a tag (e.g. "v1.2.0").
#
# Used by .github/workflows/build.yml to version a successful main build.
# Run it locally to preview what the next release would be:
#
#   git fetch --tags && .github/scripts/next-version.sh
#
set -euo pipefail

# Printed when the repo has no valid semver tag yet, which is the case for the
# first run: this repo had no tags at all before this script existed.
SEED_TAG="${SEED_TAG:-v1.0.0}"

last_tag="$(git tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | head -n1)"

if [[ -z "$last_tag" ]]; then
  printf '%s\n' "$SEED_TAG"
  exit 0
fi

# Merge commits are excluded throughout: subjects like "Merge pull request #17
# from josiahdj/fix/copr-helper-cleanup" are not conventional commits, and
# counting them would mask the real commits they bring in.
#
# subjects: one commit subject per line, for matching the "type(scope):" prefix.
# bodies:   subjects and bodies, for matching the BREAKING CHANGE footer.
subjects="$(git log --no-merges --format='%s' "${last_tag}..HEAD")"
bodies="$(git log --no-merges --format='%s%n%b' "${last_tag}..HEAD")"

# Echoes exactly one of: major, minor, patch.
determine_bump() {
  # Breaking changes are honoured in both spellings Conventional Commits
  # allows: a "!" before the colon (feat!:, fix(base)!:) and a BREAKING CHANGE
  # footer in the body. The spec permits the hyphenated BREAKING-CHANGE in the
  # footer too, so both are matched.
  if grep -qE '^[a-zA-Z]+(\([^)]*\))?!:' <<<"$subjects" ||
    grep -qE '^BREAKING[ -]CHANGE:' <<<"$bodies"; then
    echo major
  elif grep -qE '^feat(\([^)]*\))?:' <<<"$subjects"; then
    echo minor
  else
    # Everything else is a patch: fix:, docs:, ci(deps):, chore(deps): -- and
    # the empty case, which is a nightly rebuild onto a refreshed upstream base
    # with no commits of our own since the last release.
    echo patch
  fi
}

bump="$(determine_bump)"

IFS=. read -r major minor patch <<<"${last_tag#v}"

case "$bump" in
  major) major=$((major + 1)); minor=0; patch=0 ;;
  minor) minor=$((minor + 1)); patch=0 ;;
  patch) patch=$((patch + 1)) ;;
  *)
    printf 'error: determine_bump returned %q, expected major|minor|patch\n' "$bump" >&2
    exit 1
    ;;
esac

printf 'v%s.%s.%s\n' "$major" "$minor" "$patch"
