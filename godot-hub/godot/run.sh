#!/bin/bash
# run.sh - the shared Godot launcher. Not meant to be run directly.
#
# Godot Scan writes one small wrapper per game into the ports folder, and each
# wrapper calls this with four arguments:
#     $1  game name   the folder name under ports/godot/games/
#     $2  runtime     e.g. frt_3.5.2 or godot_4.3
#     $3  profile     frt (Godot 3) or godot4 (Godot 4)
#     $4  pack path   relative to games/<name>/
#
# The two profiles exist because PortMaster runs the two engine generations
# differently, and both follow the official port templates:
#
#   frt     mount the runtime, put it on PATH, run it with --main-pack. The
#           binary inside the squashfs has the same name as the runtime.
#   godot4  mount the weston runtime as well, then go through westonwrap in
#           headless kiosk mode and run the godot binary inside it.
#
# Per-game extras, all optional, in games/<name>/ :
#   runtime.txt   force a runtime (read by Godot Scan, not here)
#   game.gptk     controller map. Most Godot games read the gamepad natively
#                 through SDL and need none, so none is used unless this exists.
#   args.txt      extra command line arguments, one line, appended last

set -o pipefail

NAME="$1"
RUNTIME="$2"
PROFILE="$3"
PCKREL="$4"

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi

source $controlfolder/control.txt
[ -f "$controlfolder/device_info.txt" ] && source "$controlfolder/device_info.txt"
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"
get_controls

HUBDIR="/$directory/ports/godot"
GDIR="$HUBDIR/games/$NAME"
CONFDIR="$GDIR/conf"

mkdir -p "$HUBDIR/logs" "$CONFDIR"
LOG="$HUBDIR/logs/${NAME}.txt"
: > "$LOG"
exec > >(tee -a "$LOG") 2>&1

echo "== $NAME  $(date)"
echo "runtime : $RUNTIME"
echo "profile : $PROFILE"
echo "pack    : $PCKREL"

if [ -z "$NAME" ] || [ -z "$RUNTIME" ] || [ -z "$PCKREL" ]; then
  pm_message "run.sh was started without enough arguments.

Launch a game from its own 'Godot - <name>' entry, or run Godot Scan to
rebuild those entries."
  sleep 8
  exit 1
fi

PCK="$GDIR/$PCKREL"
if [ ! -f "$PCK" ]; then
  pm_message "The pack for $NAME is missing:

games/$NAME/$PCKREL

Run Godot Scan again after fixing it."
  sleep 8
  exit 1
fi

# --- the runtime --------------------------------------------------------
SQUASH="$controlfolder/libs/${RUNTIME}.squashfs"
if [ ! -f "$SQUASH" ]; then
  if [ ! -f "$controlfolder/harbourmaster" ]; then
    pm_message "This needs the latest PortMaster. See https://portmaster.games/"
    sleep 5
    exit 1
  fi
  echo "fetching runtime $RUNTIME ..."
  $ESUDO $controlfolder/harbourmaster --quiet --no-check runtime_check "${RUNTIME}.squashfs"
fi
if [ ! -f "$SQUASH" ]; then
  pm_message "The runtime $RUNTIME could not be installed.

PortMaster may not have it for this device, or there is no connection.
Put another runtime name in games/$NAME/runtime.txt to try a different one.

Log: ports/godot/logs/${NAME}.txt"
  sleep 12
  exit 1
fi

# --- optional per-game pieces -------------------------------------------
GPTK=""
[ -f "$GDIR/game.gptk" ] && GPTK="$GDIR/game.gptk"
EXTRA=""
[ -f "$GDIR/args.txt" ] && EXTRA="$(head -1 "$GDIR/args.txt" | tr -d '\r')"
[ -n "$EXTRA" ] && echo "extra args : $EXTRA"

GKPID=""
cleanup() {
  [ -n "$GKPID" ] && kill $GKPID 2>/dev/null
  killall gptokeyb 2>/dev/null
  killall gptokeyb2 2>/dev/null
  if [ -n "$WESTON_DIR" ] && [ -x "$WESTON_DIR/westonwrap.sh" ]; then
    $ESUDO "$WESTON_DIR/westonwrap.sh" cleanup 2>/dev/null
  fi
  if [[ "$PM_CAN_MOUNT" != "N" ]]; then
    [ -n "$GODOT_DIR" ] && $ESUDO umount "$GODOT_DIR" 2>/dev/null
    [ -n "$WESTON_DIR" ] && $ESUDO umount "$WESTON_DIR" 2>/dev/null
  fi
  command -v set_kill >/dev/null 2>&1 && set_kill stop
}
trap cleanup EXIT INT TERM HUP

cd "$GDIR" || exit 1
export XDG_DATA_HOME="$CONFDIR"
export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"

# ------------------------------------------------------------------ FRT
if [ "$PROFILE" = "frt" ]; then
  GODOT_DIR="$HOME/godot"
  $ESUDO mkdir -p "$GODOT_DIR"
  $ESUDO umount "$GODOT_DIR" 2>/dev/null
  $ESUDO mount "$SQUASH" "$GODOT_DIR" || {
    pm_message "Could not mount $RUNTIME"; sleep 8; exit 1; }
  PATH="$GODOT_DIR:$PATH"

  # The binary inside an FRT runtime carries the runtime's own name.
  EXE="$RUNTIME"
  if [ ! -x "$GODOT_DIR/$EXE" ]; then
    EXE="$(ls "$GODOT_DIR" 2>/dev/null | grep -E '^frt' | head -1)"
  fi
  if [ -z "$EXE" ] || [ ! -x "$GODOT_DIR/$EXE" ]; then
    echo "contents of the runtime: $(ls "$GODOT_DIR" 2>/dev/null | tr '\n' ' ')"
    pm_message "No FRT binary inside $RUNTIME.

