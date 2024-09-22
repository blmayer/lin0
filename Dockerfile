FROM alpine:latest AS builder

ARG BUILDARCH

ADD rootfs-$BUILDARCH.tar.xz .

RUN rm -rf rootfs/share rootfs/sbin rootfs/var

FROM scratch

COPY --from=builder rootfs/ .

ENTRYPOINT ["/bin/sh"]
