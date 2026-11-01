#!/bin/bash
# RenPy Build Runtime - turn an extracted Ren'Py SDK into a runtime this hub can
# use, so newer Ren'Py games work before PortMaster ships a newer runtime.
#
# WHY THIS WORKS AND WHAT IT IS NOT
#   Nothing is compiled here. PortMaster's own renpy_8.1.3 and renpy_8.3.4
#   runtimes are official upstream Ren'Py builds, repackaged. Both carry
#   renpy/vc_version.py saying official = True, and both are laid out exactly
#   like an SDK with the desktop extras stripped out:
#
#       startRENPY            the SDK's renpy.sh, renamed
#       startRENPY.py         the SDK's renpy.py, renamed
#       game/                 empty, the game's assets get laid over it
#       renpy/                the engine, plain Python, no architecture
#       lib/py3-linux-aarch64/   the ARM64 binaries, from the SDK
#       lib/python3.XX/          the matching Python standard library
#
#   Ren'Py's own build system lists Platform("linux", "aarch64"), which is where
#   those ARM64 binaries come from. So this script just rearranges files.
#
# WHAT YOU DO FIRST
#   1. Download the ARM SDK for the version you need. It has to be the "sdkarm"
#      file, not the plain "sdk" one:
#
#          https://www.renpy.org/dl/8.5.2/renpy-8.5.2-sdkarm.tar.bz2
#
#      renpy.org lists it as "ARM Linux (Raspberry Pi and Chromebook)". The
#      ordinary renpy-8.5.2-sdk.tar.bz2 contains only x86_64 Linux, Mac and
#      Windows binaries, so it is useless on a handheld. Swap the version number
#      in that URL for whichever one you need.
#   2. Put the archive, as downloaded, in:
#          ports/renpy/sdk/
#      This script extracts it for you, so there is no need to unpack it on a PC.
#      An already-extracted folder works too.
#   3. Run this from the Ports menu, then run RenPy Scan.
#
#   If the SDK has no lib/py3-linux-aarch64 folder, it carries no ARM64 build and
#   this cannot work. The script says so and stops.

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

GAMEDIR="/$directory/ports/renpy"
SDKROOT="$GAMEDIR/sdk"
REPORT="$GAMEDIR/build-runtime.txt"

mkdir -p "$SDKROOT" "$GAMEDIR/runtimes"
: > "$REPORT"
exec > >(tee -a "$REPORT") 2>&1
echo "== RenPy Build Runtime $(date)"
echo ""

# ---------------------------------------------------------------- find the SDK
# An SDK folder is one holding renpy.sh and a lib directory. Checked at the top
# level and one level down, since people drop the whole extracted folder in.
find_sdk() {
  local d
  if [ -f "$SDKROOT/renpy.sh" ] && [ -d "$SDKROOT/lib" ]; then echo "$SDKROOT"; return 0; fi
  for d in "$SDKROOT"/*/; do
    [ -f "${d}renpy.sh" ] && [ -d "${d}lib" ] && { echo "${d%/}"; return 0; }
  done
  for d in "$SDKROOT"/*/*/; do
    [ -f "${d}renpy.sh" ] && [ -d "${d}lib" ] && { echo "${d%/}"; return 0; }
  done
  return 1
}

# ---------------------------------------------------------------- extraction
# PortMaster ships a 7-Zip binary, which is the one extractor that is certain to
# be on the device and handles bz2, gz, xz, tar and zip. ROCKNIX's own tar is
# tried first when it can do the job, since it is one pass instead of two.
find_7z() {
  local c
  for c in "$controlfolder/7zzs.$DEVICE_ARCH" "$controlfolder/7zzs" \
           "$controlfolder/utils/7zzs.$DEVICE_ARCH" "$(command -v 7zz)" "$(command -v 7z)"; do
    [ -n "$c" ] && [ -x "$c" ] && [ ! -d "$c" ] && { echo "$c"; return 0; }
  done
  return 1
}

# Each extractor is tried in turn, and success is judged by whether an SDK is
# actually on disk afterwards, NOT by the tool's exit code. That matters because
# tar reports failure for things that do not break the extraction at all: on an
# exFAT or FAT card it cannot set ownership or timestamps, so it prints a pile of
# "Cannot change ownership" lines and exits non-zero with every file unpacked
# correctly. An earlier version believed the exit code and gave up on a perfectly
# good extraction.
try_tar() {
  local arc="$1" dest="$2"
  command -v tar >/dev/null 2>&1 || return 1
  # --no-same-owner and --no-same-permissions stop tar from even attempting the
  # operations that fail on cards without unix permissions.
  tar -xf "$arc" -C "$dest" --no-same-owner --no-same-permissions 2>&1 | tail -5
  return 0
}

try_unzip() {
  local arc="$1" dest="$2"
  command -v unzip >/dev/null 2>&1 || return 1
  unzip -q -o "$arc" -d "$dest" 2>&1 | tail -5
  return 0
}

