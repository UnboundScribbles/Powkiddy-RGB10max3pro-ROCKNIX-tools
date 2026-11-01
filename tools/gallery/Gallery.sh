#!/bin/bash
# Gallery v2 - scan the SD card, then browse it with the gamepad.
#
# One port does both jobs: it indexes your images, converted ugoira
# animations, video and audio, then opens the result in Firefox with no
# browser UI and the controller mapped to it.
#
# Put in: /storage/roms/ports/   then run "Gallery" from the Ports menu.
#
# CONTROLS
#   D-pad        move
#   A            open / confirm
#   B            back / close
#   X            fullscreen
#   Y            rotate
#   START        pause / play
#   SELECT       on-screen keyboard
#   L1 / R1      step one frame (animations)
#   L2 / R2      slower / faster
#   Left stick   mouse pointer, L3 clicks
#   L1+SELECT+START   quit

# Folders to index. Add more, space separated.
FOLDERS="/storage/roms/_downloads /storage/roms/_ugoira /storage/roms/mplayer"

ROOT="/storage/roms"
OUT="$ROOT/_media.html"
GPTK="$ROOT/ports/gallery.gptk"
PROFILE="/storage/.mozilla/firefox-gallery"
LOG="$ROOT/ports/gallery.log"
MAXFILES=4000

TMP="/tmp/.gallery.$$"
GKPID=""

cleanup() {
  rm -f "$TMP".*
  [ -n "$GKPID" ] && kill $GKPID 2>/dev/null
  killall gptokeyb  2>/dev/null
  killall gptokeyb2 2>/dev/null
  killall firefox     2>/dev/null
  killall firefox-bin 2>/dev/null
  command -v set_kill >/dev/null 2>&1 && set_kill stop
  true
}
trap cleanup EXIT INT TERM HUP

echo "=== gallery $(date) ===" >> "$LOG"

line()  { echo "============================================"; }
pause() { i=$1; while [ $i -gt 0 ]; do printf "\r  Closing in %2d seconds...  " "$i"; sleep 1; i=$((i-1)); done; echo ""; }

clear 2>/dev/null
line
echo "  GALLERY"
line
echo ""

# Same parser as Ugoira Convert. Splitting on { puts each frame object on
# its own line, which is far less fragile than matching across the file.
read_frames() {
  tr '{' '\n' < "$1" \
    | grep '"file"' \
    | sed -n \
      -e 's/.*"file"[[:space:]]*:[[:space:]]*"\([^"]*\)"[^}]*"delay"[[:space:]]*:[[:space:]]*\([0-9]\{1,\}\).*/\1 \2/p' \
      -e 's/.*"delay"[[:space:]]*:[[:space:]]*\([0-9]\{1,\}\)[^}]*"file"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\2 \1/p'
}

esc() { sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }
esc1() { printf '%s' "$1" | esc; }

: > "$TMP.ugo"
: > "$TMP.img"
: > "$TMP.vid"
: > "$TMP.aud"
: > "$TMP.excl"

