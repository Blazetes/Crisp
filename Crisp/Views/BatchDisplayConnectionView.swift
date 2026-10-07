import SwiftUI

struct BatchDisplayConnectionView: View {
    @EnvironmentObject private var displayManager: DisplayManager
    @ObservedObject private var service = PhysicalDisplayToggleService.shared
    @ObservedObject private var batch = BatchDisplayConnectionService.shared

    private var state: ExternalDisplayConnectionState { batch.state(using: displayManager) }

    var body: some View {
        if service.isSupported, !state.entries.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    MenuItemIcon(systemName: "display.2", color: .blue, active: state.isOn)
                        .accessibilityHidden(true)
                    Text(state.hasProtectedDisplay ? "Other External Displays" : "External Displays").font(.body)
                    Spacer(minLength: 0)
                    if batch.isBusy {
                        ProgressView().controlSize(.small).frame(width: 18, height: 18)
                    } else if state.isOn && state.canReconnect {
                        Button { run(.reconnectAll) } label: {
                            Image(systemName: "arrow.clockwise").frame(width: 18, height: 18)
                        }
                        .buttonStyle(.plain)
                        .help("Connect All External Displays")
                        .accessibilityLabel(Text("Connect All External Displays"))
                    }
                    Toggle("External Displays", isOn: Binding(
                        get: { state.isOn },
                        set: { run($0 ? .reconnectAll : .disconnectAll) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(batch.isBusy || (!state.canDisconnect && !state.canReconnect))
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 6), count: state.columnCount),
                          alignment: .leading, spacing: 4) {
                    ForEach(state.entries) { entry in
                        if entry.isProtected {
                            displayName(entry)
                        } else {
                            Button { toggle(entry.id) } label: {
                                displayName(entry)
                            }
                            .buttonStyle(.plain)
                            .disabled(batch.isBusy || (!entry.isConnected && !entry.isAvailable))
                        }
                    }
                }
                .padding(.leading, 32)

                ForEach(batch.failures) { failure in
                    Text(verbatim: "\(failure.name): \(failure.error.description)")
                        .font(.caption)
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
        }
    }

    private func displayName(_ entry: ExternalDisplayConnectionState.Entry) -> some View {
        HStack(spacing: 2) {
            if entry.isProtected {
                Image(systemName: "lock.fill").font(.system(size: 8)).accessibilityHidden(true)
            }
            Text(verbatim: entry.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundStyle(entry.isConnected ? Color.primary : Color.secondaryReadable)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 20)
        .contentShape(Rectangle())
        .help(tooltip(for: entry))
        .accessibilityLabel(Text(verbatim: entry.name))
        .accessibilityValue(Text(status(for: entry)))
    }

    private func status(for entry: ExternalDisplayConnectionState.Entry) -> LocalizedStringKey {
        if entry.isProtected { return "Main Display Kept Connected" }
        if !entry.isAvailable { return "Display Unavailable" }
        return entry.isConnected ? "Connected" : "Disconnected"
    }

    private func tooltip(for entry: ExternalDisplayConnectionState.Entry) -> String {
        let detail: String
        if entry.isProtected {
            detail = String(localized: "Main Display Kept Connected")
        } else if !entry.isAvailable {
            detail = String(localized: "Display Unavailable")
        } else {
            detail = entry.isConnected ? String(localized: "Disconnect Display") : String(localized: "Reconnect Display")
        }
        return "\(entry.name): \(detail)"
    }

    private func run(_ action: DisplayConnectionPlan.Action) {
        guard PanelOpenGuard.allowsActivation, !batch.isBusy else { return }
        Task { @MainActor in _ = await batch.perform(action, using: displayManager) }
    }

    private func toggle(_ uuid: String) {
        guard PanelOpenGuard.allowsActivation, !batch.isBusy else { return }
        Task { @MainActor in await batch.toggle(uuid: uuid, using: displayManager) }
    }
}
