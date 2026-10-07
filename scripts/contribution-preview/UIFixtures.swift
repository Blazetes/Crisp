import SwiftUI
import AppKit
import CoreGraphics
import Combine

@MainActor
final class DisplayInfo: ObservableObject {
    let displayID = CGMainDisplayID()
    let displayUUID: String
    let name: String
    let isBuiltin: Bool
    let isMain: Bool
    init(_ uuid: String, name: String, builtin: Bool = false) {
        displayUUID = uuid
        self.name = name
        isBuiltin = builtin
        isMain = builtin
    }
}

@MainActor
final class DisplayManager: ObservableObject {
    var availableDisplays = [DisplayInfo("builtin", name: "Built-in Display", builtin: true),
                             DisplayInfo("external", name: "External Display")]
    @Published var displays: [DisplayInfo] = []
    init() { refreshDisplays() }
    func refreshDisplays() {
        displays = availableDisplays.filter { !PhysicalDisplayToggleService.shared.isDisconnected(uuid: $0.displayUUID) }
    }
}

@MainActor
final class PhysicalDisplayToggleService: ObservableObject {
    static let shared = PhysicalDisplayToggleService()
    static let hasBattery = true
    let isSupported = true
    @Published var disconnected: [DisconnectedDisplay] = []
    @Published var configurationInProgress = false
    var unavailable: Set<String> = []
    var disconnectedUUIDs: [String] = []
    var restoredUUIDs: [String] = []
    var heldBuiltin = false
    var failUUID: String?
    struct DisconnectedDisplay: Identifiable {
        let uuid: String
        let name: String
        let width = 1920
        let height = 1080
        var isBuiltin: Bool? = false
        var id: String { uuid }
    }
    enum ToggleError: Error, Sendable {
        case timedOut
        case configurationInProgress
        var description: String { "Fixture failure" }
    }
    func isDisconnected(uuid: String) -> Bool { disconnected.contains { $0.uuid == uuid } }
    func wouldLeaveNoActiveDisplay(_ id: CGDirectDisplayID) -> Bool { !disconnected.isEmpty }
    func disconnect(_ display: DisplayInfo) async -> Result<Void, ToggleError> {
        disconnectedUUIDs.append(display.displayUUID)
        if display.displayUUID == failUUID { return .failure(.timedOut) }
        disconnected.append(.init(uuid: display.displayUUID, name: display.name, isBuiltin: display.isBuiltin))
        return .success(())
    }
    func reconnect(uuid: String) async -> Result<Void, ToggleError> {
        restoredUUIDs.append(uuid)
        if uuid == failUUID { return .failure(.timedOut) }
        disconnected.removeAll { $0.uuid == uuid }
        return .success(())
    }
    func reapplyParkedIfDocked() {}
    func clearParked() {}
    func isBuiltinDisconnectedDisplay(_ record: DisconnectedDisplay) -> Bool { record.isBuiltin == true }
    func isAvailableForReconnect(_ record: DisconnectedDisplay) -> Bool { !unavailable.contains(record.uuid) }
    func holdBuiltinForExternalDisconnect() { heldBuiltin = true }
}

@MainActor
final class InputSwitchService {
    static let shared = InputSwitchService()
    func reconnect(uuid: String) async -> Result<Void, PhysicalDisplayToggleService.ToggleError> {
        await PhysicalDisplayToggleService.shared.reconnect(uuid: uuid)
    }
}

@MainActor
final class VirtualDisplayService {
    static let shared = VirtualDisplayService()
    func isVirtualDisplay(_ id: CGDirectDisplayID) -> Bool { false }
}

@MainActor
enum PanelOpenGuard {
    static let allowsActivation = true
}

extension Animation {
    static let panelResize = Animation.smooth(duration: 0.16)
}

extension Color {
    static let secondaryReadable = Color.secondary
}

extension Notification.Name {
    static let crispPanelDidOpen = Notification.Name("fixture.open")
}

#if !FEATURE_TOOLS
@MainActor
final class SettingsService: ObservableObject {
    static let shared = SettingsService()
    @Published var disconnectBuiltinWhenDocked = false
}
#else
@MainActor
final class LaunchService {
    static let shared = LaunchService()
    let isEnabled = false
}
@MainActor
final class EdgeCrossingService {
    static let shared = EdgeCrossingService()
    func setEnabled(_ enabled: Bool) {}
}
@MainActor
final class HotkeyService {
    static let shared = HotkeyService()
    func syncRegistrations() {}
}
@MainActor
final class PresetService {
    static let shared = PresetService()
    func stealShortcutFromPresets(_ shortcut: KeyboardShortcut) {}
}
@MainActor
final class KeepAwakeService: ObservableObject {
    static let shared = KeepAwakeService()
    @Published var isActive = false
    func setActive(_ active: Bool) { isActive = active }
}
#endif