for d in $FOLDERS; do
  [ -d "$d" ] || { echo "  skip (missing) : $d"; continue; }

  find "$d" -name animation.json -type f 2>/dev/null \
    | sed 's|/animation\.json$||' >> "$TMP.ugo"

  find "$d" -type f \( \
      -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png'  -o -iname '*.gif' -o \
      -iname '*.webp' -o -iname '*.avif' -o -iname '*.bmp' -o -iname '*.jfif' \
    \) 2>/dev/null >> "$TMP.img"

  # Only formats Firefox can actually decode. .mkv and .avi are left out on
  # purpose: the browser will not play them and a dead tile is worse than
  # no tile.
  find "$d" -type f \( \
      -iname '*.mp4' -o -iname '*.webm' -o -iname '*.m4v' -o -iname '*.ogv' \
    \) 2>/dev/null >> "$TMP.vid"

  find "$d" -type f \( \
      -iname '*.mp3' -o -iname '*.ogg' -o -iname '*.oga' -o -iname '*.flac' -o \
      -iname '*.wav' -o -iname '*.m4a' -o -iname '*.opus' \
    \) 2>/dev/null >> "$TMP.aud"

  echo "  scanned        : $d"
done
echo ""

# Ugoira frame folders would otherwise flood the grid with numbered stills.
cp "$TMP.ugo" "$TMP.excl"
filter() {
  if [ -s "$TMP.excl" ]; then
    grep -v -F -f "$TMP.excl" "$1" 2>/dev/null
  else
    cat "$1"
  fi
}
filter "$TMP.img" > "$TMP.img2"; mv "$TMP.img2" "$TMP.img"
filter "$TMP.vid" > "$TMP.vid2"; mv "$TMP.vid2" "$TMP.vid"
filter "$TMP.aud" > "$TMP.aud2"; mv "$TMP.aud2" "$TMP.aud"

# grep -c prints 0 AND exits non-zero on an empty file, so a "|| echo 0"
# fallback here would append a second zero and break the arithmetic below.
count() { n=$(grep -c . "$1" 2>/dev/null); echo "${n:-0}"; }
nu=$(count "$TMP.ugo")
ni=$(count "$TMP.img")
nv=$(count "$TMP.vid")
na=$(count "$TMP.aud")
tot=$((nu + ni + nv + na))

echo "  Animations : $nu"
echo "  Images     : $ni"
echo "  Video      : $nv"
echo "  Audio      : $na"
echo ""

if [ "$tot" -eq 0 ]; then
  echo "  Nothing found."
  echo ""
  echo "  Looked in:"
  for d in $FOLDERS; do echo "    $d"; done
  echo ""
  echo "  Edit FOLDERS at the top to add more."
  line
  pause 20
  exit 0
fi

echo "  Building page..."

# --- items --------------------------------------------------------------
: > "$TMP.items"

# Animations first: they are the thing you came for.
while IFS= read -r dir; do
  [ -n "$dir" ] || continue
  j="$dir/animation.json"
  [ -f "$j" ] || continue
  nm=$(basename "$dir")
  fr=$(read_frames "$j" | while IFS=' ' read -r f dly; do
         if [ -z "$f" ] || [ -z "$dly" ]; then continue; fi
         printf '{f:"%s/%s",d:%s},' "$(esc1 "$dir")" "$(esc1 "$f")" "$dly"
       done)
  [ -n "$fr" ] || continue
  first=$(read_frames "$j" | head -1 | awk '{print $1}')
  printf '{t:"ugo",n:"%s",p:"%s",th:"%s/%s",fr:[%s]},\n' \
    "$(esc1 "$nm")" "$(esc1 "$dir")" "$(esc1 "$dir")" "$(esc1 "$first")" "$fr" >> "$TMP.items"
done < "$TMP.ugo"

emit() {
  kind=$1; src=$2
  [ -s "$src" ] || return 0
  # One sed pass for the whole list rather than a process per file, which
  # matters when there are thousands and the CPU is a handheld's.
  sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' "$src" \
    | sed -e "s|^\(.*\)$|{t:\"$kind\",p:\"\1\"},|" >> "$TMP.items"
}
emit img "$TMP.img"
emit vid "$TMP.vid"
emit aud "$TMP.aud"

head -n "$MAXFILES" "$TMP.items" > "$TMP.final"
shown=$(count "$TMP.final")

# --- page ---------------------------------------------------------------
{
cat <<'HEAD'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,user-scalable=no">
<title>Media</title>
<style>
  :root { color-scheme: dark; }
  * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
  html, body { height: 100%; }
  body { margin: 0; background: #0d0d10; color: #e8e8ea;
         font: 13px/1.4 system-ui, sans-serif; }

  header { position: sticky; top: 0; z-index: 5;
    display: flex; gap: 8px; align-items: center; flex-wrap: wrap;
    padding: 7px 10px; background: #16161b; border-bottom: 1px solid #26262e; }
  header b { font-size: 14px; }
  header .n { color: #8a8a94; font-size: 12px; }
  .tab { padding: 5px 10px; font-size: 12px; font-weight: 600;
         color: #b4b4be; background: #23232b; border: 0;
         border-radius: 999px; cursor: pointer; }
  .tab.on { color: #0d0d10; background: #e8e8ea; }
  header input { margin-left: auto; width: 32%; min-width: 110px;
    padding: 6px 9px; font-size: 13px; color: #e8e8ea; background: #0d0d10;
    border: 1px solid #33333d; border-radius: 6px; }

  #grid { display: grid; gap: 4px; padding: 4px;
          grid-template-columns: repeat(auto-fill, minmax(108px, 1fr)); }
  .cell { position: relative; aspect-ratio: 1; background: #1a1a20;
          border-radius: 4px; overflow: hidden; cursor: pointer; }
  .cell img { width: 100%; height: 100%; object-fit: cover; display: block; }
  .ph { width: 100%; height: 100%; display: flex; align-items: center;
        justify-content: center; font-size: 30px; color: #4a4a56; }
  .cell .tag { position: absolute; left: 0; right: 0; bottom: 0;
    padding: 3px 5px; font-size: 10px; line-height: 1.25; color: #fff;
    background: linear-gradient(transparent, rgba(0,0,0,.85));
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .cell .kind { position: absolute; top: 4px; left: 4px;
    padding: 1px 5px; font-size: 9px; font-weight: 700; letter-spacing: .4px;
    color: #0d0d10; background: #e8e8ea; border-radius: 3px; }
  .cell.hidden { display: none; }
  .cell.sel { outline: 3px solid #e8e8ea; outline-offset: -3px; }
  .cell.sel .tag { background: #e8e8ea; color: #0d0d10; }

  #view { position: fixed; inset: 0; z-index: 10; display: none;
          background: #000; flex-direction: column; }
  #view.on { display: flex; }
  #stage { flex: 1 1 auto; position: relative; overflow: hidden; }
  #big, #vid { position: absolute; top: 50%; left: 50%;
               transform-origin: center center; will-change: transform; }
  #vid { max-width: 100%; max-height: 100%; transform: translate(-50%,-50%); }
  #aud { position: absolute; top: 50%; left: 50%;
         transform: translate(-50%,-50%); width: min(90%, 420px); }
  #big { display: none; } #vid { display: none; } #aud { display: none; }

  #bar { flex: 0 0 auto; display: flex; gap: 6px; align-items: center;
    justify-content: center; flex-wrap: wrap; padding: 8px;
    background: #16161b; border-top: 1px solid #26262e; }
  button.b { padding: 9px 13px; font-size: 13px; font-weight: 600;
    color: #e8e8ea; background: #2a2a33; border: 0; border-radius: 6px;
    cursor: pointer; }
  button.b.pri { color: #0d0d10; background: #e8e8ea; }
  #cap { color: #8a8a94; font-size: 12px; max-width: 100%;
         overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  #view.fs #bar { position: fixed; left: 0; right: 0; bottom: 0;
    background: rgba(12,12,16,.82); opacity: 0; pointer-events: none;
    transition: opacity .25s; }
  #view.fs.show #bar { opacity: 1; pointer-events: auto; }
  #empty { padding: 30px; text-align: center; color: #8a8a94; display: none; }
</style>
</head>
<body>

<header>
  <b>Media</b> <span class="n" id="count"></span>
  <button class="tab on" data-f="all">All</button>
  <button class="tab" data-f="ugo">Anim</button>
  <button class="tab" data-f="img">Images</button>
  <button class="tab" data-f="vid">Video</button>
  <button class="tab" data-f="aud">Audio</button>
  <input id="q" type="search" placeholder="filter" autocomplete="off">
</header>

<div id="grid"></div>
<div id="empty">Nothing matches.</div>

<div id="view">
  <div id="stage">
    <img id="big" alt="">
    <video id="vid" controls playsinline preload="metadata"></video>
    <audio id="aud" controls preload="metadata"></audio>
  </div>
  <div id="bar">
    <button class="b" id="prev">&#8592;</button>
    <button class="b pri" id="play">Pause</button>
    <button class="b" id="next">&#8594;</button>
    <button class="b" id="rot">Rotate</button>
    <button class="b" id="loop">Loop: on</button>
    <button class="b" id="fs">Fullscreen</button>
    <button class="b" id="close">Close</button>
    <div id="cap"></div>
  </div>
</div>

<script>
HEAD

printf 'const ITEMS = [\n'
cat "$TMP.final"
printf '];\n'

cat <<'TAIL'
const grid  = document.getElementById("grid");
const view  = document.getElementById("view");
const stage = document.getElementById("stage");
const big   = document.getElementById("big");
const vid   = document.getElementById("vid");
const aud   = document.getElementById("aud");
const cap   = document.getElementById("cap");
const playB = document.getElementById("play");
const empty = document.getElementById("empty");

const url  = p => "file://" + encodeURI(p);
const base = p => p.slice(p.lastIndexOf("/") + 1);
const name = it => it.n || base(it.p);
const ICON = { vid: "\u25B6", aud: "\u266A" };
const LABEL = { ugo: "ANIM", img: "IMG", vid: "VID", aud: "AUD" };

document.getElementById("count").textContent = ITEMS.length + " items";

const cells = ITEMS.map((it, i) => {
  const d = document.createElement("div");
  d.className = "cell"; d.dataset.i = i;

  // Images and animations get a real thumbnail. Video and audio get a
  // placeholder, because generating a poster frame needs ffmpeg and this
  // device does not have it.
  if (it.t === "img" || it.t === "ugo") {
    const im = document.createElement("img");
    im.loading = "lazy"; im.decoding = "async";
    im.src = url(it.t === "ugo" ? it.th : it.p);
    d.appendChild(im);
  } else {
    const ph = document.createElement("div");
    ph.className = "ph"; ph.textContent = ICON[it.t] || "\u25A0";
    d.appendChild(ph);
  }

  const k = document.createElement("div");
  k.className = "kind"; k.textContent = LABEL[it.t] || "?";
  d.appendChild(k);

  const t = document.createElement("div");
  t.className = "tag"; t.textContent = name(it);
  d.appendChild(t);

  grid.appendChild(d);
  return d;
});

// --- viewer -------------------------------------------------------------
let cur = 0, rot = 0, nw = 0, nh = 0;
let timer = null, fi = 0, pre = [], playing = true;

function stopAnim() { if (timer) { clearTimeout(timer); timer = null; } }

function fit() {
  if (!nw || !nh) return;
  const sw = stage.clientWidth, sh = stage.clientHeight;
  const turned = (rot === 90 || rot === 270);
  const ew = turned ? nh : nw, eh = turned ? nw : nh;
  const s = Math.min(sw / ew, sh / eh);
  big.style.width = nw + "px"; big.style.height = nh + "px";
  big.style.transform =
    "translate(-50%,-50%) rotate(" + rot + "deg) scale(" + s + ")";
}

function clearStage() {
  stopAnim();
  pre.length = 0;                 // let the decoded frames go
  big.style.display = "none"; big.removeAttribute("src");
  vid.style.display = "none"; vid.pause(); vid.removeAttribute("src"); vid.load();
  aud.style.display = "none"; aud.pause(); aud.removeAttribute("src");
}

function stepAnim() {
  const it = ITEMS[cur];
  big.src = it.fr[fi].f ? url(it.fr[fi].f) : "";
  const w = Math.max(10, it.fr[fi].d);
  fi = (fi + 1) % it.fr.length;
  timer = setTimeout(stepAnim, w);
}

function open(i) {
  const v = shown();
  if (!ITEMS.length) return;
  cur = (i + ITEMS.length) % ITEMS.length;
  const it = ITEMS[cur];
  clearStage();
  rot = 0; nw = nh = 0; fi = 0; playing = true;
  playB.textContent = "Pause";
  cap.textContent = name(it);
  view.classList.add("on");

  if (it.t === "ugo") {
    big.style.display = "block";
    pre = it.fr.map(f => { const im = new Image(); im.src = url(f.f); return im; });
    stepAnim();
  } else if (it.t === "img") {
    big.style.display = "block";
    big.src = url(it.p);
  } else if (it.t === "vid") {
    vid.style.display = "block";
    vid.src = url(it.p);
    vid.play().catch(() => {});
  } else {
    aud.style.display = "block";
    aud.src = url(it.p);
    aud.play().catch(() => {});
  }
}

big.addEventListener("load", () => {
  if (!nw) { nw = big.naturalWidth; nh = big.naturalHeight; fit(); }
});

// A codec the browser cannot decode should say so rather than sit black.
vid.addEventListener("error", () => {
  cap.textContent = name(ITEMS[cur]) + "  —  this build of Firefox cannot decode it";
});

function close() { clearStage(); view.classList.remove("on");
  if (document.fullscreenElement) document.exitFullscreen(); }

function togglePlay() {
  const it = ITEMS[cur];
  playing = !playing;
  playB.textContent = playing ? "Pause" : "Play";
  if (it.t === "ugo") { if (playing) stepAnim(); else stopAnim(); }
  else if (it.t === "vid") { playing ? vid.play().catch(()=>{}) : vid.pause(); }
  else if (it.t === "aud") { playing ? aud.play().catch(()=>{}) : aud.pause(); }
}

grid.addEventListener("click", e => {
  const c = e.target.closest(".cell");
  if (c) open(Number(c.dataset.i));
});
document.getElementById("close").addEventListener("click", close);
document.getElementById("prev").addEventListener("click", () => open(cur - 1));
document.getElementById("next").addEventListener("click", () => open(cur + 1));
playB.addEventListener("click", togglePlay);
document.getElementById("rot").addEventListener("click", () => { rot = (rot + 90) % 360; fit(); });

function toggleFs() {
  if (document.fullscreenElement) document.exitFullscreen();
  else document.documentElement.requestFullscreen().catch(() => {});
}
document.getElementById("fs").addEventListener("click", toggleFs);
stage.addEventListener("dblclick", toggleFs);
document.addEventListener("fullscreenchange", () => {
  view.classList.toggle("fs", !!document.fullscreenElement);
  bump(); setTimeout(fit, 60);
});

let hideT = null;
function bump() { view.classList.add("show"); clearTimeout(hideT);
  hideT = setTimeout(() => view.classList.remove("show"), 2200); }
["mousemove","touchstart","keydown"].forEach(e =>
  document.addEventListener(e, bump, { passive: true }));

window.addEventListener("resize", fit);

// --- grid selection -----------------------------------------------------
let sel = 0;
const shown = () => cells.filter(c => !c.classList.contains("hidden"));

function cols() {
  const v = shown();
  if (v.length < 2) return 1;
  const top = v[0].offsetTop;
  let n = 0;
  for (const c of v) { if (c.offsetTop !== top) break; n++; }
  return Math.max(1, n);
}
function mark(i) {
  const v = shown();
  if (!v.length) return;
  sel = Math.max(0, Math.min(v.length - 1, i));
  cells.forEach(c => c.classList.remove("sel"));
  v[sel].classList.add("sel");
  v[sel].scrollIntoView({ block: "nearest" });
}

document.addEventListener("keydown", e => {
  if (view.classList.contains("on")) {
    switch (e.key) {
      case "Escape":     close(); break;
      case "ArrowRight": open(cur + 1); break;
      case "ArrowLeft":  open(cur - 1); break;
      case " ": case "Enter": e.preventDefault(); togglePlay(); break;
      case "f": case "F": toggleFs(); break;
      case "r": case "R": rot = (rot + 90) % 360; fit(); break;
    }
    return;
  }
  if (document.activeElement && document.activeElement.id === "q") {
    if (e.key === "Enter") { document.getElementById("q").blur(); mark(0); }
    return;
  }
  const c = cols();
  switch (e.key) {
    case "ArrowRight": e.preventDefault(); mark(sel + 1); break;
    case "ArrowLeft":  e.preventDefault(); mark(sel - 1); break;
    case "ArrowDown":  e.preventDefault(); mark(sel + c); break;
    case "ArrowUp":    e.preventDefault(); mark(sel - c); break;
    case "Home":       e.preventDefault(); mark(0); break;
    case "End":        e.preventDefault(); mark(shown().length - 1); break;
    case "Enter": case " ": {
      e.preventDefault();
      const v = shown();
      if (v[sel]) open(Number(v[sel].dataset.i));
      break;
    }
  }
});

// --- filters ------------------------------------------------------------
let kind = "all";
function apply() {
  const s = document.getElementById("q").value.toLowerCase();
  let n = 0;
  cells.forEach((c, i) => {
    const it = ITEMS[i];
    const hit = (kind === "all" || it.t === kind) &&
                (!s || name(it).toLowerCase().includes(s));
    c.classList.toggle("hidden", !hit);
    if (hit) n++;
  });
  empty.style.display = n ? "none" : "block";
  document.getElementById("count").textContent =
    (kind === "all" && !s) ? ITEMS.length + " items" : n + " of " + ITEMS.length;
  sel = 0; mark(0);
}
document.querySelectorAll(".tab").forEach(b => {
  b.addEventListener("click", () => {
    document.querySelectorAll(".tab").forEach(x => x.classList.remove("on"));
    b.classList.add("on");
    kind = b.dataset.f;
    apply();
  });
});
document.getElementById("q").addEventListener("input", apply);

mark(0);
</script>
</body>
</html>
TAIL
} > "$OUT"
sz=$(stat -c %s "$OUT" 2>/dev/null || echo 0)
echo "  Indexed $shown item(s), page is $((sz / 1024)) KB"
echo ""

# --- find Firefox -------------------------------------------------------
FF=""
for c in \
  /storage/apps/firefox-rocknix/firefox/firefox \
  /storage/apps/firefox-rocknix/firefox \
  /storage/roms/ports/firefox/firefox/firefox \
  /storage/roms/ports/firefox/firefox \
  "$(command -v firefox 2>/dev/null)"
do
  if [ -n "$c" ] && [ -x "$c" ] && [ ! -d "$c" ]; then FF="$c"; break; fi
done

if [ -z "$FF" ]; then
  echo "  Firefox not found."
  echo ""
  echo "  Looked in:"
  echo "    /storage/apps/firefox-rocknix/"
  echo "    /storage/roms/ports/firefox/"
  echo ""
  echo "  Edit the FF list at the top of this script"
  echo "  if yours lives somewhere else."
  echo ""
  line
  sleep 20
  exit 1
fi
echo "  Firefox  : $FF"

# --- find gptokeyb ------------------------------------------------------
GK=""
for c in \
  "$(command -v gptokeyb2 2>/dev/null)" \
  "$(command -v gptokeyb 2>/dev/null)" \
  /storage/roms/ports/PortMaster/gptokeyb2 \
  /storage/roms/ports/PortMaster/gptokeyb
do
  if [ -n "$c" ] && [ -x "$c" ]; then GK="$c"; break; fi
done
echo "  gptokeyb : ${GK:-none, gamepad will not work}"

# --- controller map -----------------------------------------------------
# Key names follow the Linux KEY_* constants with the prefix dropped, which
# is why it is "dot" rather than "period".
# Every comment is on its own line. The stock port maps never put one after
# a value, so there is no evidence gptokeyb strips a trailing comment, and a
# binding that silently becomes "enter        # open" is exactly the kind of
# failure that wastes an evening.
cat > "$GPTK" <<'EOF'
# Gallery - gamepad to the keys the gallery pages listen for.

left_analog_up = mouse_movement_up
mouse_scale = 5000
deadzone_mode = scaled_radial
deadzone = 2000
deadzone_scale = 7

up = up
down = down
left = left
right = right

# A opens, B goes back
a = enter
b = esc

# X fullscreen, Y rotate
x = f
y = r

# shoulders: step one frame, then speed
l1 = comma
r1 = dot
l2 = minus
r2 = equal

# pointer lives on the left stick, L3 clicks
l3 = mouse_left
r3 = home

# pause / play, and the on-screen keyboard
start = space
back = f12
EOF
echo "  Map      : $GPTK"

# --- lean profile -------------------------------------------------------
# A profile of its own, so this does not load your extensions or disturb
# your normal browsing session. Much lighter on 2GB.
mkdir -p "$PROFILE"
cat > "$PROFILE/user.js" <<'EOF'
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.archive.enabled", false);
user_pref("browser.pagethumbnails.capturing_disabled", true);
user_pref("gfx.webrender.software", true);
user_pref("dom.ipc.processCount", 1);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("browser.cache.disk.capacity", 20480);
user_pref("accessibility.force_disabled", 1);
user_pref("extensions.autoDisableScopes", 15);
EOF

# --- run ----------------------------------------------------------------
cleanup() {
  kill $GKPID 2>/dev/null
  killall gptokeyb  2>/dev/null
  killall gptokeyb2 2>/dev/null
  killall firefox   2>/dev/null
  killall firefox-bin 2>/dev/null
  command -v set_kill >/dev/null 2>&1 && set_kill stop
}
trap cleanup EXIT INT TERM HUP

GKPID=""
if [ -n "$GK" ]; then
  "$GK" "firefox" -c "$GPTK" >> "$LOG" 2>&1 &
  GKPID=$!
fi

# ROCKNIX global exit chord
command -v set_kill >/dev/null 2>&1 && set_kill set "firefox firefox-bin"

echo ""
line
echo "  Starting..."
echo ""

export MOZ_ENABLE_WAYLAND=1
export HOME="/storage"
export MALLOC_ARENA_MAX=2

"$FF" --kiosk --no-remote --profile "$PROFILE" "file://$OUT" >> "$LOG" 2>&1

exit 0
