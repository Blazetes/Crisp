# Display-control contribution previews

## Local Xcode 27 Validation (2026-10-08)

The single-display previews now render source `8570f4cc4ab9d19984c447dabbd379ef0b4212f5`. Its exact-source local `make check`, Chinese translations, complete universal release dry run (`v0.0.0-ci`), deep signature/DMG checks and three-language native fixture rendering passed with Xcode 27.0 / SDK 27.0.

The batch previews now render source `d7137e289676e48ebc9891ce0d1458942ad30b1b`: one external-display switch with a four-column name grid, equal 16:9 diagonal SVG and a same-row mixed-state recovery button. Exact-source local checks, translations, full universal release, signatures/DMG integrity, mock service assertions and 33 native previews passed. The actual full application asset resolves and renders at 16/20/24/32px with transparent borders. Additional Chinese previews show eight displays, mixed state and a protected desktop keeper.

Tools source `163007a119b024287010824c5a2e16e02814b1ce` was independently revalidated locally with Xcode 27.0 / SDK 27.0: complete make check, Chinese translations, universal release, signatures/DMG integrity, production preference write/reload in separate fixture processes, section reset assertions and three-language UI rendering all passed. Its source remains unchanged.

The physical backend guards remain active until blocking transactions actually finish, including after a UI timeout. Live display changes, clamshell/sleep recovery and installed-app interaction have not been tested. Earlier validation links below describe their explicitly listed revisions.

These PNGs render the contribution branches' native SwiftUI views at Crisp's 308-point panel width, in English, Simplified Chinese, and Traditional Chinese.

Display and input services are fixtures. They do not change real monitor connections. The Tools-preference fixture uses the production SettingsService and PanelSectionState with inert hardware services, and verifies persistence across separate process launches and section reset behavior.

Validation: https://github.com/Blazetes/Crisp/actions/runs/37586562363

Final single-switch alignment (22e17ab): https://github.com/Blazetes/Crisp/actions/runs/37588176832/attempts/2

Final batch controls, including physical mirror targets (b0fc3d9): https://github.com/Blazetes/Crisp/actions/runs/37589974607

All three features compiled and checked together (e149249): https://github.com/Blazetes/Crisp/actions/runs/37589976364

These previews verify the row layout and translated strings. They are not screenshots of a deployed Crisp build and do not establish real hardware behavior.
