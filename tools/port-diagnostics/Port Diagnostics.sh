#!/bin/bash
# Port Diagnostics - collect everything needed to debug a failing port into
# one text file, so it can be read off the card instead of hunted for on the
# handheld.
#
# Run from the Ports menu. Writes:
#     <roms>/ports/port-diagnostics.txt
#
# Edit PORTS below to cover whichever ports are misbehaving.

PORTS="chasm slaythespire"

# Files that must exist for a given port to launch at all. Format:
#   <portname>:<path relative to the port folder>
# Checked and reported individually, because "the folder has stuff in it" is
# not the same as "the one file the launcher execs is present".
KEYFILES="
chasm:gamedata/Chasm.exe
chasm:dlls/FNA.dll
chasm:dlls/ChasmPatches.dll
chasm:libs/libFNA3D.so.0
slaythespire:desktoppatched.jar
slaythespire:controller-injector.jar
slaythespire:texcompress-agent.jar
slaythespire:libtexcompress.so
slaythespire:slay.gptk
"

# Logs to tail, relative to the port folder, and how many lines of each.
LOGTAIL=160

notify() {
  command -v pm_message >/dev/null 2>&1 && pm_message "$*"
  echo "$*"
}

# --- find the ports root -------------------------------------------------
ROOTS=""
for r in /storage/roms/ports /storage/games-external/roms/ports; do
  [ -d "$r" ] && ROOTS="$ROOTS $r"
done

if [ -z "$ROOTS" ]; then
  notify "Could not find a ports folder in either roms location."
  sleep 10
  exit 1
fi

# Write the report next to the first ports folder we found.
OUTDIR="$(echo $ROOTS | awk '{print $1}')"
OUT="$OUTDIR/port-diagnostics.txt"

clear 2>/dev/null
echo "============================================"
echo "  PORT DIAGNOSTICS"
echo "============================================"
echo "  Writing: $OUT"
echo ""

{
echo "==================== PORT DIAGNOSTICS ===================="
echo "date      : $(date)"
echo "ports for : $PORTS"
echo "roots     : $ROOTS"
echo ""

echo "-------------------- system --------------------"
# control.txt is where PortMaster defines $directory, DISPLAY_WIDTH etc.
for c in /opt/system/Tools/PortMaster /opt/tools/PortMaster \
         "$HOME/.local/share/PortMaster" /storage/roms/ports/PortMaster; do
  if [ -d "$c" ]; then
    echo "controlfolder : $c"
    [ -f "$c/version" ] && echo "PM version    : $(cat "$c/version" 2>/dev/null)"
    break
  fi
done
echo "uname         : $(uname -a 2>/dev/null)"
echo "mem (MB)      :"
free -m 2>/dev/null | sed 's/^/    /'
echo "disk          :"
df -h /storage 2>/dev/null | sed 's/^/    /'
echo ""

echo "-------------------- runtimes present --------------------"
# The launchers mount these. A missing one is an immediate hard failure.
for c in /opt/system/Tools/PortMaster /opt/tools/PortMaster \
         "$HOME/.local/share/PortMaster" /storage/roms/ports/PortMaster; do
  if [ -d "$c/libs" ]; then
    ls -1 "$c/libs"/*.squashfs 2>/dev/null | while read -r f; do
      printf "  %10s  %s\n" "$(du -h "$f" 2>/dev/null | cut -f1)" "$(basename "$f")"
    done
    break
  fi
done
echo ""

for p in $PORTS; do
  echo "##########################################################"
  echo "## PORT: $p"
  echo "##########################################################"

  PDIR=""
  for r in $ROOTS; do
    [ -d "$r/$p" ] && PDIR="$r/$p" && break
  done

  if [ -z "$PDIR" ]; then
    echo "NOT INSTALLED: no '$p' folder under any ports root."
    echo ""
    continue
  fi

  echo "path : $PDIR"
  echo ""

  echo "---- key files ----"
  # Presence plus size. A 0-byte or missing file is the usual culprit.
  echo "$KEYFILES" | while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    case "$entry" in
      "$p":*) ;;
      *) continue ;;
    esac
    rel="${entry#*:}"
    f="$PDIR/$rel"
    if [ -f "$f" ]; then
      printf "  OK      %12s  %s\n" "$(stat -c %s "$f" 2>/dev/null)" "$rel"
    elif [ -d "$f" ]; then
      printf "  DIR?    %12s  %s\n" "-" "$rel"
    else
      printf "  MISSING %12s  %s\n" "-" "$rel"
    fi
  done
  echo ""

  echo "---- top level ----"
  ls -la "$PDIR" 2>/dev/null | sed 's/^/  /'
  echo ""

  # gamedata is where user-supplied assets go. Depth matters: a single
  # wrapper folder here is the most common reason a port "does nothing".
  if [ -d "$PDIR/gamedata" ]; then
    echo "---- gamedata (file count: $(find "$PDIR/gamedata" -type f 2>/dev/null | wc -l)) ----"
    ls -la "$PDIR/gamedata" 2>/dev/null | head -40 | sed 's/^/  /'
    echo ""
    echo "---- gamedata subdirs, 2 deep ----"
    find "$PDIR/gamedata" -maxdepth 2 -type d 2>/dev/null | head -30 | sed 's/^/  /'
    echo ""
    echo "---- any leftover GOG installer in gamedata? ----"
    # If one is still here, the port's own (7zzs-based) patcher will fire
    # again on every launch and fail again.
    # Captured first: piping straight into sed would mask ls's exit status,
    # so a "none" fallback on the pipeline would never fire and an empty
    # section could be misread as "not checked".
    leftovers="$(ls -la "$PDIR/gamedata"/*.sh "$PDIR/gamedata"/*.bin 2>/dev/null)"
    if [ -n "$leftovers" ]; then
      echo "$leftovers" | sed 's/^/  /'
    else
      echo "  none"
    fi
    echo ""
  else
    echo "---- no gamedata folder (normal for slaythespire) ----"
    echo ""
  fi

  # Leftover temp dir from a half-finished patch run.
  if [ -d "$PDIR/tmp" ]; then
    echo "---- leftover tmp/ from patching ----"
    find "$PDIR/tmp" -maxdepth 2 2>/dev/null | head -25 | sed 's/^/  /'
    echo ""
  fi

  for lg in log.txt patchlog.txt patchlog_error.txt; do
    if [ -f "$PDIR/$lg" ]; then
      echo "---- $lg  (last $LOGTAIL lines, size $(stat -c %s "$PDIR/$lg" 2>/dev/null)) ----"
      tail -n "$LOGTAIL" "$PDIR/$lg" 2>/dev/null | sed 's/^/  /'
      echo ""
    else
      echo "---- $lg : ABSENT ----"
      echo ""
    fi
  done
done

echo "==================== END ===================="
} > "$OUT" 2>&1

echo "  Done."
echo ""
echo "  Report lines: $(wc -l < "$OUT" 2>/dev/null)"
echo "  Report size : $(stat -c %s "$OUT" 2>/dev/null) bytes"
echo ""
echo "============================================"

notify "Diagnostics written to:

ports/port-diagnostics.txt

Pull that one file off the card and send it over. It has the key-file checks,
the folder layouts and the tail of log.txt / patchlog.txt for both ports."

sleep 12
exit 0
