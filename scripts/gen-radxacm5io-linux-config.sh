#!/bin/sh
# Generate configs/radxacm5io-linux.config from allnoconfig + minimal fragment.
# Run from a Linux tree (or pass LINUX_SRC). Requires gcc/make for arm64.
set -e

REPO_ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
LINUX_SRC="${LINUX_SRC:-$1}"
FRAGMENT="$REPO_ROOT/configs/radxacm5io-kernel.fragment"
OUT="$REPO_ROOT/configs/radxacm5io-linux.config"

if [ -z "$LINUX_SRC" ] || [ ! -d "$LINUX_SRC" ]; then
	echo "usage: $0 /path/to/linux-source" >&2
	echo "   or: LINUX_SRC=/path/to/linux $0" >&2
	exit 1
fi

if [ ! -f "$FRAGMENT" ]; then
	echo "missing fragment: $FRAGMENT" >&2
	exit 1
fi

cd "$LINUX_SRC"
# Host toolchain only (avoid musl-gcc / rootfs ld if caller polluted PATH)
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
unset CC CXX CFLAGS LDFLAGS CPPFLAGS C_INCLUDE_PATH CPLUS_INCLUDE_PATH LD
export CC=gcc HOSTCC=gcc LD=ld

# Tiny base: only enable what the fragment + deps need.
make ARCH=arm64 allnoconfig
scripts/kconfig/merge_config.sh -m .config "$FRAGMENT"
# Resolve dependencies / drop unknown symbols for this kernel version
make ARCH=arm64 olddefconfig
cp .config "$OUT"
echo "wrote $OUT ($(wc -l < "$OUT") lines, $(grep -c '=y$' .config || true) =y symbols)"
