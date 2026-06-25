#!/bin/sh
# Radxa CM5 + IO — official-hybrid image build (stock loader/GPT + lin0 on p3).
#
# Invoked by:  make radxacm5io
# Also:        ./scripts/build-radxacm5io-docker.sh
#
# Output (repo root):
#   lin0-radxacm5io.img       — flashable hybrid (~official head + lin0 p3)
#
# Requires:
#   - Docker (linux/arm64 builder + privileged loop for p3)
#   - Official Radxa CM5 IO image as loader/GPT donor, default path:
#       build/official-radxa-inspect/radxa-cm5-io_bookworm_cli_b3.output.img
#     (download rsdk bookworm CLI .img.xz, decompress into that dir)
#
# Optional env: LINUXVER (default master), OFFICIAL_IMG, P3_SIZE_MB (default 128)

set -e

REPO_ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

LINUXVER="${LINUXVER:-master}"
PLATFORM="${PLATFORM:-radxacm5io}"
OFFICIAL_IMG="${OFFICIAL_IMG:-$REPO_ROOT/build/official-radxa-inspect/radxa-cm5-io_bookworm_cli_b3.output.img}"
P3_SIZE_MB="${P3_SIZE_MB:-128}"

echo "lin0 platform=$PLATFORM (Radxa CM5 IO — official hybrid only)"
echo "  entry     : make radxacm5io"
echo "  linux     : $LINUXVER (mainline kernel for Image/DTB/rootfs)"
echo "  donor img : $OFFICIAL_IMG"
echo "  p3 size   : ${P3_SIZE_MB} MiB lin0 root"
echo "  image     : $REPO_ROOT/lin0-radxacm5io.img"
echo ""

if [ ! -f "$OFFICIAL_IMG" ]; then
	echo "error: official donor image not found:" >&2
	echo "  $OFFICIAL_IMG" >&2
	echo "" >&2
	echo "Hybrid keeps stock RKNS U-Boot + GPT p1/p2 from that image and puts lin0 only on p3." >&2
	echo "Get Radxa CM5 IO bookworm CLI from rsdk, decompress, place at the path above (or set OFFICIAL_IMG=)." >&2
	exit 1
fi

if ! docker info >/dev/null 2>&1; then
	echo "error: Docker is not running. Start Docker Desktop / colima, then:" >&2
	echo "  make radxacm5io" >&2
	exit 1
fi

BUILDER_TAG="lin0-radxacm5io-builder:latest"
echo "==> ensuring builder image $BUILDER_TAG"
docker build --platform linux/arm64 -t "$BUILDER_TAG" -f - "$REPO_ROOT" << 'DOCKERFILE'
FROM debian:bookworm-slim
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
	build-essential gcc g++ make bison flex bc kmod cpio rsync \
	gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu \
	libncurses-dev libssl-dev libelf-dev dwarves \
	git curl ca-certificates xz-utils bzip2 \
	python3 python3-dev python3-setuptools python3-pyelftools \
	device-tree-compiler u-boot-tools swig libgnutls28-dev \
	dosfstools e2fsprogs fdisk util-linux parted gdisk \
	musl-tools xxd \
	&& rm -rf /var/lib/apt/lists/*
WORKDIR /work
DOCKERFILE

echo "==> 1/2 kernel + rootfs (arm64 builder)"
docker run --rm --platform linux/arm64 \
	-e LINUXVER="$LINUXVER" \
	-e PLATFORM="$PLATFORM" \
	-v "$REPO_ROOT:/work" \
	-w /work \
	"$BUILDER_TAG" \
	/bin/sh /work/scripts/build-radxacm5io-inner.sh

echo "==> 2/2 official-hybrid image (privileged loop for p3)"
export ROOTFS="$REPO_ROOT/rootfs"
export OUTIMG="$REPO_ROOT/lin0-radxacm5io.img"
export OFFICIAL_IMG
export P3_SIZE_MB
sh "$REPO_ROOT/scripts/mkimg-radxacm5io-official-hybrid.sh"

echo ""
echo "Build finished (PLATFORM=$PLATFORM, official hybrid)."
ls -lh "$REPO_ROOT"/lin0-radxacm5io.img 2>/dev/null || true
echo ""
echo "Flash with rkdeveloptool (Maskrom), e.g.:"
echo "  rkdeveloptool wl 0 lin0-radxacm5io.img"
