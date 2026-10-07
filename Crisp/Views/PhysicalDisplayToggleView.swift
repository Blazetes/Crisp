import SwiftUI
import CoreGraphics

struct DisconnectDisplayRow: View {
    @ObservedObject var display: DisplayInfo
    @EnvironmentObject var displayManager: DisplayManager
    @ObservedObject private var service = PhysicalDisplayToggleService.shared
    @State private var isHovered = false
    @State private var busy = false
    @State private var errorMessage: String?

    var body: some View {
        if service.isSupported, !VirtualDisplayService.shared.isVirtualDisplay(display.displayID) {
            VStack(alignment: .leading, spacing: 0) {
                Toggle(isOn: Binding(
                    get: { !service.isDisconnected(uuid: display.displayUUID) },
                    set: { setConnected($0) }
                )) {
                    HStack(spacing: 8) {
                        MenuItemIcon(systemName: "display", color: .blue,
                                     active: !service.isDisconnected(uuid: display.displayUUID))
                            .accessibilityHidden(true)
                        Text("Display Connection").font(.body)
                        Spacer()
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(busy || service.wouldLeaveNoActiveDisplay(display.displayID))
                .help(service.wouldLeaveNoActiveDisplay(display.displayID)
                      ? String(localized: "Refusing to disconnect: it would leave no active display.")
                      : String(localized: "Display Connection"))
                .accessibilityLabel("Display Connection")
                .overlay(alignment: .trailing) {
                    if busy {
                        ProgressView().scaleEffect(0.6).frame(width: 16, height: 16)
                            .frame(width: 32, height: 20)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 3)
                .menuRowHover(isHovered)
                .onHover { isHovered = $0 }

                Text("Stays disconnected until you reconnect it here.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 4)
                }
            }
        }
    }

    private func setConnected(_ connected: Bool) {
        guard PanelOpenGuard.allowsActivation, !busy else { return }
        busy = true
        errorMessage = nil
        Task { @MainActor in
            let result: Result<Void, PhysicalDisplayToggleService.ToggleError>
            if connected {
                result = await InputSwitchService.shared.reconnect(uuid: display.displayUUID)
            } else {
                result = await service.disconnect(display)
            }
            displayManager.refreshDisplays()
            if case .failure(let error) = result { errorMessage = error.description }
            busy = false
        }
    }
}

/// Inline "Disconnected" section for the main display list: lists displays the
/// user disconnected and offers a Reconnect action for each.
struct ReconnectDisplaysSection: View {
    @EnvironmentObject var displayManager: DisplayManager
    @ObservedObject private var service = PhysicalDisplayToggleService.shared
    @State private var busyUUIDs: Set<String> = []
    @State private var errors: [String: String] = [:]

    var body: some View {
        if !service.disconnected.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Disconnected")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    .padding(.bottom, 2)

                ForEach(service.disconnected) { record in
                    DisconnectedDisplayRow(
                        record: record,
                        busy: busyUUIDs.contains(record.uuid),
                        onReconnect: { reconnect(record) }
                    )
                    if let error = errors[record.uuid] {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 12)
                    }
                }
            }
        }
    }

    private func reconnect(_ record: PhysicalDisplayToggleService.DisconnectedDisplay) {
        guard !busyUUIDs.contains(record.uuid) else { return }
        busyUUIDs.insert(record.uuid)
        errors[record.uuid] = nil
        Task { @MainActor in
            let result = await InputSwitchService.shared.reconnect(uuid: record.uuid)
            if case .failure(let error) = result { errors[record.uuid] = error.description }
            displayManager.refreshDisplays()
            busyUUIDs.remove(record.uuid)
        }
    }
}

private struct DisconnectedDisplayRow: View {
    let record: PhysicalDisplayToggleService.DisconnectedDisplay
    let busy: Bool
    let onReconnect: () -> Void
    @State private var isHovered = false

    var body: some View {
        Toggle(isOn: Binding(
            get: { false },
            set: { connected in
                guard connected, !busy, PanelOpenGuard.allowsActivation else { return }
                onReconnect()
            }
        )) {
            HStack(spacing: 8) {
                MenuItemIcon(systemName: "rectangle.slash", color: .secondary, active: false)
                VStack(alignment: .leading, spacing: 1) {
                    Text(record.name).font(.body).lineLimit(1)
                    Text(verbatim: "\(record.width)×\(record.height)")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
            .opacity(isHovered ? 1 : 0.6)

            Spacer()

        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .disabled(busy)
        .help("Reconnect this display")
        .overlay(alignment: .trailing) {
            if busy {
                ProgressView().scaleEffect(0.6).frame(width: 16, height: 16)
                    .frame(width: 32, height: 20)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .menuRowHover(isHovered)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .accessibilityLabel("\(record.name), disconnected")
        .accessibilityHint("Reconnect this display")
    }
}
