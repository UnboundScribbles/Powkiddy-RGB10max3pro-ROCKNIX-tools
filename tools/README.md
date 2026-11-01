# Tools

Each one is a single `.sh` you copy into your ports folder. All of them write
their results to a text file, because console output is not visible when a script
runs from the Ports menu.

## runelite/RuneLite Fit Screen.sh

Makes RuneLite usable on an 854x480 screen. Run it with RuneLite closed.

Two separate problems get fixed. RuneLite defaults `automaticResizeType` to
`KEEP_GAME_SIZE`, which *widens the window* when a side panel opens so the game
area stays 765 wide; on an 854 screen the window grows to about 1005 and
right-click menus open off the edge. And the fixed layout is 765x503, so a 480
tall screen loses the bottom 23 pixels no matter what, which the Stretched Mode
plugin solves by scaling the canvas.

The script edits `.runelite/profiles2/<profile>.properties`, which is where
current RuneLite keeps live config. Editing `settings.properties` does nothing:
that file is only read as migration input, and only when no profile exists yet.

Keys set: `runelite.gameSize`, `runelite.automaticResizeType`,
`runelite.containInScreen2`, `runelite.lockWindowSize`,
`runelite.stretchedmodeplugin`, `stretchedmode.keepAspectRatio`,
`stretchedmode.increasedPerformance`. Backs up to `.bak`, merges rather than
overwrites, idempotent, and refuses to run while java is running.

Variables at the top: `GAME_W`, `GAME_H`, `STRETCH`, `KEEP_ASPECT`.

## unzip-files/Unzip_Files.sh

Extract archives without SSH. Put them in `/storage/roms/_unzip/` and run it.
Each archive extracts into its own folder beside it, originals kept, log at
`_unzip/unzip-log.txt`.

## gog-installer/Extract GOG Installer.sh

Unpacks GOG `.sh` and `.exe` installers on the device, so a game bought from GOG
can be fed to a port that expects the game's data files. Uses the `7zzs` and
`innoextract` binaries PortMaster already ships.

## gallery/

`Gallery.sh` indexes images, converted ugoira animations, video and audio from a
set of folders and opens the result in Firefox with no browser UI and the
controller mapped to it. `Media_Gallery.sh` is the earlier version that builds
the page only, at `file:///storage/roms/_media.html`, which is useful if you
would rather open it yourself.

Edit `FOLDERS` at the top of either to choose what gets indexed. `Gallery.sh`
needs Firefox installed, see [`../firefox/`](../firefox/).

## port-diagnostics/Port Diagnostics.sh

Collects system info, installed runtimes, key-file checks, folder layouts and log
tails for a list of ports into `ports/port-diagnostics.txt`, so one file can be
pulled off the card instead of hunting through folders on the device.

Edit `PORTS` and `KEYFILES` at the top for whichever port is misbehaving.

## github-upload/Upload To GitHub.sh

Uploads a folder to GitHub from the device, with no git installed and no PC
involved. It serves a form on `127.0.0.1` in Firefox, takes a personal access
token, and then creates the repository and commits every file through GitHub's
REST API.

This is how this repository got to GitHub in the first place. See
[`github-upload/README.md`](github-upload/README.md).
