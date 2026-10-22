#!/usr/bin/env bash
# Clone Cua Driver, apply this repository's patch, and build the patched driver.
# Usage: scripts/build.sh [main|v0.37] [workdir]
set -euo pipefail

VARIANT="${1:-main}"
WORK="${2:-cua-driver-build}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

git clone --depth 1 --filter=blob:none --sparse https://github.com/trycua/cua.git "$WORK"
cd "$WORK"
git sparse-checkout set libs/cua-driver/rust libs/cua libs/images libs/cua-driver/wayland-helper

case "$VARIANT" in
  main)
    PATCH="$REPO_ROOT/patches/main-combined.diff"
    ;;
  v0.37 | 0.37)
    git fetch --depth 1 origin tag cua-driver-rs-v0.37.0
    git checkout -q cua-driver-rs-v0.37.0
    PATCH="$REPO_ROOT/patches/v0.37-combined.diff"
    ;;
  *)
    echo "unknown variant '$VARIANT' (expected main or v0.37)" >&2
    exit 2
    ;;
esac

git apply --check "$PATCH"
git apply "$PATCH"

cd libs/cua-driver/rust
cargo build --release -p cua-driver --bin cua-driver
echo "built: $WORK/libs/cua-driver/rust/target/release/cua-driver"
