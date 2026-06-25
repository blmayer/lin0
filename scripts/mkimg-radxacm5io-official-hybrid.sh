#!/bin/sh
# Compact hybrid CM5 IO image: official loader/GPT/p1/p2 head + small lin0 p3 only.
#
# Default ~460 MiB (was ~4.5 GiB full official clone):
#   - copy official bytes only up to p3 start (~332 MiB: SPL/U-Boot + GPT + FAT p1/p2)
#   - append small ext4 p3 (P3_SIZE_MB, default 128) with lin0 rootfs + /boot/Image
#   - rewrite GPT p3 last-LBA + backup GPT; truncate file
#
# U-Boot still does: sysboot mmc 0:3 /boot/extlinux/extlinux.conf
#
# Usage:
#   ./scripts/mkimg-radxacm5io-official-hybrid.sh
#   P3_SIZE_MB=96 OUTIMG=... ./scripts/mkimg-radxacm5io-official-hybrid.sh
#   FULL_CLONE=1  # old behaviour: copy entire 4.5G official then rewrite p3
#
# Flash (Maskrom):
#   rkdeveloptool db build/rk3588_spl_loader.bin
#   rkdeveloptool wl 0 lin0-radxacm5io.img

set -e

REPO_ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
OFFICIAL_IMG="${OFFICIAL_IMG:-$REPO_ROOT/build/official-radxa-inspect/radxa-cm5-io_bookworm_cli_b3.output.img}"
ROOTFS="${ROOTFS:-$REPO_ROOT/rootfs}"
OUTIMG="${OUTIMG:-$REPO_ROOT/lin0-radxacm5io.img}"
KERNEL="${KERNEL:-$ROOTFS/boot/Image}"
DTB="${DTB:-$ROOTFS/boot/rk3588s-radxa-cm5-io.dtb}"
if [ ! -f "$DTB" ] && [ -f "$REPO_ROOT/build/dtbs/rk3588s-radxa-cm5-io.dtb" ]; then
	DTB="$REPO_ROOT/build/dtbs/rk3588s-radxa-cm5-io.dtb"
fi

# Official GPT geometry (bookworm CLI b3)
P3_START_LBA="${P3_START_LBA:-679936}"
# Compact default: 128 MiB root — enough for ~36 MiB lin0 + 14 MiB Image + headroom
P3_SIZE_MB="${P3_SIZE_MB:-128}"
FULL_CLONE="${FULL_CLONE:-0}"

ROOT_UUID="${ROOT_UUID:-a1ce5ba1-b0fe-43c3-b85c-eca170319b83}"
ROOT_LABEL="${ROOT_LABEL:-lin0root}"

die() { echo "error: $*" >&2; exit 1; }

[ -f "$OFFICIAL_IMG" ] || die "official image missing: $OFFICIAL_IMG"
[ -d "$ROOTFS" ] || die "rootfs missing: $ROOTFS"
[ -f "$ROOTFS/sbin/init" ] || die "rootfs missing sbin/init"
[ -f "$KERNEL" ] || die "kernel missing: $KERNEL"
[ -f "$DTB" ] || die "dtb missing: $DTB"
command -v docker >/dev/null || die "docker required"
command -v python3 >/dev/null || die "python3 required"

P3_SECTS=$((P3_SIZE_MB * 1024 * 1024 / 512))
[ "$P3_SECTS" -ge 65536 ] || die "P3_SIZE_MB=$P3_SIZE_MB too small (need >= 32)"

HEAD_BYTES=$((P3_START_LBA * 512))
TOTAL_SECTS=$((P3_START_LBA + P3_SECTS))
TOTAL_BYTES=$((TOTAL_SECTS * 512))

if [ "$(cd "$(dirname "$OUTIMG")" && pwd)/$(basename "$OUTIMG")" = \
	"$(cd "$(dirname "$OFFICIAL_IMG")" && pwd)/$(basename "$OFFICIAL_IMG")" ]; then
	die "OUTIMG must not be the official source image"
fi

