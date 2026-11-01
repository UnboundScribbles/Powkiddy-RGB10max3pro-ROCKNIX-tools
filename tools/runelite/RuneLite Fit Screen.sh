#!/bin/bash
# RuneLite Fit Screen v2 - make the client fit an 854x480 handheld panel.
#
# Run from the Ports menu, with RuneLite CLOSED.
#
# WHY v1 DID NOTHING
#   v1 wrote to .runelite/settings.properties. That file is only read once,
#   as migration input, and only when no profile exists yet:
#       if (profiles.isEmpty() && configFile.exists())
#   Your client already had a profile, so the file was ignored. Your log said
#   "Using profile: default (5857646562209)" with no migration line, which
#   was the proof. Current RuneLite keeps live config in
#       .runelite/profiles2/<name>-<id>.properties
#   This version edits that.
#
# WHAT IS ACTUALLY WRONG
#   Two separate things.
#
#   1. Resize type. RuneLiteConfig.java defaults automaticResizeType to
#      KEEP_GAME_SIZE, which WIDENS the window when a side panel opens so the
#      game area stays 765 wide. The panel is roughly 240px, so the window
#      grows to about 1005 on an 854 screen. Everything past the edge is
#      unreachable and right-click menus open into the void. That is your
#      "menu items shoot off the right side".
#      KEEP_WINDOW_SIZE shrinks the game area instead, so the window never
#      grows past the screen.
#
#   2. Height. OSRS's fixed layout is 765x503. Your panel is 480 tall, so even
#      a correctly placed window loses the bottom 23px. No window setting
#      fixes that, because the fixed canvas is a fixed size. The Stretched
#      Mode plugin scales that canvas to whatever the window is, which does.
#      It ships disabled (enabledByDefault = false), so it gets turned on.
#
# Keys verified against RuneLite source, not guessed:
#   ConfigManager.getWholeKey() -> group + "." + key when profile is null,
#   so plain settings are runelite.<keyName>.
#   PluginManager.setPluginEnabled() -> runelite.<classname lowercased>,
#   so StretchedModePlugin is runelite.stretchedmodeplugin.
#   StretchedModeConfig is @ConfigGroup("stretchedmode").
#
# Idempotent. Run it as often as you like.

# --- what to set ---------------------------------------------------------
GAME_W=854
GAME_H=480

# Stretched Mode scales the 765x503 fixed canvas to the window.
STRETCH=on

# on  = scale to fit height, small black bars at the sides, no distortion
# off = fill the whole 854x480, image stretched about 17% wide
KEEP_ASPECT=on
# ------------------------------------------------------------------------

notify() {
  echo "$*"
  command -v pm_message >/dev/null 2>&1 && pm_message "$*"
}

line() { echo "============================================"; }

clear 2>/dev/null
line
echo "  RUNELITE FIT SCREEN  v2"
line
echo ""

# --- do not run while the client is up ----------------------------------
# RuneLite holds config in memory and writes the whole file out on exit.
# Editing underneath a running client just gets overwritten.
if pgrep -x java >/dev/null 2>&1; then
  notify "RuneLite looks like it is still running.

It rewrites its settings when it closes, so anything changed now would be
thrown away.

Quit RuneLite (L1 + SELECT + START) and run this again."
  sleep 15
  exit 1
fi

# --- find the config folder ---------------------------------------------
# The launcher sets HOME to the port folder, so config normally lives in
# <port dir>/.runelite. But ROCKNIX has two roms locations and PortMaster's
# $directory only names one, and /storage/.runelite shows up too depending on
# how the client was first started. Prefer whichever candidate actually has a
# profiles2 folder, since that is the one in use.
RLDIR=""
FALLBACK=""
for d in \
  /storage/roms/ports/runelite/.runelite \
  /storage/games-external/roms/ports/runelite/.runelite \
  /storage/.runelite \
  "$HOME/.runelite"
do
  [ -d "$d" ] || continue
  [ -z "$FALLBACK" ] && FALLBACK="$d"
  if [ -d "$d/profiles2" ]; then
    RLDIR="$d"
    break
  fi
done

[ -z "$RLDIR" ] && RLDIR="$FALLBACK"

if [ -z "$RLDIR" ]; then
  notify "Could not find RuneLite's .runelite folder.

Launch RuneLite once so it creates one, then run this again."
  sleep 15
  exit 1
fi

echo "  Config dir : $RLDIR"

PROFDIR="$RLDIR/profiles2"
if [ ! -d "$PROFDIR" ]; then
  notify "No profiles2 folder in:
$RLDIR

That means RuneLite has not finished a first run here. Launch it, log in,
quit cleanly, then run this again."
  sleep 15
  exit 1
fi

command -v python3 >/dev/null 2>&1 || {
  notify "python3 not found. Cannot edit the config."
  sleep 10; exit 1; }

echo ""
echo "  Profiles found:"
ls -1 "$PROFDIR" 2>/dev/null | sed 's/^/    /'
echo ""

# --- pick the profile ----------------------------------------------------
# Not read from profiles.json: its "active" flag means "a client currently has
# this open", not "this is the selected one", so after a clean exit it can be
# false for everything. Instead take the newest .properties, preferring one
# called default-*, which is what your log named.
TARGET=""
for f in "$PROFDIR"/default-*.properties; do
  [ -f "$f" ] && TARGET="$f" && break
done

if [ -z "$TARGET" ]; then
  TARGET="$(ls -1t "$PROFDIR"/*.properties 2>/dev/null | head -1)"
fi

