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
    @Published var displays = [DisplayInfo("builtin", name: "Built-in Display", builtin: true),
                               DisplayInfo("external", name: "External Display")]
    func refreshDisplays() {
        displays.removeAll { PhysicalDisplayToggleService.shared.isDisconnected(uuid: $0.displayUUID) }
    }
}

@MainActor
final class PhysicalDisplayToggleService: ObservableObject {
    static let shared = PhysicalDisplayToggleService()
    static let hasBattery = true
    let isSupported = true
    @Published var disconnected: [DisconnectedDisplay] = []
    struct DisconnectedDisplay: Identifiable {
        let uuid: String
        let name: String
        let width = 1920
        let height = 1080
        var id: String { uuid }
    }
    enum ToggleError: Error, Sendable {
        case timedOut
        var description: String { "Fixture failure" }
    }
    func isDisconnected(uuid: String) -> Bool { disconnected.contains { $0.uuid == uuid } }
    func wouldLeaveNoActiveDisplay(_ id: CGDirectDisplayID) -> Bool { !disconnected.isEmpty }
    func disconnect(_ display: DisplayInfo) async -> Result<Void, ToggleError> {
        disconnected.append(.init(uuid: display.displayUUID, name: display.name))
        return .success(())
    }
    func reconnect(uuid: String) async -> Result<Void, ToggleError> {
        disconnected.removeAll { $0.uuid == uuid }
        return .success(())
    }
    func reapplyParkedIfDocked() {}
    func clearParked() {}
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
        try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        print("Rendered native SwiftUI fixture: \(size)")
        window.orderOut(nil)
    }
}
