# Godot hub

One port folder that runs any number of Godot games, each as its own entry in
the Ports menu. It reads the engine version out of each game's pack file and
picks the matching PortMaster runtime, so nothing has to be configured per game.

Covers Godot 3 through the FRT runtimes and Godot 4 through the `godot_4.x`
runtimes, including the Mono builds for C# games.

Not an official PortMaster port. It follows PortMaster's own Godot port
templates and uses PortMaster's runtimes.

## Install

Copy into your ports folder:

```
ports/Godot Scan.sh
ports/godot/
```

## Add a game

One folder per game, with the extracted download inside:

```
ports/godot/games/Some Game/game.pck
ports/godot/games/Other Game/OtherGame.exe
```

A separate `.pck` is ideal. An executable with the pack embedded also works:
the pack is carved out of it once, into `_embedded.pck`. Nested folders are
fine, so dumping an extracted zip in as-is usually just works.

Then run **Godot Scan**. It makes one launcher per game, named
`Godot - <folder name>`. Refresh your gamelist or restart EmulationStation to
see them. Run it again whenever you add or remove a game.

## How the version is detected

Every Godot pack starts with a 20-byte header:

```
offset 0   magic 'GDPC'
offset 4   pack format   1 = Godot 3, 2 = Godot 4
offset 8   version major
offset 12  version minor
offset 16  version patch
```

So the engine version is inside the file, always. Two packs from real ports:

```
merpworld.pck          pack format 2  ->  4.3.0   ->  godot_4.3
turbotabletennis.pck   pack format 1  ->  3.5.2   ->  frt_3.5.2
```

Both match the runtime the human porters chose by hand in those ports.

The scan picks the oldest runtime that is still new enough, which is the closest
match, and says in the report whether it was exact. Godot packs are usually
forward compatible within a major version, so a 4.1 pack on the 4.2 runtime
normally works. Unlike Ren'Py, Godot does not refuse outright: it either runs or
fails while loading resources.

C# games are detected by the .NET assemblies that ship beside the pack, and get
a `_mono` runtime. Without one they will not start, and the report says so.

## When a game needs tuning

Three optional files in `games/<name>/`:

| | |
|---|---|
| `runtime.txt` | one runtime name, e.g. `godot_4.4.1`, to override the guess |
| `args.txt` | one line of extra arguments, appended last so they win |
| `game.gptk` | a controller map, used only if present |

Most Godot games read the gamepad natively through SDL and need no `game.gptk`
at all. Add one only for a game driven by mouse or keyboard.

Useful things for `args.txt`:

```
--rendering-driver opengl3          instead of opengl3_es
--audio-driver PulseAudio           instead of ALSA
--resolution 640x480                render smaller than the screen
```

## How it runs them

PortMaster launches the two engine generations differently, and both profiles
here follow the official templates.

**Godot 3, FRT:** mount the runtime, prepend it to `PATH`, set
`FRT_NO_EXIT_SHORTCUTS` so Select does not quit the game, then run the FRT
binary with `--main-pack <pack> -sw`. The binary inside the squashfs has the
same name as the runtime.

**Godot 4:** mount the weston runtime as well, then go through
`westonwrap.sh headless noop kiosk crusty_x11egl` and run the Godot binary
inside it with the screen resolution, `-f --disable-cursor`,
`--rendering-driver opengl3_es` and `--audio-driver ALSA`. The binary is named
for its version, such as `godot43.aarch64`, and is found by globbing the mount
rather than by rebuilding that name.

`libcrusty.so` blocks stray pointer input under westonpack. It ships inside the
ports that need it rather than with the runtime, so the launcher looks for one
in your installed ports and continues without it if there is none.

## Logs

```
ports/godot/godot-scan.txt     what the scan found and why
ports/godot/logs/<name>.txt    that game's last launch, with the full command line
```

## What will not work

- Games needing Vulkan. The Mali-G52 goes through OpenGL ES here.
- C# games with no matching Mono runtime available.
- Anything heavy. 2 GB of RAM and a 6-core A311D is the ceiling, and a Godot 4
  game built for desktop can simply be too much.
- Games that need their own native libraries beyond the engine, such as FMOD or
  Steam integration.

## Prior art

[GodotMaster](https://github.com/simplicy/GodotMaster) by simplicy had this idea
first, for ArkOS and AmberELEC on RG351 devices. It ships its own FRT builds for
Godot 3.4.4 and 2.1.6, covers no Godot 4, and the runtime is chosen by editing
the scripts. This hub differs in reading the version from the pack, covering
Godot 4 and Mono, and using PortMaster's runtime set on ROCKNIX.
