# Verbatim

A minimal native macOS notes app that leaves your text alone. macOS 14 or later.

Verbatim uses an AppKit `NSTextView` with rich text, smart punctuation, replacement,
correction, completion, link/data detection, and smart insertion disabled. Its
subclass refuses attempts to enable these settings; its menus expose no
substitution controls. Spell and grammar checking default off. UTF-8 text is
written atomically without trimming or normalizing the content.

## Build

Requires Xcode 16 or later with the macOS SDK and command-line tools selected
(the deployment target remains macOS 14). Tested with Xcode 27.2.

```sh
make build   # universal release app: .build/Build/Products/Release/Verbatim.app
make run
make test
make install # copy the app to /Applications (override with APPDIR=...)
make release # Developer ID signed, notarized zip in .build/dist (see scripts/release.sh)
```

The checked-in Xcode project builds without a project generator. `project.yml` is
its development source (regenerate with XcodeGen when changing target structure).
There are no third-party runtime dependencies.

Notes are ordinary files, not records in a proprietary database. Deleting the
app leaves your notes intact.

## Use

On first launch, authorize a folder using the macOS folder chooser. The suggested
location is `~/Documents/Verbatim` (create it with **New Folder** if necessary).
Verbatim remembers access with a security-scoped bookmark. Use **File → Choose
Notes Folder…** to change it.

- The note list is always ordered by last modified, newest first, and each row
  shows when its note last changed. Editing a note moves it to the top.
- **Cmd+L:** search titles and bodies; use Up/Down to select a result.
- **Return in search:** open the selected result, or create a note from the query
  when there are no matches. If body search is still running, Return waits for
  its result before creating a note.
- **Cmd+N:** create an empty note. **Cmd+F:** find inside the current note.
- **Cmd+S:** save immediately. **Cmd+Delete:** move the current note to Trash.
- **Cmd+,**: choose the editor font and size. Spelling and grammar checking are
  optional Edit menu toggles, both off by default.

Typing never invokes app-provided auto-capitalization, list continuation, or rich
text formatting. Paste inserts the clipboard's plain string. Search uses the
same guarded text view, so creating a title through search also avoids smart
substitutions. Inline predictions are also disabled, as are math completions and
Writing Tools on macOS versions that provide them. macOS input methods,
dictation, and explicitly invoked spelling
replacements still supply text chosen by you or the input method.

## Plain files, safe saves

Only immediate, non-hidden, regular `.txt` files in the chosen folder are notes;
subfolders and symlinks are ignored. Files must be valid UTF-8. Unsupported files
are left untouched. The first line is the title, with **Untitled** as the display
fallback for an empty or whitespace-only first line, or one holding only
attachment placeholders. Existing text is never
trimmed, normalized, or rewritten merely by opening it.
UTF-8 byte-order marks and existing line endings are preserved; a leading
byte-order mark is excluded from the displayed title and derived filename.

After roughly 500ms of inactivity, edits save in the background. Changing the
first line also changes the filename during that save. Unsafe filename
characters are replaced, stems are limited to 180 UTF-8 bytes, and collisions
receive suffixes starting at `2`. A body-only edit keeps an externally chosen
filename. Close, quit, note switches, and loss of focus flush pending changes;
close and quit are cancelled if saving fails.

New files are staged and published with an exclusive atomic rename. Existing
files use atomic replacement, coordinated with cooperating filesystem clients.
The original disk bytes are checked before replacement. If they changed or the
file disappeared, your edits go into a separate `Title (conflict).txt`, and a
small status notice explains what happened. A failed rename leaves the saved
text at its old filename and reports the failure. Deletion uses macOS Trash.

FSEvents watches for external edits, including in-place writes and atomic saves.
Clean open notes reload automatically. Conflicting edits preserve both versions.
No software can guarantee recovery from hardware failure or prevent every race
with an external writer that ignores file coordination. Save failures remain
visible; there is no proprietary recovery database.

Metadata loads off the UI thread. Titles load in batches; body search is
cancellable and uses a bounded 16 MiB cache. Filenames appear until title loading
finishes, and body search reports when it is still running. No persistent index
is required. A folder can live on iCloud Drive or Dropbox, but Verbatim has no
sync service, accounts, analytics, or networking code or network entitlements.

## Verification

Tests cover all substitution flags and toggle actions, literal typing, title
derivation, filename sanitizing and deduplication, search, atomic replacement
under concurrent reads, conflict handling, serial autosaves, real folder events,
and external-edit reconciliation through the window controller. A generated
10,000-note fixture exercises metadata enumeration and body search. Test note
files live in temporary directories.

The universal build includes arm64 and x86_64. Signing is local/ad hoc by default;
`make release` signs with your Developer ID certificate and notarizes the result.
Cold launch below 300ms, Intel runtime behavior, macOS 14 runtime behavior, and
real third-party sync services require separate verification.

Local measurements on Apple Silicon with Xcode 27.2: the Debug test's 10,000
recently created notes took approximately 97ms to enumerate, 0.3ms to open one,
and 344ms for a first body search. Five Release process launches with an already
authorized folder reached a loaded editor in **318, 274, 235, 276, and 269ms**.
These include process startup but do not establish cold-cache timing or first
frame presentation. A later first launch after rebuilding took **444ms**, followed
by **255, 273, and 269ms** launches. The 300ms target is **not consistently met**
on this development machine.
To reproduce the launch measurement after building and authorizing a folder:

```sh
# Close Verbatim first; do not type into it while the benchmark runs.
python3 scripts/measure-launch.py --runs 5
```

The script terminates only the processes it creates, immediately after readiness.

## Import Apple Notes

The build includes a separate `verbatim` command, also bundled at
`Verbatim.app/Contents/Helpers/verbatim`:

```sh
.build/Build/Products/Release/verbatim --import-notes
.build/Build/Products/Release/verbatim --import-notes --folder "$HOME/path/to/notes"
make install-cli  # development symlink in ~/.local/bin; override PREFIX if desired
verbatim --help
```

The default import destination is `~/Documents/Verbatim`. If the app uses another
folder, pass that folder explicitly with `--folder`. Run the tool from Terminal;
macOS will request permission to automate Notes. The GUI remains sandboxed and
has no Notes automation entitlement; only this separately invoked, unsandboxed
CLI has the Apple Events entitlement and privacy usage description. Running
`verbatim` with no arguments opens the app.

The importer asks Apple Notes for its native `plaintext` property, one note at a
time. It never modifies or deletes the originals. All notes exposed by Notes'
scripting interface are flattened into the destination; password-protected notes
are skipped. Each imported file is stamped with its note's modification date, so
the list keeps the order you had in Notes. Formatting, attachments, folder/account
hierarchy, and creation dates are not exported. Any attachment placeholders
supplied by Notes remain ordinary text.
Notes must be locally available to Notes; the tool does not fetch cloud data itself.

Existing destination files are never overwritten. Identical UTF-8 bytes found
along a title's filename collision sequence are skipped, so typical re-runs do
not duplicate notes. Identical source notes may therefore collapse into one
file. If you remove a file leaving a gap in that sequence, a later import may
create another copy. No import manifest is required. The final counts report
imports, identical copies, locked notes, and failures; failures produce a nonzero
exit status while preserving files already imported.

The importer is tested with synthetic Notes data and its AppleScript is compiled
without execution. Access to a real Notes library and macOS's Automation consent
flow have **not** been exercised during development.

Licensed under Apache License 2.0; see [LICENSE](LICENSE).
