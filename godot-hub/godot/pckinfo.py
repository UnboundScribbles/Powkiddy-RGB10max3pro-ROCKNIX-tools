#!/usr/bin/env python3
"""Work out which Godot engine built a game, by reading its pack file.

A Godot .pck starts with a 20-byte header:

    offset 0   magic          'GDPC'
    offset 4   pack format    1 for Godot 3, 2 for Godot 4
    offset 8   version major
    offset 12  version minor
    offset 16  version patch

So the engine version is in the file itself, always, with nothing optional
about it. That is what makes a Godot hub possible: the right runtime can be
chosen without asking the player anything.

Many itch.io games ship a single executable with the pack embedded instead of a
separate .pck. Those end with:

    [uint64 pack size][magic 'GDPC']

and the pack itself starts at  eof - size - 12. Godot only runs an embedded
pack when it is the executable being run, so for a hub the pack is carved out
into a .pck of its own, which --main-pack can then load.

Usage:
    pckinfo.py <game-folder> [--extract]

Prints shell-assignable lines. PCK_OK=1 means the rest is usable.
"""

import os
import struct
import sys

MAGIC = b"GDPC"
HEADER = 20
FOOTER = 12
# Anything smaller than this is not a game pack.
MIN_PCK = 64
# Extensions worth probing for an embedded pack, plus any extensionless file.
BINARY_EXT = (".exe", ".x86_64", ".x86", ".bin", ".elf", ".arm64", ".aarch64",
              ".64", ".32", ".app")


def read_header(fh, offset=0):
    """Return (pack_format, major, minor, patch) or None if no pack here."""
    try:
        fh.seek(offset)
        if fh.read(4) != MAGIC:
            return None
        return struct.unpack("<IIII", fh.read(16))
    except (OSError, struct.error):
        return None


def find_embedded(path):
    """Return (offset, size, header) for a pack inside a binary, or None."""
    try:
        size = os.path.getsize(path)
        if size < HEADER + FOOTER:
            return None
        with open(path, "rb") as fh:
            fh.seek(size - 4)
            if fh.read(4) != MAGIC:
                return None
            fh.seek(size - FOOTER)
            pack_size = struct.unpack("<Q", fh.read(8))[0]
            if pack_size < MIN_PCK or pack_size > size:
                return None

            # Where Godot itself looks. Verified by checking the magic lands
            # there rather than trusting the arithmetic.
            offset = size - pack_size - FOOTER
            head = read_header(fh, offset) if offset >= 0 else None

            if head is None:
                # Some exporters count the footer differently. Try the obvious
                # neighbours before giving up.
                for cand in (size - pack_size, size - pack_size - 8,
                             size - pack_size - 4):
                    if cand < 0:
                        continue
                    head = read_header(fh, cand)
                    if head is not None:
                        offset = cand
                        break

            if head is None:
                return None
            return offset, pack_size, head
    except OSError:
        return None


def carve(src, offset, size, dest):
    """Copy an embedded pack out into a .pck of its own."""
    with open(src, "rb") as fin, open(dest, "wb") as fout:
        fin.seek(offset)
        left = size
        while left > 0:
            chunk = fin.read(min(1 << 20, left))
            if not chunk:
                break
            fout.write(chunk)
            left -= len(chunk)
    return os.path.getsize(dest)


def looks_binary(name):
    low = name.lower()
    if low.endswith(BINARY_EXT):
        return True
    # Godot's Linux export often has no extension at all.
    return "." not in os.path.basename(low)


def detect_mono(folder):
    """C# games ship .NET assemblies beside the pack."""
    for dirpath, dirnames, filenames in os.walk(folder):
        for n in filenames:
            low = n.lower()
            if low.endswith(".dll") or low.startswith("godotsharp"):
                return True
        for d in dirnames:
            if d.lower().startswith("data_") or d.lower() == "mono":
                return True
    return False


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    extract = "--extract" in sys.argv
    if not args:
        print("PCK_OK=0")
        print("PCK_ERROR=no folder given")
        return 1
    folder = os.path.abspath(args[0])

    if not os.path.isdir(folder):
        print("PCK_OK=0")
        print("PCK_ERROR=not a folder")
        return 1

    # A standalone .pck is the straightforward case, and the biggest one wins
    # when a game ships several (DLC packs are usually smaller than the game).
    pcks = []
    binaries = []
    for dirpath, dirnames, filenames in os.walk(folder):
        dirnames[:] = [d for d in dirnames if d not in (".git", "conf")]
        for n in filenames:
            full = os.path.join(dirpath, n)
            if n.lower().endswith(".pck"):
                pcks.append(full)
            elif looks_binary(n):
                binaries.append(full)

    pick = None
    for cand in sorted(pcks, key=lambda p: -os.path.getsize(p)):
        with open(cand, "rb") as fh:
            head = read_header(fh)
        if head:
            pick = (cand, head, False, None, None)
            break

    if pick is None:
        # No usable .pck, so look inside the executables.
        for cand in sorted(binaries, key=lambda p: -os.path.getsize(p)):
            found = find_embedded(cand)
            if found:
                offset, size, head = found
                pick = (cand, head, True, offset, size)
                break

    if pick is None:
        print("PCK_OK=0")
        print("PCK_ERROR=no Godot pack found in this folder")
        return 1

    path, head, embedded, offset, size = pick
    pack_format, major, minor, patch = head

    out_path = path
    extracted = 0
    if embedded:
        dest = os.path.join(folder, "_embedded.pck")
        if extract:
            if not os.path.exists(dest) or os.path.getsize(dest) != size:
                written = carve(path, offset, size, dest)
                if written != size:
                    print("PCK_OK=0")
                    print("PCK_ERROR=carving the embedded pack came up short")
                    return 1
            extracted = 1
            out_path = dest
        elif os.path.exists(dest) and os.path.getsize(dest) == size:
            extracted = 1
            out_path = dest

    print("PCK_OK=1")
    print("PCK_PATH=%s" % os.path.relpath(out_path, folder))
    print("PCK_SOURCE=%s" % os.path.relpath(path, folder))
    print("PACK_FORMAT=%d" % pack_format)
    print("GODOT_MAJOR=%d" % major)
    print("GODOT_MINOR=%d" % minor)
    print("GODOT_PATCH=%d" % patch)
    print("GODOT_VERSION=%d.%d.%d" % (major, minor, patch))
    print("EMBEDDED=%d" % (1 if embedded else 0))
    print("EXTRACTED=%d" % extracted)
    print("MONO=%d" % (1 if detect_mono(folder) else 0))
    return 0


if __name__ == "__main__":
    sys.exit(main())
