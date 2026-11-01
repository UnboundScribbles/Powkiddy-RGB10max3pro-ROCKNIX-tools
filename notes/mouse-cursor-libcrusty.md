# Getting a mouse cursor in a port on ROCKNIX

Plenty of ports want a pointer: visual novels with image maps, strategy games,
anything originally driven by a mouse. `gptokeyb` can move a pointer from the
analog stick, but on ROCKNIX that alone gives you an invisible cursor.

## The incomplete version

This is what people usually try, and it does not show a cursor:

```sh
# .gptk
mouse_scale = 8192
right_analog_up = mouse_movement_up
right_analog_down = mouse_movement_down
right_analog_left = mouse_movement_left
right_analog_right = mouse_movement_right
l3 = mouse_right
r3 = mouse_left
```

```sh
LD_PRELOAD=./libcrusty.so CRUSTY_SHOW_CURSOR=1 ./game
```

`libcrusty.so` comes from PortMaster's westonpack and draws a cursor sprite over
the game. Copying it into the port folder and setting the flag is necessary but
not sufficient.

## What the OpenMW port actually does

OpenMW runs on this device with a working cursor, and its launcher shows the
missing pieces:

```sh
export CRUSTY_SHOW_CURSOR=1
export CRUSTY_CURSOR_FILE=$GAMEDIR/cursor.bmp
export CRUSTY_CURSOR_OFFSET_X=0.0      # 0 = top left, 0.5 = middle, 1 = bottom right
export CRUSTY_CURSOR_OFFSET_Y=0.0
export CRUSTY_CURSOR_SIZE=0.75         # 1 is normal, any positive value

PRELOAD="$GAMEDIR/libcrusty.so"

if [ "$DEVICE_ARCH" = "x86_64" ]; then
    PRELOAD=""                          # not needed on a Steam Deck

elif [ "$CFW_NAME" = "ROCKNIX" ]; then
    SDL_VIDEODRIVER=x11                 # <- without this, no cursor

    if [ "$CFW_VERSION" -gt "20250517" ]; then
        rm -f "$GAMEDIR/libs.aarch64/libX11.so.6"
    fi

    if [[ "$UI_SERVICE" == *"sway"* ]]; then
        swaymsg 'seat * hide_cursor 1'  # <- stop the system cursor fighting it
    else
        PRELOAD=""                      # breaks things on the OGU
    fi
fi

LD_PRELOAD="$PRELOAD" ./$GAME_EXECUTABLE
```

The two lines that matter on ROCKNIX and get left out:

1. `SDL_VIDEODRIVER=x11`
2. `swaymsg 'seat * hide_cursor 1'` when the UI service is sway

Some CFWs also want a deliberately blank cursor bitmap instead, because they
draw their own:

```sh
elif [ "$CFW_NAME" = "AmberELEC" ]; then
    CRUSTY_CURSOR_FILE=$GAMEDIR/blank_cursor.bmp
fi
```

## Where to get libcrusty.so

It ships inside PortMaster ports that need it. The OpenMW port has it at
`ports/openmw/libcrusty.so`, about 55 KB, along with `cursor.bmp` and
`blank_cursor.bmp`.

## Caveat

This is read off a working port, not tested as a standalone recipe on every
device. `PRELOAD=""` appears in two branches precisely because the preload makes
things worse on some hardware, so expect to test rather than assume.
