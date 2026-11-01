#!/bin/bash
# Unzip Files v2 - extract archives from the Ports menu, no SSH needed.
#
# Put archives in:  /storage/roms/_unzip/
# Run "Unzip Files" from the Ports menu.
# Each archive extracts into its own folder beside it. Originals are kept.

WORKDIR="/storage/roms/_unzip"
LOG="$WORKDIR/unzip-log.txt"
BARW=28

mkdir -p "$WORKDIR"
echo "=== Unzip run $(date) ===" > "$LOG"

ok=0; failed=0; skipped=0
failed_names=""

say()  { echo "$*"; echo "$*" >> "$LOG"; }
line() { echo "============================================"; }

# human-readable size
hsize() {
  s=$(stat -c %s "$1" 2>/dev/null || echo 0)
  if   [ "$s" -ge 1073741824 ]; then echo "$((s/1073741824)) GB"
  elif [ "$s" -ge 1048576 ];    then echo "$((s/1048576)) MB"
  elif [ "$s" -ge 1024 ];       then echo "$((s/1024)) KB"
  else echo "$s B"; fi
}

bar() {
  d=$1; t=$2
  [ "$t" -eq 0 ] && t=1
  f=$(( d * BARW / t ))
  printf "  ["
  i=0
  while [ $i -lt $BARW ]; do
    if [ $i -lt $f ]; then printf "#"; else printf "."; fi
    i=$((i+1))
  done
  printf "] %d/%d\n" "$d" "$t"
}

# --- find an extractor -------------------------------------------------
SEVENZ=""
for c in \
  /storage/roms/ports/PortMaster/7zzs \
  /storage/roms/ports/PortMaster/7za \
  /storage/roms/ports/PortMaster/7z \
  "$(command -v 7zzs 2>/dev/null)" \
  "$(command -v 7za 2>/dev/null)" \
  "$(command -v 7z  2>/dev/null)"
do
  if [ -n "$c" ] && [ -x "$c" ]; then SEVENZ="$c"; break; fi
done
command -v unzip   >/dev/null 2>&1 && HAVE_UNZIP=1 || HAVE_UNZIP=0
command -v python3 >/dev/null 2>&1 && HAVE_PY=1    || HAVE_PY=0

clear 2>/dev/null
line
echo "  UNZIP FILES"
line
echo "  Folder : $WORKDIR"
echo "  7-Zip  : ${SEVENZ:-none}"
echo "  unzip  : $([ $HAVE_UNZIP -eq 1 ] && echo yes || echo no)"
echo "  python : $([ $HAVE_PY -eq 1 ] && echo yes || echo no)"
line
echo ""

# --- build the list ----------------------------------------------------
list=""
total=0
for f in "$WORKDIR"/*; do
  [ -f "$f" ] || continue
  case "$f" in
    *.zip|*.7z|*.rar|*.tar|*.tar.gz|*.tgz|*.tar.xz|*.txz|*.tar.bz2|*.tbz)
      list="$list
$f"
      total=$((total+1))
      ;;
  esac
done

if [ "$total" -eq 0 ]; then
  echo "  No archives found."
  echo ""
  echo "  Copy .zip / .7z / .rar / .tar files into:"
  echo "  $WORKDIR"
  echo ""
  line
  echo "  Closing in 15 seconds..."
  sleep 15
  exit 0
fi

echo "  Found $total archive(s)."
echo ""

# --- extract -----------------------------------------------------------
run_with_spinner() {
  "$@" >> "$LOG" 2>&1 &
  pid=$!
  start=$(date +%s)
  while kill -0 "$pid" 2>/dev/null; do
    el=$(( $(date +%s) - start ))
    printf "\r      working... %ds  " "$el"
    sleep 1
  done
  wait "$pid"
  rc=$?
  el=$(( $(date +%s) - start ))
  printf "\r                           \r"
  return $rc
}

n=0
IFS='
'
for src in $list; do
  [ -z "$src" ] && continue
  n=$((n+1))
  base=$(basename "$src")
  name="${base%.*}"
  case "$name" in *.tar) name="${name%.tar}" ;; esac
  dest="$WORKDIR/$name"

  bar "$((n-1))" "$total"
  echo "  [$n/$total] $base  ($(hsize "$src"))"

  if [ -e "$dest" ]; then
    echo "      already extracted, skipping"
    say "SKIP $base (destination exists)"
    skipped=$((skipped+1))
    echo ""
    continue
  fi

  mkdir -p "$dest"
  rc=1
  case "$base" in
    *.tar)            run_with_spinner tar -xf  "$src" -C "$dest"; rc=$? ;;
    *.tar.gz|*.tgz)   run_with_spinner tar -xzf "$src" -C "$dest"; rc=$? ;;
    *.tar.xz|*.txz)   run_with_spinner tar -xJf "$src" -C "$dest"; rc=$? ;;
    *.tar.bz2|*.tbz)  run_with_spinner tar -xjf "$src" -C "$dest"; rc=$? ;;
    *)
      if [ -n "$SEVENZ" ]; then
        run_with_spinner "$SEVENZ" x -y -o"$dest" "$src"; rc=$?
      fi
      if [ "$rc" -ne 0 ] && [ $HAVE_UNZIP -eq 1 ]; then
        case "$base" in *.zip)
          run_with_spinner unzip -o "$src" -d "$dest"; rc=$? ;;
        esac
      fi
      if [ "$rc" -ne 0 ] && [ $HAVE_PY -eq 1 ]; then
        case "$base" in *.zip)
          run_with_spinner python3 -m zipfile -e "$src" "$dest"; rc=$? ;;
        esac
      fi
      ;;
  esac

  if [ "$rc" -eq 0 ]; then
    count=$(find "$dest" -type f 2>/dev/null | wc -l)
    echo "      OK  ->  $name/   ($count files)"
    say "OK $base -> $name ($count files)"
    ok=$((ok+1))
  else
    echo "      FAILED  (see unzip-log.txt)"
    say "FAIL $base"
    failed_names="$failed_names $base"
    rmdir "$dest" 2>/dev/null
    failed=$((failed+1))
  fi
  echo ""
done
unset IFS

# --- summary -----------------------------------------------------------
bar "$total" "$total"
echo ""
line
echo "  FINISHED"
line
echo "  Extracted : $ok"
echo "  Skipped   : $skipped"
echo "  Failed    : $failed"
if [ "$failed" -gt 0 ]; then
  echo ""
  echo "  Failed files:"
  for bn in $failed_names; do echo "    - $bn"; done
fi
echo ""
echo "  Output in : $WORKDIR"
echo "  Full log  : unzip-log.txt"
line
echo ""

i=20
while [ $i -gt 0 ]; do
  printf "\r  Closing in %2d seconds...  " "$i"
  sleep 1
  i=$((i-1))
done
echo ""
