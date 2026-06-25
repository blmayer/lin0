#!/usr/bin/env python3
"""Resize GPT partition 3 (1-based entry index 2) and rewrite backup GPT for a shorter disk.

Usage: gpt-resize-p3.py IMAGE P3_START_LBA P3_SECTOR_COUNT

Keeps partition 1/2 entries; updates p3 last LBA, header current/backup LBAs,
partition-array CRC, header CRC, and writes backup header + entries at disk end.
"""
from __future__ import annotations

import struct
import sys
import zlib


def crc32(data: bytes) -> int:
    return zlib.crc32(data) & 0xFFFFFFFF


def main() -> int:
    if len(sys.argv) != 4:
        print(__doc__, file=sys.stderr)
        return 2
    path = sys.argv[1]
    p3_start = int(sys.argv[2])
    p3_sects = int(sys.argv[3])
    p3_last = p3_start + p3_sects - 1
    # disk last usable LBA = p3_last; backup GPT header at last LBA+1 typically = total-1
    # Standard: LBA0 PMBR, LBA1 primary header, LBA2.. primary entries
    # backup entries just before backup header; backup header at last LBA of disk
    disk_last_lba = p3_last + 1  # header sits after usable? Actually usable is up to backup_lba-1
    # On official image: partitions end, then backup GPT. Usable last = p3_last for our layout
    # Place backup header at p3_last+33 (32 entry sectors + 1 header) if room, else tight:
    # Minimal: backup entries at p3_last-32 .. p3_last-1, backup header at p3_last — WRONG overlaps p3.
    # Correct layout for truncated image ending at sector TOTAL-1 where TOTAL = p3_start+p3_sects
    # Primary uses LBA 0..p3_last inclusive as data for p3. Backup GPT must live AFTER p3.
    # So total sectors = p3_last + 1 + 33 (32 entry LBAs + 1 backup header) = p3_start+p3_sects+33
    # Simpler approach used by many tools: extend file by 34 sectors for backup GPT only.

    with open(path, "r+b") as f:
        f.seek(0, 2)
        file_bytes = f.tell()

        # Read primary header at LBA 1
        f.seek(512)
        hdr = bytearray(f.read(92))
        if hdr[:8] != b"EFI PART":
            print("error: no EFI PART at LBA1", file=sys.stderr)
            return 1

        entr_lba = struct.unpack_from("<Q", hdr, 72)[0]
        num_entr = struct.unpack_from("<I", hdr, 80)[0]
        entr_sz = struct.unpack_from("<I", hdr, 84)[0]
        entr_bytes = num_entr * entr_sz

        f.seek(entr_lba * 512)
        entries = bytearray(f.read(entr_bytes))

        # Entry 2 (index 2) = partition 3
        off = 2 * entr_sz
        type_guid = entries[off : off + 16]
        if type_guid == b"\x00" * 16:
            print("error: GPT entry 3 empty", file=sys.stderr)
            return 1
        first = struct.unpack_from("<Q", entries, off + 32)[0]
        if first != p3_start:
            # still apply resize from given start
            struct.pack_into("<Q", entries, off + 32, p3_start)
            first = p3_start
        struct.pack_into("<Q", entries, off + 40, p3_last)

        # Total disk LBAs: data through p3_last, then 33 LBAs for backup GPT (32 entries + header)
        # entry array size in LBAs
        entr_lbas = (entr_bytes + 511) // 512
        backup_hdr_lba = p3_last + 1 + entr_lbas
        backup_entr_lba = p3_last + 1
        disk_lba_count = backup_hdr_lba + 1  # LBAs 0..backup_hdr_lba inclusive
        need_bytes = disk_lba_count * 512
        if file_bytes < need_bytes:
            f.seek(need_bytes - 1)
            f.write(b"\0")
        elif file_bytes > need_bytes:
            f.truncate(need_bytes)

        # Partition entry CRC
        entr_crc = crc32(bytes(entries))
        struct.pack_into("<I", hdr, 88, entr_crc)

        # Header fields: my LBA=1, alt=backup_hdr_lba, first usable=34?, last usable=p3_last
        # Preserve first usable from original if sensible
        first_usable = struct.unpack_from("<Q", hdr, 40)[0]
        struct.pack_into("<Q", hdr, 24, 1)  # current LBA
        struct.pack_into("<Q", hdr, 32, backup_hdr_lba)  # backup LBA
        struct.pack_into("<Q", hdr, 40, first_usable)
        struct.pack_into("<Q", hdr, 48, p3_last)  # last usable LBA
        struct.pack_into("<Q", hdr, 72, entr_lba)
        struct.pack_into("<I", hdr, 88, entr_crc)

        # Zero header CRC field then compute
        struct.pack_into("<I", hdr, 16, 0)
        hdr_crc = crc32(bytes(hdr[:92]))
        struct.pack_into("<I", hdr, 16, hdr_crc)

        # Write primary header + entries
        f.seek(512)
        f.write(hdr[:92])
        # pad header sector
        f.write(b"\x00" * (512 - 92))
        f.seek(entr_lba * 512)
        f.write(entries)

        # Backup entries
        f.seek(backup_entr_lba * 512)
        f.write(entries)
        # pad to entr_lbas
        pad = entr_lbas * 512 - entr_bytes
        if pad > 0:
            f.write(b"\x00" * pad)

        # Backup header: swap current/backup LBA, entry LBA = backup_entr_lba
        bhdr = bytearray(hdr)
        struct.pack_into("<Q", bhdr, 24, backup_hdr_lba)
        struct.pack_into("<Q", bhdr, 32, 1)
        struct.pack_into("<Q", bhdr, 72, backup_entr_lba)
        struct.pack_into("<I", bhdr, 16, 0)
        bcrc = crc32(bytes(bhdr[:92]))
        struct.pack_into("<I", bhdr, 16, bcrc)
        f.seek(backup_hdr_lba * 512)
        f.write(bhdr[:92])
        f.write(b"\x00" * (512 - 92))

        # Protective MBR partition size (optional): set to disk end
        f.seek(446)
        # one entry type EE
        mbr_part = bytearray(f.read(16))
        if mbr_part[4] == 0xEE:
            # sectors 1..disk_lba_count-1
            struct.pack_into("<I", mbr_part, 8, 1)
            struct.pack_into("<I", mbr_part, 12, min(disk_lba_count - 1, 0xFFFFFFFF))
            f.seek(446)
            f.write(mbr_part)

    print(
        f"GPT p3 LBA {p3_start}..{p3_last} ({p3_sects} sect), "
        f"backup_hdr LBA {backup_hdr_lba}, file {need_bytes} bytes "
        f"({need_bytes / 1024 / 1024:.1f} MiB)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
