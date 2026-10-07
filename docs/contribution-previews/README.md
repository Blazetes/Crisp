# Display-control contribution previews

These PNGs render the contribution branches' native SwiftUI views at Crisp's 308-point panel width, in English, Simplified Chinese, and Traditional Chinese.

Display and input services are fixtures. They do not change real monitor connections. The Tools-preference fixture uses the production SettingsService and PanelSectionState with inert hardware services, and verifies persistence across separate process launches and section reset behavior.

Validation: https://github.com/Blazetes/Crisp/actions/runs/37586562363

Final single-switch alignment (22e17ab): https://github.com/Blazetes/Crisp/actions/runs/37588176832/attempts/2

These previews verify the row layout and translated strings. They are not screenshots of a deployed Crisp build and do not establish real hardware behavior.
