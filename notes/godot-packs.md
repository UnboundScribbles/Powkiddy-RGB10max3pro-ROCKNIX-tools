# Reading a Godot game's engine version from its pack

Everything about running arbitrary Godot games on a handheld depends on one
question: which engine version built this game. The answer is in the file.

## The header

A `.pck` starts with 20 bytes:

```
offset 0    magic 'GDPC'
offset 4    pack format    1 = Godot 3.x, 2 = Godot 4.x
offset 8    version major
offset 12   version minor
offset 16   version patch
```

Two packs taken from real PortMaster ports:

```
merpworld.pck          GDPC  format 2  ->  4.3.0
turbotabletennis.pck   GDPC  format 1  ->  3.5.2
```

Those ports' own launchers set `godot_runtime="godot_4.3"` and
`runtime="frt_3.5.2"` by hand. So five integers out of the file reproduce what a
human porter decided.

This is better than Ren'Py's equivalent. Ren'Py games carry
`game/script_version.txt`, which is a separate optional file. The pck header is
mandatory and sits in the first 20 bytes of the only file that must exist.

## Packs embedded in an executable

Most itch.io Godot games ship a single executable rather than a loose `.pck`.
Those end with:

```
[uint64 pack size][magic 'GDPC']
```

and the pack begins at `eof - size - 12`. Godot runs an embedded pack only when
it is the executable being run, so for a hub the pack has to be carved out into
a `.pck` of its own, which `--main-pack` can then load. Verify by checking that
`GDPC` really is at the computed offset rather than trusting the arithmetic:
exporters have differed on whether the size counts the footer.

## Mapping a version to a PortMaster runtime

- pack format 1 goes to an `frt_*` runtime. FRT is a separate Godot 3 build for
  embedded devices, and PortMaster ships around ten versions.
- pack format 2 goes to a `godot_4.*` runtime, of which there are about fifteen,
  each with a `_mono` variant for C# games.

Pick the oldest runtime that is still at or above the game's version, which is
the closest match. Godot packs are usually forward compatible within a major
version, so a 4.1 pack on the 4.2 runtime normally works. Godot does not refuse
a newer pack the way Ren'Py does; it either runs or fails while loading
resources, which makes a nearest-match guess worth trying.

## C# games

A C# game ships .NET assemblies beside the pack, so `*.dll` files or a `data_*`
folder are the tell. These need a `_mono` runtime and will not start without
one.

## Runtime naming

Two inconsistencies worth knowing before hardcoding anything:

- An FRT runtime's binary has the same name as the runtime: `frt_3.5.2`.
- A Godot 4 runtime's binary is the version with the dots removed, plus the
  architecture: `godot_4.3` holds `godot43.aarch64`, and `godot_4.2.2` holds
  `godot422.aarch64`.

Globbing the mounted runtime for `godot*.$DEVICE_ARCH` is more reliable than
rebuilding that name from the version.