try_7z() {
  local arc="$1" dest="$2" sevenz tmp inner
  sevenz="$(find_7z)" || return 1
  echo "using 7-Zip   : $sevenz"
  case "$arc" in
    *.tar.bz2|*.tbz2|*.tar.gz|*.tgz|*.tar.xz)
      # Two passes: unwrap the compression, then unpack the tar inside it.
      tmp="$dest/.unpack"
      rm -rf "$tmp"; mkdir -p "$tmp"
      "$sevenz" x -y -o"$tmp" "$arc" >/dev/null 2>&1
      inner="$(ls "$tmp"/*.tar 2>/dev/null | head -1)"
      [ -z "$inner" ] && inner="$(ls "$tmp"/* 2>/dev/null | head -1)"
      if [ -n "$inner" ]; then
        "$sevenz" x -y -o"$dest" "$inner" >/dev/null 2>&1
      fi
      rm -rf "$tmp"
      ;;
    *)
      "$sevenz" x -y -o"$dest" "$arc" >/dev/null 2>&1
      ;;
  esac
  return 0
}

extract_archive() {
  local arc="$1" dest="$2" tool found
  mkdir -p "$dest"
  echo "extracting    : $(basename "$arc")"
  echo "size          : $(du -h "$arc" 2>/dev/null | cut -f1)"
  echo "this can take several minutes, bzip2 is slow on this chip"

  for tool in tar unzip 7z; do
    case "$arc:$tool" in
      *.zip:tar) continue ;;
      *.tar*:unzip|*.tbz2:unzip|*.tgz:unzip) continue ;;
    esac
    echo "trying        : $tool"
    "try_$tool" "$arc" "$dest" || { echo "  $tool not available"; continue; }
    found="$(find_sdk)"
    if [ -n "$found" ]; then
      echo "extracted with: $tool"
      return 0
    fi
    echo "  $tool left no usable SDK, trying the next tool"
  done
  return 1
}

SDK="$(find_sdk)"
if [ -z "$SDK" ]; then
  # Nothing extracted yet. Look for an archive to unpack.
  ARC=""
  for f in "$SDKROOT"/*.tar.bz2 "$SDKROOT"/*.tbz2 "$SDKROOT"/*.tar.gz "$SDKROOT"/*.tgz \
           "$SDKROOT"/*.tar.xz "$SDKROOT"/*.tar "$SDKROOT"/*.zip "$SDKROOT"/*.7z; do
    [ -f "$f" ] && { ARC="$f"; break; }
  done

  if [ -n "$ARC" ]; then
    if extract_archive "$ARC" "$SDKROOT/extracted"; then
      SDK="$(find_sdk)"
    else
      echo "extraction failed"
      echo "extracted/ now holds: $(ls -A "$SDKROOT/extracted" 2>/dev/null | tr '\n' ' ')"
      pm_message "Could not extract:

$(basename "$ARC")

No folder containing renpy.sh and lib/ turned up afterwards. If the card was
short on space, clear some and run this again: a part-extracted folder is
picked up on the next run.

Details in ports/renpy/build-runtime.txt"
      sleep 12
      exit 1
    fi
  fi
fi

if [ -z "$SDK" ]; then
  echo "No Ren'Py SDK found under $SDKROOT"
  echo "contents: $(ls -A "$SDKROOT" 2>/dev/null | tr '\n' ' ')"
  pm_message "No Ren'Py SDK found.

Put the SDK here, either as the downloaded archive or already extracted:

ports/renpy/sdk/

Get it from renpy.org, e.g. renpy-8.5.2-sdk.tar.bz2. The .tar.bz2 is better
than the .zip, which carries no execute bits."
  sleep 10
  exit 1
fi
echo "SDK folder    : $SDK"

# ---------------------------------------------------------------- version
VER=""
if [ -f "$SDK/renpy/vc_version.py" ]; then
  # version = '8.5.2.26010101'  ->  8.5.2
  VER="$(grep -m1 "^version *=" "$SDK/renpy/vc_version.py" \
         | sed "s/.*'\([^']*\)'.*/\1/" | cut -d. -f1-3)"
fi
if [ -z "$VER" ]; then
  # Fall back to the folder name, e.g. renpy-8.5.2-sdk
  VER="$(basename "$SDK" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
fi
if [ -z "$VER" ]; then
  pm_message "Could not work out the Ren'Py version of that SDK.

Expected renpy/vc_version.py inside it. Details in build-runtime.txt"
  sleep 10
  exit 1
fi
echo "version       : $VER"

OFFICIAL="$(grep -m1 "^official" "$SDK/renpy/vc_version.py" 2>/dev/null)"
[ -n "$OFFICIAL" ] && echo "build         : $OFFICIAL"

# ---------------------------------------------------------------- the ARM64 check
ARMDIR="$SDK/lib/py3-linux-aarch64"
echo "lib contents  : $(ls "$SDK/lib" 2>/dev/null | tr '\n' ' ')"

