require 'fileutils'
require 'json'

source, feature, output = ARGV
FileUtils.mkdir_p(output)
menu = File.read(File.join(source, 'Crisp/Views/MenuBarView.swift'))
blocks = File.read(File.join(source, 'Crisp/Views/PanelBlocks.swift'))

def section(text, first, last)
  start = text.index(first) or abort "Missing source marker: #{first}"
  finish = text.index(last, start) or abort "Missing source marker: #{last}"
  text[start...finish]
end

helpers = "import SwiftUI\nimport AppKit\n"
helpers += section(menu, 'struct MenuItemIcon', '/// Native menus ignore')
helpers += section(menu, 'struct MenuRowHover', "extension View {\n    /// Keep scroll")
helpers += section(menu, 'struct ExpandableRow', '// MARK: - UpdateRow')
if feature == 'keep-tools-expanded'
  helpers += section(blocks, "@MainActor\nfinal class PanelSectionState", '/// Wraps a block')
  helpers += section(blocks, 'struct KeepAwakeRow', '/// Saved and off by default, unlike Keep Awake')
else
  helpers += section(blocks, 'struct DisconnectBuiltinRow', '/// Update notice')
end
File.write(File.join(output, 'Helpers.swift'), helpers)

app = File.join(output, 'Fixture.app')
resources = File.join(app, 'Contents/Resources')
FileUtils.mkdir_p(resources)
FileUtils.mkdir_p(File.join(app, 'Contents/MacOS'))
File.write(File.join(app, 'Contents/Info.plist'), <<~PLIST)
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.blazetes.crisp-ui-fixture</string>
  <key>CFBundleExecutable</key><string>Fixture</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>zh-Hans</string><string>zh-Hant</string></array>
  <key>LSUIElement</key><true/>
  </dict></plist>
PLIST
catalog = JSON.parse(File.read(File.join(source, 'Crisp/Resources/Localizable.xcstrings')))
%w[en zh-Hans zh-Hant].each do |language|
  directory = File.join(resources, "#{language}.lproj")
  FileUtils.mkdir_p(directory)
  strings = catalog.fetch('strings').map do |key, value|
    translated = value.dig('localizations', language, 'stringUnit', 'value') || key
    "#{key.to_json} = #{translated.to_json};"
  end
  File.write(File.join(directory, 'Localizable.strings'), strings.join("\n"))
end

sources = [File.join(__dir__, 'UIFixtures.swift'), File.join(output, 'Helpers.swift')]
flags = ['-swift-version', '6', '-parse-as-library', '-target', 'arm64-apple-macos14.0']
case feature
when 'display-connection-switch'
  flags += ['-D', 'FEATURE_SWITCH']
  sources << File.join(source, 'Crisp/Views/PhysicalDisplayToggleView.swift')
when 'batch-display-connections'
  flags += ['-D', 'FEATURE_BATCH']
  sources += %w[Crisp/Models/DisplayConnectionPlan.swift Crisp/Services/BatchDisplayConnectionService.swift Crisp/Views/BatchDisplayConnectionView.swift].map { |path| File.join(source, path) }
when 'keep-tools-expanded'
  flags += ['-D', 'FEATURE_TOOLS']
  sources += %w[Crisp/Models/CombinedBrightnessMath.swift Crisp/Models/KeyboardShortcut.swift Crisp/Services/SettingsService.swift Crisp/Views/ToolsExpansionView.swift].map { |path| File.join(source, path) }
else
  abort "Unknown feature: #{feature}"
end
binary = File.join(app, 'Contents/MacOS/Fixture')
abort 'Fixture compile failed' unless system('xcrun', 'swiftc', *flags, *sources, '-o', binary)
if feature == 'keep-tools-expanded'
  abort 'Preference write failed' unless system(binary, '--write-preference')
  abort 'Preference reload failed' unless system(binary, '--read-preference')
end
%w[en zh-Hans zh-Hant].each do |language|
  abort 'UI rendering failed' unless system(binary, File.join(output, "#{language}.png"), '-AppleLanguages', "(#{language})")
end
