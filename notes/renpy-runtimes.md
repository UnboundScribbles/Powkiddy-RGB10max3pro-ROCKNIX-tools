# Ren'Py on ROCKNIX: why new visual novels fail, and how to fix it

## The symptom

A Ren'Py game starts, then dies during loading with:

```
Exception: Could not load from archive gui.rpyc
```

## The cause

A Ren'Py game's scripts ship as compiled bytecode, stamped with the version of
Ren'Py that built them. The version is in plain text at:

```
game/script_version.txt        e.g.  (8, 5, 2)
```

A Ren'Py runtime reads its own version or older, never newer. PortMaster's
newest aarch64 runtime is **8.3.4**, so any game built with 8.4 or 8.5 fails.
Ren'Py 8.4 was released 13 July 2025, which means roughly everything built since
then is affected.

**Check `game/script_version.txt` before downloading gigabytes.** It is the whole
compatibility question in one line.

## What PortMaster's runtimes actually are

Unpacking `renpy_8.3.4.squashfs` answers this. Inside:

```
startRENPY            Ren'Py's own renpy.sh, renamed
startRENPY.py         Ren'Py's own renpy.py, renamed
game/                 empty, the game's assets get laid over it
renpy/                the engine, plain Python, architecture independent
lib/py3-linux-aarch64/   librenpython.so, python, pythonw, startRENPY, zsync
lib/python3.12/          the matching Python standard library
```

and `renpy/vc_version.py` says:

```
official = True
version = '8.3.4.24120703'
```

So it is an **official upstream Ren'Py build, repackaged**. Nothing was compiled
by PortMaster. Ren'Py's own build system lists `Platform("linux", "aarch64")`
among its targets, so the ARM64 binaries come from upstream.

`startRENPY` is `renpy.sh` verbatim: it works out the platform from `uname`,
resolves `lib/py3-linux-$(uname -m)`, and then execs the binary whose filename
matches its own. That is why both the script and the binary have to be called
`startRENPY`, and why `renpy.py` becomes `startRENPY.py`.

## The part that is easy to miss

Ren'Py publishes **two** SDK tarballs per release:

| File | Contains |
|---|---|
| `renpy-X.Y.Z-sdk.tar.bz2` | x86_64 Linux, Mac universal, Windows x86_64 |
| `renpy-X.Y.Z-sdkarm.tar.bz2` | the above plus **ARM Linux** |

renpy.org labels the second one "ARM Linux (Raspberry Pi and Chromebook)". Note
there is no hyphen before `arm`. The plain `sdk` download has no
`lib/py3-linux-aarch64` folder at all, so it is useless for a handheld.

```
https://www.renpy.org/dl/8.5.2/renpy-8.5.2-sdkarm.tar.bz2
```

Ren'Py's own docs mention this in passing, in Building Distributions: the Linux
package "will also include the 32-bit and 64-bit ARM version of Ren'Py, if
present", and those files come from the `sdkarm` package.

## Building a runtime

`renpy-hub/RenPy Build Runtime.sh` does this on the device:

1. Put `renpy-8.5.2-sdkarm.tar.bz2` in `ports/renpy/sdk/`, as downloaded.
2. Run **RenPy Build Runtime** from the Ports menu. It extracts the archive with
   whichever of `tar`, `unzip` or PortMaster's `7zzs` works, reads the version
   out of `renpy/vc_version.py`, checks `lib/py3-linux-aarch64` is really there,
   and assembles `ports/renpy/runtimes/renpy_8.5.2/`.
3. Run **RenPy Scan**. Games get matched to the oldest runtime that is still new
   enough to read them.

No `mksquashfs` needed: the hub treats an unpacked runtime folder exactly like one
of PortMaster's squashfs runtimes.

## Things that cost time

- **tar "fails" but worked.** On exFAT or FAT cards tar cannot set ownership or
  timestamps, so it prints a wall of `Cannot change ownership` and exits
  non-zero with every file correctly extracted. Judge extraction by whether the
  files are there, not by the exit code. `--no-same-owner --no-same-permissions`
  avoids the noise.
- **Zip downloads lose the execute bit.** A `.zip` has no unix permissions, so
  the binaries come out non-executable and the runtime silently does nothing.
  Prefer `.tar.bz2`, and `chmod +x` afterwards regardless.
- **bzip2 is slow on an A311D.** A 146 MB `sdkarm` takes minutes. The black
  screen is not a hang.
- **Two python directories.** The 8.3.4 runtime carries both `lib/python3.9` and
  `lib/python3.12`. Pick the newest, not the first one `ls` returns.

## Version reference

| Ren'Py | Released | Runs on PortMaster's 8.3.4? |
|---|---|---|
| 8.1.3 | Sep 2023 | yes |
| 8.3.4 | Dec 2024 | yes |
| 8.4.0 | 13 Jul 2025 | **no** |
| 8.5.x | 2026 | **no** |

Anything built before roughly July 2025 is likely fine as-is. Newer needs a
runtime built from the matching `sdkarm`.
