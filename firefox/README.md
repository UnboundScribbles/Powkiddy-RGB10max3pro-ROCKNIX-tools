# Firefox controller mapping

`firefox.gptk` maps this device's gamepad to Firefox: right stick moves the
pointer, L3 and R3 click, Y sends F12 for the onscreen keyboard toggle.

## What is not here

The Firefox installer itself. That is a separate community project aimed at the
Retroid Pocket Flip 2, which downloads Mozilla's official ARM64 Firefox build at
install time and installs everything under `/storage` without touching the
immutable system partition. It arrived without a license file or an author name,
so it is not redistributed here.

If you have that installer, this mapping is the piece that makes it work on a
Powkiddy RGB10 Max 3 Pro. The Flip 2 version relies on InputPlumber for controller
input; this device does not have that, so gptokeyb does the job instead, the same
way every PortMaster port does it.

Firefox is Mozilla's. Neither that project nor this one is affiliated with
Mozilla or ROCKNIX.

## Used by

`tools/gallery/Gallery.sh` opens its generated page in Firefox with the browser
UI hidden.
