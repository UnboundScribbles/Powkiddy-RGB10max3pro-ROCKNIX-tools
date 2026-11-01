#!/bin/bash
# run.sh - the shared Ren'Py launcher. Not meant to be run directly.
#
# RenPy Scan writes one small wrapper per game into the ports folder, and each
# wrapper calls this with three arguments:
#     $1  game name      the folder name under ports/renpy/games/
#     $2  runtime        e.g. renpy_8.3.4
#     $3  relative path  from games/<name> down to the Ren'Py "game" folder
#
# Modeled on PortMaster's own Ren'Py ports, which mount the runtime as a
# squashfs and then bind the game's assets over the runtime's game/ directory.
# Nothing is copied or converted.
#
# Saves live in ports/renpy/games/<name>/conf, so each game keeps its own and
# the whole game folder stays portable.

set -o pipefail

NAME="$1"
RUNTIME="$2"
REL="$3"

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
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"
get_controls

GAMEDIR="/$directory/ports/renpy"
# Set per attempt in run_one, since a local runtime lives somewhere else.
PORTEXEC="renpy/startRENPY"
# Mount point for a PortMaster squashfs runtime.
renpydir="$GAMEDIR/renpy"

# A run that dies sooner than this with a script error counts as "did not start",
# and the next runtime gets a turn.
EARLY_FAIL_SECS=90

cd "$GAMEDIR" || exit 1

mkdir -p "$GAMEDIR/logs"
LOG="$GAMEDIR/logs/${NAME}.txt"
: > "$LOG"
exec > >(tee -a "$LOG") 2>&1

echo "== $NAME  $(date)"
echo "runtime asked for : $RUNTIME"

if [ -z "$NAME" ]; then
  pm_message "run.sh was started without a game name.

Launch a game from its own 'RenPy - <name>' entry instead, or run
RenPy Scan to rebuild those entries."
  sleep 8
  exit 1
fi

gamefiles="$GAMEDIR/games/$NAME/$REL"
gamefiles="${gamefiles%/}"
if [ ! -d "$gamefiles" ] || [ -z "$(ls -A "$gamefiles" 2>/dev/null)" ]; then
  pm_message "The game folder for $NAME is missing:

games/$NAME/$REL

Run RenPy Scan again after fixing it."
  sleep 8
  exit 1
fi
echo "game folder       : games/$NAME/$REL"

# Try the chosen runtime first, then any other Ren'Py runtime available, in case
# the version read from script_version.txt was off. Local runtimes (unpacked
# folders under runtimes/) count the same as PortMaster's squashfs ones.
ALL="$(
  {
    echo renpy_8.1.3; echo renpy_8.3.4
    for f in "$controlfolder/libs"/renpy_*.squashfs; do
      [ -f "$f" ] && basename "$f" .squashfs
    done
    for d in "$GAMEDIR/runtimes"/renpy_*/; do
      [ -d "$d" ] && basename "${d%/}"
    done
  } | sort -u -V
)"
RUNTIMES="$RUNTIME"
for r in $ALL; do
  [ "$r" = "$RUNTIME" ] || RUNTIMES="$RUNTIMES $r"
done
echo "runtime order     : $RUNTIMES"

# Saves: keep them with the game rather than in a shared home directory.
mkdir -p "$GAMEDIR/games/$NAME/conf"
export XDG_DATA_HOME="$GAMEDIR/games/$NAME/conf"
bind_directories ~/.renpy/ "$GAMEDIR/games/$NAME/conf/"

$ESUDO mkdir -p "$renpydir"

unmount_all() {
  $ESUDO umount "$renpydir/game" 2>/dev/null || true
  for d in "$GAMEDIR/runtimes"/renpy_*/; do
    [ -d "$d" ] || continue
    $ESUDO umount "${d}game" 2>/dev/null
    # Only a symlink is removed here, never a real directory, so a runtime that
    # legitimately ships its own game folder is left alone.
    [ -L "${d}game" ] && $ESUDO rm -f "${d}game"
  done
  if [[ "$PM_CAN_MOUNT" != "N" ]]; then
    $ESUDO umount "$renpydir" 2>/dev/null || true
    for r in $ALL; do
      $ESUDO umount "$controlfolder/libs/${r}.squashfs" 2>/dev/null || true
    done
  fi
}

