# Credits

Nothing here exists without the work below.

## PortMaster

MIT licensed, copyright (c) 2021 christianhaitian.
<https://github.com/PortsMaster/PortMaster-New>

Every script here uses PortMaster's `control.txt` environment: `$directory`,
`$ESUDO`, `get_controls`, `pm_message`, `pm_finish`, `gptokeyb` and the runtime
mounting helpers. The Ren'Py launcher in `renpy-hub/renpy/run.sh` is modelled
directly on PortMaster's own Ren'Py ports, in particular the "Do NOT Take This
Cat Home" launcher by **Dia**, which is where the squashfs-mount-then-bind-the-game
pattern comes from.

PortMaster's Ren'Py runtimes (`renpy_8.1.3`, `renpy_8.3.4`) are what the hub uses
when a game is old enough for them.

## Ren'Py

GNU LGPL and other licenses, copyright Tom Rothamel and the Ren'Py contributors.
<https://www.renpy.org/>

`renpy-hub/RenPy Build Runtime.sh` repackages files from Ren'Py's official
`sdkarm` distribution. It does not modify them, and no Ren'Py files are included
in this repository. `renpy-hub/renpy/Licenses/LICENSE-renpy.txt` is Ren'Py's
license text, carried over from the PortMaster port.

## gl4es

MIT licensed, copyright (c) 2016-2018 Sebastien Chevalier, (c) 2013-2016 Ryan
Hileman. <https://github.com/ptitSeb/gl4es>

`renpy-hub/renpy/gl4es.aarch64/` contains gl4es `libGL.so.1` and `libEGL.so.1`
as shipped in PortMaster's Ren'Py port, with the license text alongside them.

## Firefox for ROCKNIX

**Not included here, and not my work.** `firefox/` holds only a gptokeyb mapping
for this device. The installer itself is a separate community project targeting
the Retroid Pocket Flip 2, which downloads Mozilla's official ARM64 Firefox at
install time. It shipped without a license or an author name, so it is not
redistributed in this repository. See [`firefox/README.md`](firefox/README.md).

Firefox is Mozilla's, and neither that project nor this one is affiliated with
Mozilla or ROCKNIX.

## FRT

By Emanuele Fornara. <https://github.com/efornara/frt>

A Godot 3 build for embedded devices, and what PortMaster's `frt_*` runtimes
are. Every Godot 3 game the Godot hub runs goes through it.

## GodotMaster

By simplicy. <https://github.com/simplicy/GodotMaster>

Prior art for the Godot hub: the same idea of a games folder plus a scan that
generates launchers, for ArkOS and AmberELEC on RG351 devices. It ships its own
FRT builds, covers no Godot 4, and picks the runtime by editing scripts. The hub
here was written independently against PortMaster's runtimes and the pack
header, but the shape of the idea was theirs first.

## PortMaster Wiki

<https://jantrueno.github.io/PortMaster-Wiki/>

The script templates and runtime list. Both Godot launch profiles in
[`godot-hub/`](godot-hub/) follow the official Godot 3 and Godot 4 templates.

## ROCKNIX

<https://github.com/ROCKNIX/distribution>

And thanks to **porschemad911** for turning a kernel config report into a fix the
same week. See [`notes/usb-storage-s922x.md`](notes/usb-storage-s922x.md).

## Other projects these scripts lean on

- **plox** and **openmw_esmm**, the mod sorter and mod manager bundled in the
  PortMaster OpenMW port, by **bmdhacks**, **kloptops**, **saint** and
  **BinaryCounter**
- **xdelta3**, **7-Zip** and **innoextract**, all shipped by PortMaster and used
  by the GOG installer extractor
- **RuneLite**, for having a config format that can be understood from source