if [ ! -d "$ARMDIR" ]; then
  echo ""
  echo "FAILED: this SDK has no lib/py3-linux-aarch64 folder."
  echo "This is almost certainly the plain 'sdk' download instead of 'sdkarm'."
  pm_message "Wrong download: this is the x86 SDK.

You need the ARM one, which renpy.org lists as
\"ARM Linux (Raspberry Pi and Chromebook)\":

  renpy-$VER-sdkarm.tar.bz2
  www.renpy.org/dl/$VER/

The plain renpy-$VER-sdk.tar.bz2 has only x86_64, Mac and Windows binaries
inside, so there is nothing a handheld can run.

Delete ports/renpy/sdk/ , put the sdkarm file there, and run this again."
  sleep 15
  exit 1
fi

if [ ! -f "$ARMDIR/librenpython.so" ]; then
  echo "WARNING: librenpython.so is missing from $ARMDIR, this may not run"
fi

PYLIB="$(ls -d "$SDK"/lib/python3.* 2>/dev/null | sort -V | tail -1)"
if [ -z "$PYLIB" ]; then
  pm_message "This SDK has no lib/python3.XX folder, so the Python standard
library is missing. Details in build-runtime.txt"
  sleep 10
  exit 1
fi
echo "python lib    : $(basename "$PYLIB")"

# ---------------------------------------------------------------- assemble
OUT="$GAMEDIR/runtimes/renpy_$VER"
echo "building      : runtimes/renpy_$VER"

if [ -d "$OUT" ]; then
  echo "removing the previous build first"
  rm -rf "$OUT"
fi
mkdir -p "$OUT/lib" "$OUT/game" || {
  pm_message "Could not create $OUT"; sleep 8; exit 1; }

# cp -a keeps the execute bits where the filesystem supports them.
echo "copying renpy/ ..."
cp -a "$SDK/renpy" "$OUT/renpy" || { pm_message "Copy of renpy/ failed."; sleep 8; exit 1; }
echo "copying lib/py3-linux-aarch64/ ..."
cp -a "$ARMDIR" "$OUT/lib/py3-linux-aarch64" || { pm_message "Copy of the ARM64 libs failed."; sleep 8; exit 1; }
echo "copying lib/$(basename "$PYLIB")/ ..."
cp -a "$PYLIB" "$OUT/lib/$(basename "$PYLIB")" || { pm_message "Copy of the Python library failed."; sleep 8; exit 1; }

# renpy.sh works out the platform from uname and then runs the binary that
# matches its own filename, so both have to be called startRENPY. renpy.py is
# the script that binary loads, named after it too.
cp -a "$SDK/renpy.sh" "$OUT/startRENPY"
cp -a "$SDK/renpy.py" "$OUT/startRENPY.py"

# The launcher binary in the SDK is called renpy. A plain copy under the new
# name is what Ren'Py's own packaging does.
if [ -f "$OUT/lib/py3-linux-aarch64/renpy" ]; then
  cp -a "$OUT/lib/py3-linux-aarch64/renpy" "$OUT/lib/py3-linux-aarch64/startRENPY"
elif [ -f "$OUT/lib/py3-linux-aarch64/python" ]; then
  cp -a "$OUT/lib/py3-linux-aarch64/python" "$OUT/lib/py3-linux-aarch64/startRENPY"
else
  echo "FAILED: no renpy or python binary in lib/py3-linux-aarch64"
  pm_message "The ARM64 folder has no launcher binary in it.

Expected lib/py3-linux-aarch64/renpy (or python).
Details in build-runtime.txt"
  sleep 10
  exit 1
fi

# A zip-extracted SDK arrives without execute bits, which is the usual reason a
# hand-built runtime does nothing at all.
chmod +x "$OUT/startRENPY" 2>/dev/null
chmod +x "$OUT"/lib/py3-linux-aarch64/* 2>/dev/null

echo ""
echo "============================================"
echo "  built: runtimes/renpy_$VER"
echo "  size : $(du -sh "$OUT" 2>/dev/null | cut -f1)"
echo "  root : $(ls "$OUT" | tr '\n' ' ')"
echo "  exec : startRENPY $([ -x "$OUT/startRENPY" ] && echo ok || echo "NOT EXECUTABLE")"
echo "         lib/py3-linux-aarch64/startRENPY $([ -x "$OUT/lib/py3-linux-aarch64/startRENPY" ] && echo ok || echo "NOT EXECUTABLE")"
echo "============================================"

WARN=""
[ -x "$OUT/lib/py3-linux-aarch64/startRENPY" ] || WARN="
The binaries are not marked executable and chmod did not help, which happens on
some cards. The game will not start until that is fixed."

pm_message "Built Ren'Py runtime $VER.

runtimes/renpy_$VER
$(du -sh "$OUT" 2>/dev/null | cut -f1) on disk
$WARN

Now run RenPy Scan. Games built with Ren'Py $VER or older should be
assigned to it.

You can delete ports/renpy/sdk/ afterwards to save space.
Details in ports/renpy/build-runtime.txt"
sleep 8
exit 0