Log: ports/godot/logs/${NAME}.txt"
    sleep 10
    exit 1
  fi
  echo "binary  : $EXE"

  # Stops FRT quitting on Select, which otherwise fights the gamepad.
  export FRT_NO_EXIT_SHORTCUTS=FRT_NO_EXIT_SHORTCUTS
  $ESUDO chmod 666 /dev/uinput 2>/dev/null

  if [ -n "$GPTK" ]; then
    $GPTOKEYB "$EXE" -c "$GPTK" &
    GKPID=$!
  fi
  command -v set_kill >/dev/null 2>&1 && set_kill set "$EXE"

  echo "---- starting"
  "$GODOT_DIR/$EXE" $GODOT_OPTS --main-pack "$PCK" -sw $EXTRA
  echo "---- exited rc=$?"

# --------------------------------------------------------------- Godot 4
else
  WESTON_RUNTIME="weston_pkg_0.2"
  WESTON_SQUASH="$controlfolder/libs/${WESTON_RUNTIME}.squashfs"
  if [ ! -f "$WESTON_SQUASH" ]; then
    echo "fetching $WESTON_RUNTIME ..."
    $ESUDO $controlfolder/harbourmaster --quiet --no-check runtime_check "${WESTON_RUNTIME}.squashfs"
  fi
  if [ ! -f "$WESTON_SQUASH" ]; then
    pm_message "Godot 4 games need the weston runtime, which could not be installed.

Log: ports/godot/logs/${NAME}.txt"
    sleep 10
    exit 1
  fi

  WESTON_DIR=/tmp/weston
  GODOT_DIR=/tmp/godot
  $ESUDO mkdir -p "$WESTON_DIR" "$GODOT_DIR"
  if [[ "$PM_CAN_MOUNT" != "N" ]]; then
    $ESUDO umount "$WESTON_DIR" 2>/dev/null
    $ESUDO umount "$GODOT_DIR" 2>/dev/null
  fi
  $ESUDO mount "$WESTON_SQUASH" "$WESTON_DIR" || {
    pm_message "Could not mount $WESTON_RUNTIME"; sleep 8; exit 1; }
  $ESUDO mount "$SQUASH" "$GODOT_DIR" || {
    pm_message "Could not mount $RUNTIME"; sleep 8; exit 1; }

  # Named godot43.aarch64 for 4.3, godot422.aarch64 for 4.2.2, and so on.
  # Globbing the mount is safer than rebuilding that name from the version.
  EXE="$(ls "$GODOT_DIR" 2>/dev/null | grep -E "^godot.*\.${DEVICE_ARCH}$" | head -1)"
  [ -z "$EXE" ] && EXE="$(ls "$GODOT_DIR" 2>/dev/null | grep -E '^godot' | head -1)"
  if [ -z "$EXE" ] || [ ! -x "$GODOT_DIR/$EXE" ]; then
    echo "contents of the runtime: $(ls "$GODOT_DIR" 2>/dev/null | tr '\n' ' ')"
    pm_message "No Godot binary inside $RUNTIME for this architecture.

Log: ports/godot/logs/${NAME}.txt"
    sleep 10
    exit 1
  fi
  echo "binary  : $EXE"

  # libcrusty blocks stray pointer input under westonpack. It ships inside
  # ports that need it rather than with the runtime, so it is used when one of
  # them has it and skipped otherwise.
  PRELOAD=""
  for c in "$GDIR/libcrusty.so" "$HUBDIR/libcrusty.so" "$WESTON_DIR/libcrusty.so" \
           /"$directory"/ports/*/libcrusty.so; do
    [ -f "$c" ] && { PRELOAD="$c"; break; }
  done
  echo "libcrusty : ${PRELOAD:-not found, continuing without it}"

  if [ -n "$GPTK" ]; then
    $GPTOKEYB "$EXE" -c "$GPTK" &
    GKPID=$!
  fi
  command -v set_kill >/dev/null 2>&1 && set_kill set "$EXE"

  RES="${DISPLAY_WIDTH:-640}x${DISPLAY_HEIGHT:-480}"
  echo "resolution : $RES"
  echo "---- starting"
  if [ -n "$PRELOAD" ]; then
    $ESUDO env WRAPPED_PRELOAD_PANFROST="$PRELOAD" CRUSTY_BLOCK_INPUT=1 \
      "$WESTON_DIR/westonwrap.sh" headless noop kiosk crusty_x11egl \
      XDG_DATA_HOME="$CONFDIR" "$GODOT_DIR/$EXE" \
      --resolution "$RES" -f --disable-cursor \
      --rendering-driver opengl3_es --audio-driver ALSA --main-pack "$PCK" $EXTRA
  else
    $ESUDO env "$WESTON_DIR/westonwrap.sh" headless noop kiosk crusty_x11egl \
      XDG_DATA_HOME="$CONFDIR" "$GODOT_DIR/$EXE" \
      --resolution "$RES" -f --disable-cursor \
      --rendering-driver opengl3_es --audio-driver ALSA --main-pack "$PCK" $EXTRA
  fi
  echo "---- exited rc=$?"
fi

pm_finish
