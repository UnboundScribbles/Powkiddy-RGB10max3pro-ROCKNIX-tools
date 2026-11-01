#!/bin/bash
# Extract GOG Installer - unpack GOG Linux .sh installers from the Ports menu.
#
# Put installers in:  /storage/roms/_SH/   (or games-external, both are checked)
# Run "Extract GOG Installer" from the Ports menu.
# Each installer extracts into its own folder beside it. Originals are kept.
#
# WHY A SPECIAL TOOL IS NEEDED
#   GOG's Linux installers are MojoSetup: a shell script with a ZIP appended
#   after it. The ZIP's index lives at the END of the file and its offsets are
#   measured from the start of the ZIP, not the start of the file. Windows
#   tools handle that badly. 7-Zip latches onto the script header and reports
#   "data after the end of the payload"; others cannot identify the file.
#   Python's zipfile scans backwards from EOF and corrects for the prefix.
#
# MULTI-PART INSTALLERS
#   GOG splits large installers into a .sh plus numbered .bin files. Keep the
#   parts together and they are joined automatically, with no combined copy
#   written to the card.

BARW=28

# Both roms locations. ROCKNIX can have an internal card and an external one,
# and PortMaster's $directory only ever names one of them.
WORKDIRS=""
for d in /storage/roms/_SH /storage/games-external/roms/_SH; do
  [ -d "$d" ] && WORKDIRS="$WORKDIRS
$d"
done

# Nothing yet: make the internal one and explain.
if [ -z "$WORKDIRS" ]; then
  mkdir -p /storage/roms/_SH
  echo "  Created /storage/roms/_SH"
  command -v pm_message >/dev/null 2>&1 && \
    pm_message "Created /storage/roms/_SH

Put your GOG .sh installers there (with any .bin parts) and run this again."
  sleep 10
  exit 0
fi

PRIMARY=$(echo "$WORKDIRS" | sed -n '2p')
LOG="$PRIMARY/extract-log.txt"
echo "=== Extract run $(date) ===" > "$LOG"

ok=0; failed=0; skipped=0
failed_names=""

say()  { echo "$*"; echo "$*" >> "$LOG"; }
line() { echo "============================================"; }

notify() {
  echo "$*" >> "$LOG"
  command -v pm_message >/dev/null 2>&1 && pm_message "$*"
}

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

clear 2>/dev/null
line
echo "  EXTRACT GOG INSTALLER"
line
IFS='
'
for d in $WORKDIRS; do
  [ -z "$d" ] && continue
  echo "  Folder : $d"
done
unset IFS
command -v python3 >/dev/null 2>&1 && HAVE_PY=1 || HAVE_PY=0
echo "  python : $([ $HAVE_PY -eq 1 ] && echo yes || echo no)"
line
echo ""

if [ $HAVE_PY -eq 0 ]; then
  echo "  python3 not found. Cannot extract."
  notify "python3 not found. Cannot extract."
  sleep 10
  exit 1
fi

