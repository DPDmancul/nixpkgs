#!/usr/bin/env bash
set -e

OWNER=mastodon
REPO=mastodon

POSITIONAL=()
while [[ $# -gt 0 ]]; do
    key="$1"

    case $key in
        --owner)
            OWNER="$2"
            shift # past argument
            shift # past value
            ;;
        --repo)
            REPO="$2"
            shift # past argument
            shift # past value
            ;;
        --ver)
            VERSION="$2"
            shift # past argument
            shift # past value
            ;;
        --rev)
            REVISION="$2"
            shift # past argument
            shift # past value
            ;;
        --patches)
            PATCHES="$2"
            shift # past argument
            shift # past value
            ;;
        *)  # unknown option
            POSITIONAL+=("$1")
            shift # past argument
            ;;
    esac
done

if [[ -z "$VERSION" || -n "$POSITIONAL" ]]; then
    echo "Usage: update.sh [--owner OWNER] [--repo REPO] --ver VERSION [--rev REVISION] [--patches PATCHES]"
    echo "OWNER and repo must be paths on github."
    echo "If VERSION is not a revision acceptable to 'git checkout', you must provide one in REVISION."
    echo "If OWNER and REPO are not provided, it defaults they default to mastodon and mastodon."
    echo "PATCHES, if provided, should be one or more Nix expressions separated by spaces."
    exit 1
fi

if [[ -z "$REVISION" ]]; then
    REVISION="$VERSION"
fi

rm -f gemset.nix version.nix source.nix
TARGET_DIR="$PWD"


WORK_DIR=$(mktemp -d)

# Check that working directory was created.
if [[ -z "$WORK_DIR" || ! -d "$WORK_DIR" ]]; then
    echo "Could not create temporary directory"
    exit 1
fi

# Delete the working directory on exit.
function cleanup {
    # Report errors, if any, from nix-prefetch-git
    grep "fatal" $WORK_DIR/nix-prefetch-git.out >/dev/stderr || true
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

echo "Fetching source code $REVISION"
JSON=$(nix-prefetch-github "$OWNER" "$REPO" --rev "$REVISION"  2> $WORK_DIR/nix-prefetch-git.out)
SHA=$(echo "$JSON" | jq -r .sha256)

echo "Creating version.nix"
echo "\"$VERSION\"" | sed 's/^"v/"/' > version.nix

cat > source.nix << EOF
# This file was generated by pkgs.mastodon.updateScript.
{ fetchFromGitHub, applyPatches }: let
  src = fetchFromGitHub {
    owner = "mastodon";
    repo = "mastodon";
    rev = "$REVISION";
    sha256 = "$SHA";
  };
in applyPatches {
  inherit src;
  patches = [$PATCHES];
}
EOF
SOURCE_DIR="$(nix-build --no-out-link -E '(import <nixpkgs> {}).callPackage ./source.nix {}')"

echo "Creating gemset.nix"
bundix --lockfile="$SOURCE_DIR/Gemfile.lock" --gemfile="$SOURCE_DIR/Gemfile"
echo "" >> "$TARGET_DIR/gemset.nix"  # Create trailing newline to please EditorConfig checks
