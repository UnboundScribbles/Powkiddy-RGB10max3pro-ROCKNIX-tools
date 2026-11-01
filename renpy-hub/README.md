# Ren'Py hub

One port folder that runs any number of Ren'Py visual novels, each as its own
entry in the Ports menu, plus a way to build Ren'Py runtimes newer than the ones
PortMaster ships.

Not an official PortMaster port. It uses PortMaster's Ren'Py runtimes the same
way PortMaster's own Ren'Py ports do, and its launcher is modelled on them.

## Install

Copy into your ports folder:

```
ports/RenPy Scan.sh
ports/RenPy Build Runtime.sh
ports/renpy/
```

Then install any PortMaster Ren'Py port once, to pull a runtime down:
"Do NOT Take This Cat Home" gives you `renpy_8.3.4`, "Butterfly Soup" gives you
`renpy_8.1.3`.

## Add a game

One folder per game, each holding the game's `game` folder, taken from the PC
download:

```
ports/renpy/games/Butterfly Soup/game/...
ports/renpy/games/Some Other VN/game/...
```

Dumping the whole extracted download works too. If `<name>/game` is missing, one
level deeper is checked, so `games/Some VN/SomeVN-1.0-pc/game/` is found.

Then run **RenPy Scan**. It makes one launcher per game, named
`RenPy - <folder name>`. Refresh your gamelist or restart EmulationStation to see
them. Run it again whenever you add or remove a game.

## Which games work

Scan reads each game's `game/script_version.txt` and assigns the oldest runtime
still new enough to read it. A game built with a newer Ren'Py than anything
installed is reported as too new rather than left to fail at launch.

PortMaster's newest is 8.3.4, which covers games built up to around July 2025.
For anything newer, build a runtime.

## Build a newer runtime

Nothing is compiled. PortMaster's runtimes are official Ren'Py ARM builds,
repackaged, and the ARM binaries come from a separate download.

1. Download the **sdkarm** tarball, not the plain sdk:

   ```
   https://www.renpy.org/dl/8.5.2/renpy-8.5.2-sdkarm.tar.bz2
   ```

   renpy.org lists it as "ARM Linux (Raspberry Pi and Chromebook)". The plain
   `renpy-8.5.2-sdk.tar.bz2` has only x86_64, Mac and Windows binaries inside.

2. Put the archive, as downloaded, in `ports/renpy/sdk/`.
3. Run **RenPy Build Runtime**. It extracts, verifies, and assembles
   `ports/renpy/runtimes/renpy_8.5.2/`.
4. Run **RenPy Scan**.
5. Delete `ports/renpy/sdk/` to get the space back.

Runtimes accumulate rather than conflict, so games spread across whichever ones
are present. Full write-up in [`../notes/renpy-runtimes.md`](../notes/renpy-runtimes.md).

## Saves

Each game keeps its own in `games/<name>/conf`, so a game folder is portable and
nothing is shared between games.

## Controls

| | |
|---|---|
| A, Start | Enter, advance dialogue |
| Back | Esc, menu |
| D-pad, left stick | arrow keys |
| L1, R1 | Tab, skip |
| X | H, hide the interface |
| Y | Ctrl held, fast skip |

Edit `renpy/renpy.gptk` to change these. It applies to every game. For games that
need a real mouse pointer see
[`../notes/mouse-cursor-libcrusty.md`](../notes/mouse-cursor-libcrusty.md).

## Force a runtime

Put a runtime name in `games/<name>/runtime.txt`, e.g. `renpy_8.1.3`, then
rescan.

## Logs

```
ports/renpy/renpy-scan.txt        what the scan found
ports/renpy/build-runtime.txt     the last runtime build
ports/renpy/logs/<name>.txt       that game's last launch
```

## How it works

`RenPy Scan` writes a thin wrapper per game; all of them call `renpy/run.sh`
with the game name, runtime and path. `run.sh` mounts the runtime (or uses an
unpacked runtime folder directly), lays the game's assets over the runtime's
empty `game/` directory with a bind mount, and runs Ren'Py's own `startRENPY`.
If a game dies quickly with a script-loading error it retries on the other
installed runtimes before giving up.
