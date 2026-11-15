# Contributing to Verbatim

Thanks for your interest. Issues labeled
[good first issue](https://github.com/keithballinger/verbatim/labels/good%20first%20issue) and
[help wanted](https://github.com/keithballinger/verbatim/labels/help%20wanted) are the best places to start.
For anything larger, or anything that changes how the app behaves, open an issue first so the approach can be
agreed on before you write code.

## What Verbatim is for

Verbatim leaves your text alone. Changes need to keep these promises, which the README describes in detail:

- No smart punctuation, autocorrection, completion, link detection or other substitution, and no menu items
  that turn them on.
- Notes are ordinary UTF-8 `.txt` files. Opening a note never rewrites, trims or normalizes it.
- Saves are atomic, and a conflicting external edit keeps both versions.
- No networking, accounts, analytics or sync service.
- The app stays sandboxed. Only the separate `verbatim` command line tool may automate Apple Notes.

A pull request that trades one of these away is unlikely to be merged.

## Build and test

You need Xcode 16 or later. No signing certificate is required; builds are ad hoc signed by default.

```sh
make build   # universal Release app in .build/Build/Products/Release
make test    # the full test suite
make run     # build and open the app
```

The tests are hosted by the app, so a Verbatim process starts while they run. They use temporary folders and
never open your notes folder.

`make release` signs with a Developer ID certificate and notarizes the result. Only the maintainer needs it.

## Changing the project structure

`project.yml` is the source for the Xcode project. If you add, remove or rename a file or target, or change a
build setting, edit `project.yml`, run `xcodegen generate`, and commit both `project.yml` and the regenerated
`Verbatim.xcodeproj`.

## Pull requests

- `main` only accepts changes through pull requests.
- Pull requests are squash-merged, and the pull request's title and description become the commit message.
  Write them to stand alone: what changed and why.
- Keep each pull request to one change.
- Run `make test` before you open it, and add or update tests for behavior you change.
- Say what you tested by hand, including the macOS version and whether the Mac is Apple silicon or Intel.
- Update the README when you change behavior it describes.

## Reporting bugs

Include your macOS version, your Mac's processor, the Verbatim version, and the steps that lead to the problem.
If a note's contents were changed or lost, say exactly what the file held before and after; that is the most
serious kind of bug this project can have.