struct FixtureContent: View {
    @EnvironmentObject var manager: DisplayManager
    #if FEATURE_TOOLS
    @StateObject private var state = PanelSectionState()
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            #if FEATURE_SWITCH
            Text("External Display").font(.headline).padding(12)
            DisconnectDisplayRow(display: manager.displays[1])
            Divider().padding(.horizontal, 12)
            ReconnectDisplaysSection()
            #elseif FEATURE_BATCH
            Text("Tools").font(.headline).padding(12)
            DisconnectBuiltinRow()
            BatchDisplayConnectionView()
            ExpandableRow(icon: "display.2", iconActive: false, label: "Virtual Displays", isExpanded: .constant(false))
            #elseif FEATURE_TOOLS
            Text("Settings").font(.headline).padding(12)
            KeepToolsExpandedRow()
            Divider().padding(.horizontal, 12).padding(.vertical, 4)
            ToolsHeaderRow(state: state)
            if state.showTools { KeepAwakeRow().padding(.leading, 8) }
            #endif
        }
        .padding(.vertical, 8)
        .frame(width: 308)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

@main
struct UIFixtures {
    @MainActor
    static func main() async throws {
        #if FEATURE_TOOLS
        if CommandLine.arguments.contains("--write-preference") {
            SettingsService.shared.keepToolsExpanded = true
            precondition(UserDefaults.standard.bool(forKey: "crisp.keepToolsExpanded"))
            UserDefaults.standard.synchronize()
            print("Saved preference verified")
            return
        }
        if CommandLine.arguments.contains("--read-preference") {
            precondition(SettingsService.shared.keepToolsExpanded)
            let state = PanelSectionState()
            precondition(state.showTools)
            state.showSettings = true
            state.showVirtualDisplays = true
            state.collapseAll()
            precondition(state.showTools && !state.showSettings && !state.showVirtualDisplays)
            SettingsService.shared.keepToolsExpanded = false
            state.collapseAll()
            precondition(!state.showTools)
            UserDefaults.standard.synchronize()
            print("Relaunch and close/reopen state verified")
            return
        }
        SettingsService.shared.keepToolsExpanded = true
        #endif

        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let manager = DisplayManager()
        #if FEATURE_BATCH
        if CommandLine.arguments.contains("--check-app-assets") {
            guard let bundle = Bundle(path: CommandLine.arguments[2]),
                  let image = bundle.image(forResource: "ExternalDisplayConnection") else {
                fatalError("SVG menu image missing from packaged app")
            }
            try verifyIcon(image, output: CommandLine.arguments[3])
            print("Packaged app SVG image resolves from its own asset catalog")
            return
        }
        guard let menuIcon = NSImage(named: "ExternalDisplayConnection") else { fatalError("SVG menu asset is missing") }
        if CommandLine.arguments.contains("--check-batch") {
            try verifyIcon(menuIcon, output: CommandLine.arguments[2])
            await verifyBatch(using: manager)
            return
        }
        let count = Int(CommandLine.arguments[2]) ?? 4
        let variant = CommandLine.arguments[3]
        let names = ["Mi Monitor", "DELL U2723QE", "LG HDR", "Studio Display", "BenQ PD", "ASUS ProArt", "Samsung", "EIZO"]
        manager.availableDisplays = (0..<count).map {
            DisplayInfo("external-\($0)", name: variant == "duplicates" ? "DELL U2723QE" : names[$0 % names.count])
        }
        if variant != "desktop" { manager.availableDisplays.insert(DisplayInfo("builtin", name: "Built-in", builtin: true), at: 0) }
        if variant == "mixed" || variant == "off" || variant == "unavailable" {
            PhysicalDisplayToggleService.shared.disconnected = manager.availableDisplays.filter {
                !$0.isBuiltin && (variant == "off" || $0.displayUUID == "external-1")
            }.map { .init(uuid: $0.displayUUID, name: $0.name) }
            if variant == "unavailable" { PhysicalDisplayToggleService.shared.unavailable = ["external-1"] }
        }
        manager.refreshDisplays()
        #endif
        #if FEATURE_SWITCH
        PhysicalDisplayToggleService.shared.disconnected = [.init(uuid: "held", name: "Held External Display")]
        #endif
        let content = FixtureContent().environmentObject(manager)
        let hosting = NSHostingView(rootView: content)
        let size = hosting.fittingSize
        precondition(size.width == 308 && size.height > 50)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        window.orderFront(nil)
        try await Task.sleep(nanoseconds: 500_000_000)
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            fatalError("Unable to allocate preview bitmap")
        }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            fatalError("Unable to encode preview bitmap")
        }
        precondition(png.count > 1000, "Blank native fixture")
        try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        print("Rendered native SwiftUI fixture: \(size)")
        window.orderOut(nil)
    }

    #if FEATURE_BATCH
    @MainActor
    private static func verifyIcon(_ image: NSImage, output: String) throws {
        precondition(image.size == NSSize(width: 24, height: 24))
        for size in [16, 20, 24, 32] {
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: bitmap)
            else { fatalError("Icon bitmap allocation failed") }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            context.cgContext.clear(CGRect(x: 0, y: 0, width: size, height: size))
            image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
            NSGraphicsContext.restoreGraphicsState()
            var visible = 0
            for y in 0..<size {
                for x in 0..<size {
                    let alpha = bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
                    if alpha > 0.001 { visible += 1 }
                    if x == 0 || y == 0 || x == size - 1 || y == size - 1 {
                        precondition(alpha < 0.001, "SVG icon clips or has a background")
                    }
                }
            }
            precondition(visible > size && visible < size * size / 2, "Blank or filled SVG icon")
            guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Icon PNG failed") }
            try png.write(to: URL(fileURLWithPath: output).appendingPathComponent("native-icon-\(size).png"))
        }
        print("Compiled SVG image resolves and renders at 16/20/24/32 with transparent borders")
    }

    @MainActor
    private static func verifyBatch(using manager: DisplayManager) async {
        let physical = PhysicalDisplayToggleService.shared
        let batch = BatchDisplayConnectionService.shared
        let builtin = DisplayInfo("builtin", name: "Built-in", builtin: true)
        let externals = (0..<4).map { DisplayInfo("external-\($0)", name: "Monitor \($0)") }
        manager.availableDisplays = [builtin] + externals
        manager.refreshDisplays()
        precondition(batch.connectedDisplays(using: manager).allSatisfy(\.isActive), "Fixture host needs a display")
        _ = await batch.perform(.disconnectAll, using: manager)
        precondition(physical.disconnectedUUIDs == externals.map(\.displayUUID))
        precondition(manager.displays.map(\.displayUUID) == ["builtin"] && !batch.isBusy && batch.failures.isEmpty)
        precondition(!batch.state(using: manager).isOn)
        _ = await batch.perform(.reconnectAll, using: manager)
        precondition(manager.displays.count == 5 && batch.state(using: manager).isOn)
        await batch.toggle(uuid: "external-1", using: manager)
        precondition(batch.state(using: manager).canReconnect && batch.state(using: manager).isOn)
        _ = await batch.perform(.reconnectAll, using: manager)
        precondition(!batch.state(using: manager).canReconnect)
        physical.disconnected = [.init(uuid: "builtin", name: "Built-in", isBuiltin: true)]
        physical.restoredUUIDs = []
        manager.refreshDisplays()
        _ = await batch.perform(.disconnectAll, using: manager)
        precondition(physical.restoredUUIDs.first == "builtin" && physical.heldBuiltin)
        precondition(!physical.disconnectedUUIDs.contains("builtin"))
        precondition(manager.displays.map(\.displayUUID) == ["builtin"])
        _ = await batch.perform(.reconnectAll, using: manager)
        physical.disconnected = [.init(uuid: "builtin", name: "Built-in", isBuiltin: true)]
        physical.restoredUUIDs = []
        manager.refreshDisplays()
        _ = await batch.perform(.reconnectAll, using: manager)
        precondition(physical.restoredUUIDs.isEmpty, "Connect externals must not reconnect the built-in")
        physical.disconnected = []
        manager.refreshDisplays()
        physical.failUUID = "external-0"
        physical.disconnectedUUIDs = []
        _ = await batch.perform(.disconnectAll, using: manager)
        precondition(batch.failures.count == 1 && !batch.isBusy && physical.disconnectedUUIDs.count == 1)
        precondition(manager.displays.count == 5, "Failure must not show false disconnected state")
        batch.clearSettledTimeouts(using: manager)
        precondition(batch.failures.count == 1, "Unresolved timeout must remain visible")
        physical.failUUID = nil
        physical.disconnected = [.init(uuid: "external-0", name: "Monitor 0")]
        manager.refreshDisplays()
        batch.clearSettledTimeouts(using: manager)
        precondition(batch.failures.isEmpty, "Late success must clear a settled timeout")
        _ = await batch.perform(.reconnectAll, using: manager)
        manager.availableDisplays = externals
        manager.refreshDisplays()
        _ = await batch.perform(.disconnectAll, using: manager)
        precondition(manager.displays.count == 1 && batch.state(using: manager).hasProtectedDisplay)
        precondition(!batch.state(using: manager).isOn, "Protected desktop keeper must not keep the switch on")
        print("Batch service checks passed: external-only, mixed restore, built-in safety, desktop keeper, timeout state")
    }
    #endif
}
