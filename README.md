# Powkiddy RGB10 Max 3 Pro: ROCKNIX tools

Scripts and notes from setting up a Powkiddy RGB10 Max 3 Pro on ROCKNIX. Everything
here runs from the Ports menu, writes its results to a text file, and was built
and tested on this device.

**The device:** Amlogic A311D, four Cortex-A73 plus two A53, Mali-G52 MC2 on
Panfrost, 2 GB RAM, 854x480 screen. Most of this applies to any aarch64 ROCKNIX
handheld, but that is the only one it has run on.

**Why everything writes to a file:** launching a script from the Ports menu gives
you a black screen and then drops you back to EmulationStation. Console output is
effectively invisible, so every script here logs to disk and reports through
`pm_message` instead of `echo`.

## What is here

| | |
|---|---|
| [`renpy-hub/`](renpy-hub/) | Run any number of Ren'Py visual novels from one port folder, and build Ren'Py runtimes newer than the ones PortMaster ships |
| [`godot-hub/`](godot-hub/) | Run any number of Godot games from one port folder, with the engine version read out of each game's pack |
| [`tools/runelite/`](tools/runelite/) | Make RuneLite fit an 854x480 screen |
| [`tools/unzip-files/`](tools/unzip-files/) | Extract archives from the Ports menu, no SSH |
| [`tools/gog-installer/`](tools/gog-installer/) | Unpack GOG `.sh` installers on the device |
| [`tools/gallery/`](tools/gallery/) | Index and browse images, animations, video and audio with the gamepad |
| [`tools/port-diagnostics/`](tools/port-diagnostics/) | Collect everything needed to debug a failing port into one file |
| [`tools/github-upload/`](tools/github-upload/) | Push a folder to GitHub from the handheld itself, with no git and no PC |
| [`firefox/`](firefox/) | Controller mapping for the community Firefox installer |
| [`notes/`](notes/) | What was learned the hard way |

## Installing any of these

Copy the `.sh` file into your ports folder, next to the other launchers:

```
/storage/roms/ports/
```

or `/storage/games-external/roms/ports/` if that is the one your device uses.
Then refresh your gamelist, or restart EmulationStation, and the entry appears
under Ports. Anything with its own folder needs that folder copied alongside the
`.sh`, and its own README says so.

## The one worth reading first

[`notes/renpy-runtimes.md`](notes/renpy-runtimes.md). PortMaster's newest Ren'Py
runtime is 8.3.4, which leaves every visual novel built since mid-2025 with
nothing to run on. It turns out those runtimes are repackaged official Ren'Py
ARM builds, not something anyone compiled, and the ARM binaries come from a
separate `sdkarm` download most people never notice. So a newer runtime is a
packaging job, and [`renpy-hub/`](renpy-hub/) does it on the handheld in a few
minutes.

## Credits

Several of these build on other people's work. See [CREDITS.md](CREDITS.md).

MIT licensed, except where a bundled file carries its own license.