case "$(CDPATH= cd -- "$(dirname "$OUTIMG")" && pwd)" in
	"$REPO_ROOT"|"$REPO_ROOT"/*) ;;
	*) die "OUTIMG must be under repo for docker: $OUTIMG" ;;
esac

KERNEL_REL="${KERNEL#$REPO_ROOT/}"
DTB_REL="${DTB#$REPO_ROOT/}"
ROOTFS_REL="${ROOTFS#$REPO_ROOT/}"
OUT_REL="${OUTIMG#$REPO_ROOT/}"
[ "$KERNEL_REL" != "$KERNEL" ] || KERNEL_REL="rootfs/boot/Image"
[ "$DTB_REL" != "$DTB" ] || DTB_REL="rootfs/boot/rk3588s-radxa-cm5-io.dtb"
[ "$ROOTFS_REL" != "$ROOTFS" ] || ROOTFS_REL="rootfs"
[ "$OUT_REL" != "$OUTIMG" ] || OUT_REL="$(basename "$OUTIMG")"

echo "==> compact hybrid (official head + small lin0 p3)"
echo "    official head: $((HEAD_BYTES / 1024 / 1024)) MiB (loader+GPT+p1+p2)"
echo "    lin0 p3:       ${P3_SIZE_MB} MiB @ LBA $P3_START_LBA"
echo "    total image:   $((TOTAL_BYTES / 1024 / 1024)) MiB  -> $OUTIMG"
echo "    rootfs/kernel: $ROOTFS / $KERNEL"

# Build truncated image: official prefix only (not full 4.5G), then zero-extend for p3
rm -f "$OUTIMG"
if [ "$FULL_CLONE" = "1" ]; then
	echo "==> FULL_CLONE=1 — copying entire official image..."
	if ! cp -c "$OFFICIAL_IMG" "$OUTIMG" 2>/dev/null; then
		dd if="$OFFICIAL_IMG" of="$OUTIMG" bs=8M status=progress
	fi
	P3_SECTS=8745673
	TOTAL_SECTS=$((P3_START_LBA + P3_SECTS))
	TOTAL_BYTES=$((TOTAL_SECTS * 512))
else
	echo "==> copying official head only ($((HEAD_BYTES / 1024 / 1024)) MiB)..."
	dd if="$OFFICIAL_IMG" of="$OUTIMG" bs=4M count=$(( (HEAD_BYTES + 4194303) / 4194304 )) status=progress 2>/dev/null || \
		dd if="$OFFICIAL_IMG" of="$OUTIMG" bs=1m count=$((HEAD_BYTES / 1048576 + 1))
	# Exact truncate to head, then extend for p3 payload
	python3 - "$OUTIMG" "$HEAD_BYTES" "$TOTAL_BYTES" << 'PY'
import sys
path, head, total = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
with open(path, "r+b") as f:
    f.truncate(head)
    f.seek(head)
    # sparse-friendly: write last byte of p3 region
    if total > head:
        f.seek(total - 1)
        f.write(b"\0")
print("image bytes", total)
PY
fi

echo "==> fix GPT p3 size + backup header for new disk end..."
python3 "$REPO_ROOT/scripts/gpt-resize-p3.py" "$OUTIMG" "$P3_START_LBA" "$P3_SECTS"

echo "==> populate p3 (mkfs + lin0)..."
chmod +x "$REPO_ROOT/scripts/hybrid-p3-inner.sh"
docker run --rm --privileged \
	-e P3_START_LBA="$P3_START_LBA" \
	-e P3_SECTS="$P3_SECTS" \
	-e ROOT_UUID="$ROOT_UUID" \
	-e ROOT_LABEL="$ROOT_LABEL" \
	-e KERNEL_REL="$KERNEL_REL" \
	-e DTB_REL="$DTB_REL" \
	-e ROOTFS_REL="$ROOTFS_REL" \
	-e OUT_REL="$OUT_REL" \
	-v "$REPO_ROOT:/work" \
	debian:bookworm-slim \
	bash /work/scripts/hybrid-p3-inner.sh

echo "==> verify"
python3 - << PY
from pathlib import Path
p = Path(r"""$OUTIMG""")
sz = p.stat().st_size
data = p.read_bytes()[: min(sz, 20 * 1024 * 1024)]
hdr = open(p, "rb").read()[64 * 512 : 64 * 512 + 4]
assert hdr in (b"RKNS", b"LDR "), hdr
# extlinux lives on p3 — may not appear in first 20M; open end region
tail = open(p, "rb")
tail.seek($P3_START_LBA * 512)
chunk = tail.read(min(64 * 1024 * 1024, $P3_SECTS * 512))
assert b"linux /boot/Image" in chunk or b"lin0 on official" in chunk, "missing extlinux on p3"
print("ok: size_MiB=%.1f loader=%r p3_has_extlinux=yes" % (sz / 1024 / 1024, hdr))
PY

ls -lh "$OUTIMG"
cat << EOF

Done: $OUTIMG  ($((TOTAL_BYTES / 1024 / 1024)) MiB target)

Official kept:  RKNS U-Boot, GPT, FAT p1/p2 (head only — not full Debian root)
lin0 on p3:     ${P3_SIZE_MB} MiB ext4, /boot/Image + extlinux (mmc 0:3 path)

Flash (much faster than 4.5G):
  rkdeveloptool db $REPO_ROOT/build/rk3588_spl_loader.bin
  rkdeveloptool wl 0 $OUTIMG
  rkdeveloptool rd

Tune size:  P3_SIZE_MB=96 $0
EOF
