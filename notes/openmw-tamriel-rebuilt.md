# OpenMW on the handheld: mods, Tamriel Rebuilt, and the Lua version wall

Running the PortMaster Morrowind port (OpenMW) with a manual mod setup on 2 GB of
RAM.

## Which openmw.cfg

There are two, and the port adds a third wrinkle.

- The one shipped beside the binary contains `config="?userconfig?"` and only
  `data=./resources/vfs-mw`. **Do not edit it.**
- The user config is the one to edit. `openmw.log` names both at startup:

  ```
  Loading config file: /storage/roms/ports/openmw/openmw.cfg
  Loading config file: /roms/ports/openmw/openmw/openmw.cfg
  ```

- **The port's mod manager rewrites one of them.** `openmw_esmm` runs before the
  game, sorts your load order with `plox`, and ends with `Saving configuration to
  /roms/ports/openmw/openmw/openmw.cfg`. Hand edits to that file can be
  reordered or overwritten. Add mods, then let it sort.

## How the lines work

- `data=` lines are VFS layers. Later lines win, so an add-on goes **after** the
  core it patches.
- Point `data=` at the folder that directly contains `Meshes`, `Textures` and the
  plugin, not at the download's root.
- `content=` is the load order. Masters come before anything that depends on
  them.
- BSAs need a `fallback-archive=` line.
- `.omwscripts` and `.omwaddon` files get `content=` lines like any plugin.
- Paths with spaces are fine. Do not quote them.

## Tamriel Rebuilt

Two separate downloads, and the order matters:

```
data=<Tamriel_Data>/00 Data
data=<Tamriel_Data>/01 Data Files - Normal Maps      (optional, after 00)
data=<Tamriel Rebuilt>/00 Core/Data Files
data=<Tamriel Rebuilt>/01 Faction Integration/Data Files   (optional)
```

```
content=Tamriel_Data.esm
content=Tamriel_Data.omwscripts
content=TR_Mainland.esm
content=tamrielrebuilt.omwscripts
```

Then `TR_Factions.esp`, `JASPR-TR.ESP` and `MorrowindInteriorsProject_TR.ESP`
once the base four load.

The Tamriel Rebuilt download holds the plugin and scripts; nearly all of its art
lives in Tamriel_Data, which is why both are needed.

Normal maps are off by default in OpenMW. To use `01 Data Files - Normal Maps`,
set this in `settings.cfg`:

```
[Shaders]
auto use object normal maps = true
```

Add it only after Tamriel Rebuilt boots, since it costs texture memory and GPU
time.

## Memory

`TR_Mainland.esm` is about 230 MB and OpenMW reads the whole plugin at startup.
On 2 GB shared with the OS and GPU, expect a long first load. If the game closes
during loading with nothing on screen, suspect memory first and check how far
`openmw.log` got.

## The Lua version wall

Some mods refuse to load, reporting that OpenMW is too old. The port is a
development snapshot, not a release:

```
openmw/resources/version:
  0.51.0
  e8c8a6c5cc86e46160fd99ead0edbce29cc4e74b
  47d78e004bc182def2904986f8bb54aea1f4b3ae
```

Built 2026-04-12 from upstream `master` after the 0.50 release candidate, with
handheld patches: resolution scaling, ASTC texture support, an on-screen
keyboard, Lua profiling off by default, and some components dropped to shrink the
binary. OpenMW 0.51.0 proper was released 19 June 2026, so this sits before it.

Every `.omwscripts` mod targets a Lua API revision, and the engine refuses
anything newer than it supports. So a mod updated after the build's cutoff will
not run, regardless of the mod being correct.

Options, in order of sanity:

1. Use an older release of the mod, chosen by the API revision its changelog
   mentions rather than by date.
2. Comment out that `content=` line. A missing optional script is better than a
   broken load order.
3. Do not swap the engine binary. The port's patches are what make it usable on
   this hardware, and `resources/` and the binary must come from the same build.
   A mismatch produces this at startup:

   ```
   Resources dir ... doesn't match OpenMW binary, the game may work incorrectly
   ```

Rolling Tamriel_Data back on its own is a bad idea: it is versioned together with
Tamriel Rebuilt, so a mismatch can break `TR_Mainland.esm`.

## Harmless log noise

Worth knowing so you do not chase it:

- `Attempting to fullscreen app_id=... "error": "No matching node."` repeated
  several times at startup
- `Warning: invalid OSG_NOTIFY_LEVEL set (ERROR)`
- `Failed to create message #{OMWEngine:ResolutionScale}`, one missing menu label
- a MyGUI exception at shutdown, after a session that ran fine
