# Verbatim

A minimal native macOS notes app that leaves your text alone. macOS 14 or later.

Verbatim uses an AppKit `NSTextView` with rich text, smart punctuation, replacement,
correction, completion, link/data detection, and smart insertion disabled. Its
subclass refuses attempts to enable these settings; its menus expose no
substitution controls. Spell and grammar checking default off. UTF-8 text is
written atomically without trimming or normalizing the content.

## Build

Requires Xcode with macOS SDK and command-line tools selected.

```sh
make build   # universal release app: .build/Build/Products/Release/Verbatim.app
make run
make test
```

The checked-in Xcode project builds without a project generator. `project.yml` is
its development source (regenerate with XcodeGen when changing target structure).
There are no third-party runtime dependencies.

Notes are ordinary files, not records in a proprietary database. Deleting the
app leaves your notes intact.

Licensed under Apache License 2.0; see [LICENSE](LICENSE).
