# Upload To GitHub

Put a folder on GitHub from the handheld. No git, no PC.

## Why it works this way

ROCKNIX has no git. It does have Python 3, and GitHub's REST API can do
everything a push does here: write each file as a blob, build a tree, make a
commit, move the branch. `upload.py` does exactly that.

The awkward part is the token. A script launched from the Ports menu has
nowhere to type 40 characters, so the script serves a form on `127.0.0.1` and
opens it in Firefox. GitHub's token page has a copy button, and a form field
accepts a paste, so the input problem solves itself.

## Install

```
ports/Upload To GitHub.sh
ports/github-upload/upload.py
```

The `.sh` has to sit at the top of the ports folder or EmulationStation will not
list it. Keep `upload.py` in the `github-upload` folder beside it.

## Use

1. Make sure the folder you want to upload is on the device. `Unzip Files`
   handles a `.tar.gz` if you downloaded one.
2. Run **Upload To GitHub** from the Ports menu. It finds the folder, starts the
   uploader and opens the form in Firefox.
3. Follow the link on the page to GitHub's token page. The `repo` scope is
   already ticked on that link. Generate the token and press GitHub's copy
   button.
4. **L1 + D-pad Left** goes back to the form. Paste with **L2 + X**.
5. Check the repository name, then Create and upload. Progress appears as it
   goes.

## Controls

| | |
|---|---|
| Left stick | mouse pointer |
| L3 | click |
| R1 | next field |
| SELECT | on-screen keyboard |
| L2 + X | paste |
| L1 + D-pad Left | browser back |
| L1 + SELECT + START | quit |

Paste is two bindings rather than a combo: L2 holds leftctrl and X sends v. That
avoids depending on gptokeyb's combo syntax, which differs between gptokeyb and
gptokeyb2.

## Notes

- The token is used for that one upload and never written to disk. The logs hold
  file names and API results, never the token.
- Run it again later and it adds a commit to the existing repository rather than
  starting over.
- Shell scripts are committed with the executable bit set, whatever the card they
  came off could record.
- Left out of every upload: `.git`, `__pycache__`, `runtimes`, `conf`, `.pyc`,
  `.bak`, editor leftovers, `.DS_Store`, and the `._name` AppleDouble files that
  appear when an archive is made on a Mac.
- Anything over 40 MB is skipped with a line in the log.

## Logs

```
ports/github-upload.log          the launcher: python, Firefox, gptokeyb, startup
ports/github-upload-run.log      the upload itself, file by file
```

## Testing

`upload.py` takes two environment variables that exist for testing:
`GH_DRY=1` walks through everything without calling GitHub, and `GH_API` points
it at another base URL, which is how the whole call sequence was tested against
a mock before it ever saw a real token.
