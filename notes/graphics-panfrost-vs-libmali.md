# Panfrost vs libmali, and the error that gives it away

ROCKNIX can use either of two GPU drivers on Mali hardware. Panfrost is the open
source one with real OpenGL support. libmali is ARM's proprietary driver, which
on these devices provides OpenGL ES but not the desktop OpenGL that many ports
need.

## The tell

A port dies at startup with something like:

```
GLFW Error: GLX: Failed to create context: GLXBadFBConfig
```

That is almost always libmali, not a broken port and not a controller problem. I
watched someone chase control mappings for a month on GTA3 and Vice City ports
while this was the actual cause.

## How a port checks

The PortMaster OpenMW port refuses to start rather than fail obscurely:

```sh
if [ -e /usr/bin/gpudriver ]; then
    GPUDRIVER=$(/usr/bin/gpudriver)
    if [ "$GPUDRIVER" = "libmali" ]; then
        pm_message "This Port does not support the libMali graphics driver. Switch to Panfrost to continue."
        exit 1
    fi
else
    if ! glxinfo | grep "OpenGL version string"; then
        pm_message "This Port does not support the libMali graphics driver. Switch to Panfrost to continue."
        exit 1
    fi
fi
```

Worth copying into anything that needs desktop GL. `glxinfo | grep "OpenGL
version string"` is the portable check when `/usr/bin/gpudriver` is absent.

On this device Panfrost reports:

```
OpenGL version string: 3.1 Mesa 26.2.2
```

## Switching

ROCKNIX exposes the choice in its own system settings. Which ports need which
varies, so it is worth knowing where that toggle is before blaming a port.

## Related

Several ports also set `SDL_VIDEODRIVER=x11` specifically on ROCKNIX, and remove
a bundled `libX11.so.6` on builds newer than `20250517` because the bundled copy
breaks things. If a port works everywhere except ROCKNIX, the launcher's
ROCKNIX branch is the place to look.