# No properties file at all: the profile exists in profiles.json but has never
# been written. Create it under the right name so RuneLite picks it up.
if [ -z "$TARGET" ]; then
  echo "  No .properties file yet, deriving the name from profiles.json"
  NAMEID="$(python3 - "$PROFDIR/profiles.json" <<'PY'
import sys, json, os
p = sys.argv[1]
try:
    with open(p) as f:
        d = json.load(f)
except Exception:
    sys.exit(1)
profs = d.get("profiles") or []
if not profs:
    sys.exit(1)
pick = next((x for x in profs if x.get("name") == "default"), profs[0])
n, i = pick.get("name"), pick.get("id")
if not n or i is None:
    sys.exit(1)
print(f"{n}-{i}.properties")
PY
)"
  if [ -z "$NAMEID" ]; then
    notify "Could not work out which profile to edit.

Send me a listing of:
$PROFDIR"
    sleep 15
    exit 1
  fi
  TARGET="$PROFDIR/$NAMEID"
  echo "  Will create : $(basename "$TARGET")"
fi

echo "  Editing     : $(basename "$TARGET")"

if [ -f "$TARGET" ]; then
  cp -f "$TARGET" "${TARGET}.bak"
  echo "  Backup      : $(basename "$TARGET").bak"
fi
echo ""

case "$KEEP_ASPECT" in on|ON|1|true) ASPECT=true ;; *) ASPECT=false ;; esac
case "$STRETCH"     in on|ON|1|true) DOSTRETCH=true ;; *) DOSTRETCH=false ;; esac

python3 - "$TARGET" "$GAME_W" "$GAME_H" "$DOSTRETCH" "$ASPECT" <<'PYEOF'
import sys, os

cfg, w, h, stretch, aspect = sys.argv[1:6]

# Plain settings are stored as runelite.<keyName>: ConfigManager.getWholeKey()
# returns group + "." + key when the profile is null, which it is for
# everything except per-account (rsprofile) config.
wanted = {
    # Resizable-mode canvas size. Format is WxH, parsed with str.split("x").
    "runelite.gameSize": f"{w}x{h}",

    # THE one that matters. Default KEEP_GAME_SIZE widens the window when a
    # side panel opens, pushing the right edge off a small screen.
    "runelite.automaticResizeType": "KEEP_WINDOW_SIZE",

    # Keep the frame on screen while it is being resized.
    "runelite.containInScreen2": "RESIZING",

    # Left unlocked so dragging the edges still works.
    "runelite.lockWindowSize": "false",
}

if stretch == "true":
    # PluginManager stores enabled state as runelite.<simple class name>
    # lowercased. StretchedModePlugin sets no configName, so this is the key.
    wanted["runelite.stretchedmodeplugin"] = "true"
    # @ConfigGroup("stretchedmode")
    wanted["stretchedmode.keepAspectRatio"] = aspect
    # Nearest-neighbour rather than bilinear. Cheaper per frame, which is
    # worth having on a Mali-G52 that is already scaling every frame.
    wanted["stretchedmode.increasedPerformance"] = "true"
    # integerScaling deliberately left alone. Forcing integer steps would
    # mean 1x, since 2x does not fit, which defeats the point.

lines = []
if os.path.exists(cfg):
    with open(cfg, "r", encoding="utf-8", errors="replace") as f:
        lines = f.read().splitlines()

seen, out, changed = set(), [], []
for ln in lines:
    s = ln.strip()
    # Java writes a timestamp comment at the top. Keep comments and blanks.
    if not s or s.startswith("#") or s.startswith("!") or "=" not in ln:
        out.append(ln)
        continue
    key = ln.split("=", 1)[0].strip()
    if key in wanted:
        old, new = ln.split("=", 1)[1].strip(), wanted[key]
        seen.add(key)
        if old != new:
            changed.append((key, old, new))
            out.append(f"{key}={new}")
        else:
            out.append(ln)
    else:
        out.append(ln)

for key, val in wanted.items():
    if key not in seen:
        changed.append((key, "(unset)", val))
        out.append(f"{key}={val}")

os.makedirs(os.path.dirname(cfg), exist_ok=True)
with open(cfg, "w", encoding="utf-8") as f:
    f.write("\n".join(out) + "\n")

if changed:
    print("  Changed:")
    for k, o, n in changed:
        print(f"    {k}")
        print(f"        {o}  ->  {n}")
else:
    print("  Already correct, nothing to change.")

print("")
print("  Keys in file: %d" % len(
    [l for l in out if "=" in l and not l.strip().startswith("#")]))
PYEOF

RC=$?
echo ""
line

if [ "$RC" -ne 0 ]; then
  notify "Failed to update the config.

Your original is at:
${TARGET}.bak"
  sleep 15
  exit 1
fi

echo "  Done."
echo ""
echo "  Launch RuneLite. The window should stay inside the screen"
echo "  even with the sidebar open."
echo ""
echo "  If the image looks squashed, set KEEP_ASPECT=off at the top"
echo "  of this script for a full-screen stretch instead, or"
echo "  STRETCH=off to turn scaling off altogether."
echo ""
line
echo ""

notify "RuneLite window settings updated.

Resize type : Keep window size
Game size   : ${GAME_W}x${GAME_H}
Stretch     : ${STRETCH} (keep aspect: ${KEEP_ASPECT})

The resize type is the fix for menus running off the right edge. Stretched
Mode is what gets the bottom 23px back, since the fixed layout is 503 tall
and your screen is 480.

Edited: $(basename "$TARGET")
Backup: $(basename "$TARGET").bak"

sleep 12
exit 0