run_one() {
  local rt="$1" sq pylib start_bytes start_time rc secs rtroot rtrel
  sq="$controlfolder/libs/${rt}.squashfs"
  echo ""
  echo "---- trying runtime: $rt"

  unmount_all

  if [ -d "$GAMEDIR/runtimes/$rt" ]; then
    # A local runtime: an already-unpacked Ren'Py distribution, so there is
    # nothing to mount and no squashfs to download.
    rtroot="$GAMEDIR/runtimes/$rt"
    rtrel="runtimes/$rt"
    echo "runtime kind      : local folder"
  else
    if [ ! -f "$sq" ]; then
      if [ ! -f "$controlfolder/harbourmaster" ]; then
        pm_message "This needs the latest PortMaster. See https://portmaster.games/"
        return 99
      fi
      $ESUDO $controlfolder/harbourmaster --quiet --no-check runtime_check "${rt}.squashfs"
    fi
    if [ ! -f "$sq" ]; then
      echo "runtime $rt is not installed, skipping"
      return 98
    fi
    rtroot="$renpydir"
    rtrel="renpy"
    echo "runtime kind      : PortMaster squashfs"
    $ESUDO mount "$sq" "$renpydir"
    sleep 2
  fi

  # The game's assets are laid over the runtime's own empty game/ directory,
  # which is how PortMaster's Ren'Py ports do it. A bind mount is preferred; a
  # symlink is the fallback for devices that cannot mount.
  $ESUDO mkdir -p "$rtroot/game" 2>/dev/null
  if ! $ESUDO mount --bind "$gamefiles" "$rtroot/game" 2>/dev/null; then
    echo "bind mount failed, trying a symlink instead"
    $ESUDO rmdir "$rtroot/game" 2>/dev/null
    $ESUDO ln -sfn "$gamefiles" "$rtroot/game" 2>/dev/null
  fi
  if [ -z "$(ls -A "$rtroot/game" 2>/dev/null)" ]; then
    echo "ERROR: could not attach the game folder to $rt"
    return 96
  fi

  # Each runtime carries its own Python, 3.9 in 8.1.3 and 3.12 in 8.3.4, so the
  # path is read from what is actually there. Newest wins when several exist,
  # because the 8.3.4 runtime still carries a leftover 3.9 directory.
  pylib="$(ls -d "$rtroot"/lib/python3.* 2>/dev/null | sort -V | tail -1)"
  echo "runtime python    : ${pylib:-NOT FOUND}"

  # If the runtime is not really there, the launcher below would run nothing and
  # the log would say very little, so check for the file that has to exist.
  if [ ! -x "$rtroot/lib/py3-linux-aarch64/startRENPY" ]; then
    echo "ERROR: $rt is not usable, lib/py3-linux-aarch64/startRENPY is missing"
    return 97
  fi

  PORTEXEC="$rtrel/startRENPY"
  export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"
  export LD_LIBRARY_PATH="$GAMEDIR/libs:$LD_LIBRARY_PATH"
  export PYTHONHOME="$rtroot/"
  export PYTHONPATH="$pylib"

  if [ -f "${controlfolder}/libgl_${CFW_NAME}.txt" ]; then
    source "${controlfolder}/libgl_${CFW_NAME}.txt"
  else
    source "${controlfolder}/libgl_default.txt"
  fi

  pm_platform_helper "$rtroot/lib/py3-linux-aarch64/startRENPY"
  $GPTOKEYB "$PORTEXEC" -c "renpy.gptk" &

  start_bytes=$(stat -c %s "$LOG" 2>/dev/null || echo 0)
  start_time=$(date +%s)
  "./$PORTEXEC"
  rc=$?
  secs=$(( $(date +%s) - start_time ))
  echo "---- $rt exited rc=$rc after ${secs}s"

  pkill -f gptokeyb 2>/dev/null || true

  # Only a quick death with a script-loading complaint is worth retrying. A long
  # session that ended in a crash is a different problem, and retrying would just
  # relaunch the game behind the player's back.
  # These are Ren'Py's own wordings for "this content is too new for me". The
  # patterns are kept narrow on purpose: an earlier version matched the bare
  # word script_version, which also appears in ordinary file listings, so a
  # game that had started fine got relaunched on another runtime.
  if tail -c +$((start_bytes + 1)) "$LOG" 2>/dev/null \
       | grep -qE "Could not load from archive|bad magic number|unsupported pickle|newer version of Ren.Py"; then
    [ "$secs" -lt "$EARLY_FAIL_SECS" ] && return 1
  fi
  return 0
}

for rt in $RUNTIMES; do
  run_one "$rt"
  r=$?
  if [ "$r" -eq 0 ]; then
    echo "== finished with $rt"
    break
  fi
  if [ "$r" -eq 99 ]; then
    break
  fi
  echo "== $rt did not start $NAME, moving on"
  LAST_FAIL=1
done

if [ -n "$LAST_FAIL" ]; then
  pm_message "$NAME did not start on any installed Ren'Py runtime.

That usually means the game was built with a newer Ren'Py than PortMaster
has (newest is 8.3.4). Check games/$NAME/game/script_version.txt.

Log: ports/renpy/logs/${NAME}.txt"
  sleep 10
fi

unmount_all
pm_finish
