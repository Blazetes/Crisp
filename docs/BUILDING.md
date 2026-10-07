# Building Crisp

**TL;DR:** with full Xcode installed, run `./dev.sh`, which compiles the binary
and vector assets, updates the installed `/Applications/Crisp.app`, syncs the
version from `project.yml`, re-signs, and relaunches. The rest of this doc explains what it does.

You can build the full .app in Xcode (`xcodegen generate`, then archive), or a
full DMG with `./scripts/release.sh vX.Y.Z` (swiftc, with Xcode for vector assets
and Shortcuts actions). The binary alone can compile with matching Command Line
Tools and a macOS 26-or-newer SDK, but this does not compile the SVG assets:

```sh
./scripts/fetch-sparkle.sh   # once: vendors the Sparkle updater framework
swiftc -O -swift-version 6 -parse-as-library \
  -target arm64-apple-macos14.0 \
  -import-objc-header Crisp/Crisp-Bridging-Header.h \
  -framework AppKit -framework SwiftUI -framework IOKit -framework CoreAudio \
  -F vendor/Sparkle -framework Sparkle \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -Xlinker -undefined -Xlinker dynamic_lookup \
  Crisp/App/*.swift Crisp/Models/*.swift Crisp/Services/*.swift \
  Crisp/Views/*.swift Crisp/Utilities/*.swift \
  -o Crisp-bin
```

To run a binary-only build, the existing bundle must already contain matching
`Contents/Resources/Assets.car`, Shortcuts metadata and Sparkle.framework. Prefer
`./dev.sh` to synchronize these app resources before re-signing:

```sh
pkill -x Crisp
cp Crisp-bin /Applications/Crisp.app/Contents/MacOS/Crisp
xattr -cr /Applications/Crisp.app
codesign --force -s - --entitlements Crisp/Crisp.entitlements /Applications/Crisp.app
open /Applications/Crisp.app
```

The fast dev loop is edit, compile, synchronize resources, re-sign, relaunch.
`dev.sh` requires full Xcode to compile the SVG asset catalog before the swap.

## Shortcuts actions

Shortcuts finds Crisp's actions through `Contents/Resources/Metadata.appintents`, which an Xcode build writes. `scripts/appintents.sh` does the same for the swiftc build: swiftc emits the App Intents types' const values, and `appintentsmetadataprocessor` turns them into the metadata. Both steps need Xcode's toolchain. Both release and dev builds require it and regenerate the metadata. After a deploy, Shortcuts picks up changed actions only after `lsregister -f /Applications/Crisp.app` and a relaunch of Shortcuts.

## crispctl

`dev.sh` updates the app binary/resources, not the CLI. To build the command line tool on its own (the same sources `scripts/release.sh` uses):

```sh
swiftc -O -swift-version 6 -target arm64-apple-macos14.0 \
  Sources/crispctl/*.swift Crisp/Models/CrispControlModel.swift Crisp/Models/BrightnessKeySteps.swift \
  -o crispctl
```

With full Xcode, `xcodegen generate && xcodebuild -scheme crispctl -configuration Release` does the same.

## Before opening a PR

Run `make check`: it runs SwiftLint (strict), the unit tests, the x86_64
typecheck, and the localization key check, the same checks CI enforces, so
failures surface locally instead of on the PR. It needs full Xcode plus
`swiftlint` and `xcodegen` (`brew install swiftlint xcodegen`). To run it
automatically on every push, opt in once:

```sh
git config core.hooksPath .githooks
```

The app icon is generated from vector code: `scripts/generate-icon.swift`.