# --- build the list ----------------------------------------------------
# Plain glob, one level, files only. No find, no exclusions: the folder is
# called _SH, so any "skip anything containing _SH" rule would skip
# everything in it. Already-extracted output is a directory, so [ -f ]
# filters it out on its own.
list=""
total=0
IFS='
'
for d in $WORKDIRS; do
  [ -z "$d" ] && continue
  unset IFS
  for f in "$d"/*.sh "$d"/*.SH; do
    [ -f "$f" ] || continue
    list="$list
$f"
    total=$((total+1))
  done
  IFS='
'
done
unset IFS

if [ "$total" -eq 0 ]; then
  echo "  No .sh installers found."
  echo ""
  echo "  Looked in:"
  IFS='
'
  for d in $WORKDIRS; do [ -n "$d" ] && echo "    $d"; done
  unset IFS
  echo ""
  echo "  Those folders contain:"
  IFS='
'
  for d in $WORKDIRS; do
    [ -z "$d" ] && continue
    unset IFS
    ls -1 "$d" 2>/dev/null | head -12 | sed 's/^/    /'
    IFS='
'
  done
  unset IFS
  echo ""
  notify "No .sh installers found.

Put the GOG .sh files directly in the _SH folder."
  line
  sleep 15
  exit 0
fi

echo "  Found $total installer(s)."
echo ""
notify "Extracting $total installer(s).

Several minutes each, screen stays blank. Do not power off."

# --- extract -----------------------------------------------------------
n=0
IFS='
'
for src in $list; do
  [ -z "$src" ] && continue
  unset IFS
  n=$((n+1))
  base=$(basename "$src")
  name="${base%.*}"
  dest="$(dirname "$src")/${name}_SH"

  bar "$((n-1))" "$total"
  echo "  [$n/$total] $base  ($(hsize "$src"))"

  if [ -d "$dest" ] && [ -n "$(ls -A "$dest" 2>/dev/null)" ]; then
    echo "      already extracted, skipping"
    say "SKIP $base"
    skipped=$((skipped+1))
    echo ""
    IFS='
'
    continue
  fi

  mkdir -p "$dest"

  python3 - "$src" "$dest" >> "$LOG" 2>&1 <<'PYEOF'
import sys, zipfile, os, io, glob, re

src, dest = sys.argv[1], sys.argv[2]


class Parts(io.RawIOBase):
    """Present several files as one continuous seekable stream.

    GOG splits large installers into a .sh plus numbered .bin files. Python's
    zipfile cannot read split archives, but GOG's split is a plain byte split,
    so the parts only need reading back to back. A virtual stream avoids
    writing a second multi-gigabyte copy to the card just to join them.
    """

    def __init__(self, paths):
        self.sizes = [os.path.getsize(p) for p in paths]
        self.total = sum(self.sizes)
        self.starts, run = [], 0
        for s in self.sizes:
            self.starts.append(run); run += s
        self.pos = 0
        self.fhs = [open(p, "rb") for p in paths]

    def readable(self): return True
    def seekable(self): return True
    def tell(self): return self.pos

    def seek(self, off, whence=0):
        if whence == 0:   self.pos = off
        elif whence == 1: self.pos += off
        elif whence == 2: self.pos = self.total + off
        self.pos = max(0, min(self.pos, self.total))
        return self.pos

    def readinto(self, b):
        want = len(b)
        if want == 0 or self.pos >= self.total:
            return 0
        got = 0
        while got < want and self.pos < self.total:
            i = max(j for j in range(len(self.starts)) if self.starts[j] <= self.pos)
            local = self.pos - self.starts[i]
            self.fhs[i].seek(local)
            chunk = self.fhs[i].read(min(want - got, self.sizes[i] - local))
            if not chunk:
                break
            b[got:got + len(chunk)] = chunk
            got += len(chunk); self.pos += len(chunk)
        return got

    def close(self):
        for f in self.fhs:
            try: f.close()
            except Exception: pass
        super().close()


stem = re.sub(r"\.sh$", "", src, flags=re.I)
bins = sorted(
    set(glob.glob(stem + "-*.bin") + glob.glob(stem + "*.bin")),
    key=lambda p: [int(t) if t.isdigit() else t for t in re.split(r"(\d+)", p)],
)

if bins:
    print(f"multi-part: {len(bins)} .bin part(s)")
    for b in bins:
        print(f"  {os.path.basename(b)}  {os.path.getsize(b)//(1024*1024)}MB")
    source = Parts([src] + bins)
    print(f"joined: {source.total//(1024*1024)}MB")
else:
    source = src

try:
    zf = zipfile.ZipFile(source)
except zipfile.BadZipFile as e:
    print(f"FAILED: not readable as a ZIP ({e})")
    if bins:
        print("Parts were joined but it still will not open.")
        print("A part is missing or truncated.")
    else:
        print("No .bin parts found next to this installer.")
        print("If GOG lists .bin files, put them beside it.")
    sys.exit(1)

names = [n for n in zf.namelist() if not n.endswith("/")]
print(f"{len(names)} files, {sum(zf.getinfo(n).file_size for n in names)//(1024*1024)}MB")

done = 0
for n in names:
    parts = [p for p in n.replace("\\", "/").split("/") if p not in ("", ".", "..")]
    if not parts:
        continue
    out = os.path.join(dest, *parts)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with zf.open(n) as fsrc, open(out, "wb") as fdst:
        while True:
            chunk = fsrc.read(1024 * 1024)
            if not chunk:
                break
            fdst.write(chunk)
    done += 1

print(f"extracted {done} files")
PYEOF

  rc=$?
  if [ "$rc" -eq 0 ]; then
    count=$(find "$dest" -type f 2>/dev/null | wc -l)
    echo "      OK  ->  ${name}_SH/   ($count files)"
    say "OK $base -> ${name}_SH ($count files)"
    ok=$((ok+1))
  else
    echo "      FAILED  (see extract-log.txt)"
    say "FAIL $base"
    failed_names="$failed_names $base"
    rmdir "$dest" 2>/dev/null
    failed=$((failed+1))
  fi
  echo ""
  IFS='
'
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
echo "  The game is at:  <name>_SH/data/noarch/game/"
echo "  Copy the CONTENTS of that folder into the port's gamedata."
echo ""
echo "  Full log : $LOG"
line
echo ""

if [ "$ok" -gt 0 ]; then
  notify "Done. Extracted $ok, skipped $skipped, failed $failed.

Game files are in:
<name>_SH/data/noarch/game/

Copy the CONTENTS of that folder into the port's gamedata, so the .exe sits directly in gamedata."
elif [ "$failed" -gt 0 ]; then
  notify "Extraction failed ($failed).

Likely a missing .bin part or an incomplete download.

See extract-log.txt in the _SH folder."
else
  notify "Nothing to do. All $skipped installer(s) already extracted.

Delete a _SH output folder to redo it."
fi

i=20
while [ $i -gt 0 ]; do
  printf "\r  Closing in %2d seconds...  " "$i"
  sleep 1
  i=$((i-1))
done
echo ""
