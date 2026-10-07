import SwiftUI
import CoreGraphics

struct BatchDisplayConnectionView: View {
    @EnvironmentObject private var displayManager: DisplayManager
    @ObservedObject private var service = PhysicalDisplayToggleService.shared
    @ObservedObject private var batch = BatchDisplayConnectionService.shared

    private var physicalDisplays: [DisplayInfo] {
        displayManager.displays.filter { !VirtualDisplayService.shared.isVirtualDisplay($0.displayID) }
    }

    private var canDisconnect: Bool {
        !DisplayConnectionPlan.make(
            action: .disconnectAll,
            connected: physicalDisplays.map {
                .init(uuid: $0.displayUUID, isBuiltin: $0.isBuiltin, isMain: $0.isMain,
                      isActive: CGDisplayIsActive($0.displayID) != 0)
            },
            disconnected: service.disconnected.map(\.uuid)
        ).disconnectUUIDs.isEmpty
    }

    var body: some View {
        if service.isSupported, Set(physicalDisplays.map(\.displayUUID) + service.disconnected.map(\.uuid)).count > 1 {
            VStack(alignment: .leading, spacing: 0) {
                Toggle(isOn: Binding(
                    get: { service.disconnected.isEmpty },
                    set: { run($0 ? .reconnectAll : .disconnectAll) }
                )) {
                    HStack(spacing: 8) {
                        MenuItemIcon(systemName: "display.2", color: .blue, active: service.disconnected.isEmpty)
                            .accessibilityHidden(true)
                        Text("All Displays Connected").font(.body)
                        Spacer()
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(batch.isBusy || (service.disconnected.isEmpty && !canDisconnect))
                .padding(.horizontal, 12)
                .padding(.vertical, 3)

                BatchConnectionActionRow(label: "Reconnect All Displays", icon: "arrow.clockwise",
                                         disabled: batch.isBusy || service.disconnected.isEmpty) { run(.reconnectAll) }
                BatchConnectionActionRow(label: "Disconnect All Displays", icon: "rectangle.slash",
                                         disabled: batch.isBusy || !canDisconnect) { run(.disconnectAll) }
                    .help("Keeps one physical display connected.")

                if batch.isBusy {
                    ProgressView().controlSize(.small).padding(.horizontal, 12)
                }
                ForEach(batch.failures) { failure in
                    Text(verbatim: "\(failure.name): \(failure.error.description)")
                        .font(.caption)
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 4)
                }
            }
        }
    }

    private func run(_ action: DisplayConnectionPlan.Action) {
        guard PanelOpenGuard.allowsActivation, !batch.isBusy else { return }
        Task { @MainActor in
            _ = await batch.perform(action, using: displayManager)
        }
    }
}

private struct BatchConnectionActionRow: View {
    let label: String
    let icon: String
    let disabled: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                MenuItemIcon(systemName: icon, active: false).accessibilityHidden(true)
                Text(LocalizedStringKey(label)).font(.body)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .menuRowHover(isHovered && !disabled)
        .onHover { isHovered = $0 }
    }
}
