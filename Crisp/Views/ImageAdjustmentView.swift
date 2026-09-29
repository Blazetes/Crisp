import SwiftUI

/// Expandable "Image Adjustment" section, 11 sliders for software gamma/image adjustments.
/// Mirrors BetterDisplay's Image Adjustment panel.
struct ImageAdjustmentView: View {
    @ObservedObject var display: DisplayInfo
    /// Whether the parent section is expanded. The view stays instantiated when
    /// collapsed (a curtain, not an `if`), so the apply side effect keys off
    /// this instead of onAppear/onDisappear, which fire for every display.
    let isExpanded: Bool

    // MARK: - Local adjustment state (mirrors GammaAdjustment)
    @State private var contrast: Double           // -100 … +100
    @State private var gammaVal: Double           // -100 … +100
    @State private var gain: Double               // -100 … +100
    @State private var colorTemperature: Double   // -100 … +100
    @State private var quantLevels: Double        // 2 … 256 (256 = ∞)
    @State private var rGamma: Double
    @State private var gGamma: Double
    @State private var bGamma: Double
    @State private var rGain: Double
    @State private var gGain: Double
    @State private var bGain: Double
    @State private var isInverted: Bool
    @State private var isPaused: Bool

    // Seed @State from saved gamma state at init, not onAppear: mutating @State
    // there hitched the section's open animation mid-spring.
    init(display: DisplayInfo, isExpanded: Bool) {
        _display = ObservedObject(wrappedValue: display)
        self.isExpanded = isExpanded
        let saved = GammaService.shared.loadSavedState(for: display)
        _contrast = State(initialValue: saved?.contrast ?? 0)
        _gammaVal = State(initialValue: saved?.gammaVal ?? 0)
        _gain = State(initialValue: saved?.gain ?? 0)
        _colorTemperature = State(initialValue: saved?.colorTemperature ?? 0)
        _quantLevels = State(initialValue: saved.map { Double($0.quantizationLevels) } ?? 256)
        _rGamma = State(initialValue: saved?.rGamma ?? 0)
        _gGamma = State(initialValue: saved?.gGamma ?? 0)
        _bGamma = State(initialValue: saved?.bGamma ?? 0)
        _rGain = State(initialValue: saved?.rGain ?? 0)
        _gGain = State(initialValue: saved?.gGain ?? 0)
        _bGain = State(initialValue: saved?.bGain ?? 0)
        _isInverted = State(initialValue: saved?.isInverted ?? false)
        _isPaused = State(initialValue: saved?.isPaused ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // MARK: Global adjustments
            adjustRow(icon: "circle.righthalf.filled", label: "Contrast", value: $contrast)
            adjustRow(icon: "sparkle", label: "Gamma", value: $gammaVal)
            adjustRow(icon: "bolt.fill", label: "Gain", value: $gain)
            adjustRow(icon: "thermometer.medium", label: "Color Temp", value: $colorTemperature)
            quantizationRow

            Divider()
                .padding(.horizontal, 12)
                .padding(.vertical, 2)

            // MARK: Per-channel gamma
            adjustRow(icon: "r.circle", label: "Gamma R", value: $rGamma, accent: .red)
            adjustRow(icon: "g.circle", label: "Gamma G", value: $gGamma, accent: .green)
            adjustRow(icon: "b.circle", label: "Gamma B", value: $bGamma, accent: .blue)

            Divider()
                .padding(.horizontal, 12)
                .padding(.vertical, 2)

            // MARK: Per-channel gain
            adjustRow(icon: "r.circle.fill", label: "Gain R", value: $rGain, accent: .red)
            adjustRow(icon: "g.circle.fill", label: "Gain G", value: $gGain, accent: .green)
            adjustRow(icon: "b.circle.fill", label: "Gain B", value: $bGain, accent: .blue)

            Divider()
                .padding(.horizontal, 12)
                .padding(.vertical, 2)

            // MARK: HDR warning
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                    .font(.caption)
                Text("Adjustments may affect HDR content!")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)

            // MARK: Action buttons
            HStack(spacing: 8) {
                actionButton(
                    title: "Invert Colors",
                    systemImage: "circle.lefthalf.filled",
                    isActive: isInverted
                ) {
                    isInverted.toggle()
                    commitAdjustment()
                }

                actionButton(
                    title: isPaused ? "Resume Adjustments" : "Pause Adjustments",
                    systemImage: isPaused ? "play.circle" : "pause.circle",
                    isActive: isPaused
                ) {
                    isPaused.toggle()
                    commitAdjustment()
                }

                actionButton(
                    title: "Reset All",
                    systemImage: "arrow.counterclockwise",
                    isActive: false
                ) {
                    resetAll()
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .onChange(of: isExpanded) { _, expanded in
            // Re-apply so the display matches the UI; no-ops while paused.
            if expanded && !current.isNeutral { GammaService.shared.apply(current, for: display.displayID) }
        }
        // A preset or crispctl may change the adjustment while this view holds the old values.
        .onReceive(NotificationCenter.default.publisher(for: .crispGammaAdjustmentDidChange)) { note in
            guard note.object as? String == display.displayUUID else { return }
            show(GammaService.shared.loadSavedState(for: display) ?? GammaAdjustment())
        }
    }

    // MARK: - Slider row builder

    private func adjustRow(
        icon: String,
        label: LocalizedStringKey,
        value: Binding<Double>,
        accent: Color = .blue
    ) -> some View {
        AdjustRow(icon: icon, label: label, value: value, accent: accent, commitAction: commitAdjustment)
    }

    // MARK: - Quantization row

    private var quantizationRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.bar.fill")
                .foregroundColor(.blue)
                .frame(width: 18)
                .font(.caption)

            Text("Quantization")
                .font(.caption)
                .frame(width: 72, alignment: .leading)

            // Round in the binding, not via `step:`, which would draw tick marks.
            Slider(value: Binding(get: { quantLevels },
                                  set: { quantLevels = $0.rounded() }),
                   in: 2...256) { _ in
                commitAdjustment()
            }

            Text(quantLevels >= 255 ? "∞" : "\(Int(quantLevels))")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 38, alignment: .trailing)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }

    // MARK: - Action button builder

    private func actionButton(
        title: LocalizedStringKey,
        systemImage: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.caption)
                Text(title)
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isActive ? Color.blue.opacity(0.15) : Color.secondary.opacity(0.08))
            .foregroundColor(isActive ? .blue : .primary)
            .cornerRadius(5)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var current: GammaAdjustment {
        GammaAdjustment(
            contrast: contrast, gammaVal: gammaVal, gain: gain,
            colorTemperature: colorTemperature,
            rGamma: rGamma, gGamma: gGamma, bGamma: bGamma,
            rGain: rGain, gGain: gGain, bGain: bGain,
            quantizationLevels: Int(quantLevels),
            isInverted: isInverted, isPaused: isPaused
        )
    }

    private func show(_ adj: GammaAdjustment) {
        contrast = adj.contrast; gammaVal = adj.gammaVal; gain = adj.gain
        colorTemperature = adj.colorTemperature
        rGamma = adj.rGamma; gGamma = adj.gGamma; bGamma = adj.bGamma
        rGain = adj.rGain; gGain = adj.gGain; bGain = adj.bGain
        quantLevels = Double(adj.quantizationLevels)
        isInverted = adj.isInverted
        isPaused = adj.isPaused
    }

    private func commitAdjustment() {
        GammaService.shared.set(current, for: display)
    }

    @MainActor
    private func resetAll() {
        show(GammaAdjustment())
        commitAdjustment()
    }
}

private struct AdjustRow: View {
    let icon: String
    let label: LocalizedStringKey
    @Binding var value: Double
    let accent: Color
    let commitAction: () -> Void

    @State private var highlighted: Bool = false

    private func percentLabel(_ v: Double) -> String {
        let sign = v > 0 ? "+" : ""
        return "\(sign)\(Int(v))%"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(accent)
                .frame(width: 18)
                .font(.caption)

            Text(label)
                .font(.caption)
                .frame(width: 72, alignment: .leading)

            Slider(value: $value, in: -100...100) { editing in
                if !editing {
                    commitAction()
                    withAnimation(.easeOut(duration: 0.3)) { highlighted = true }
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        withAnimation(.easeOut(duration: 0.3)) { highlighted = false }
                    }
                }
            }
            .tint(accent)

            Text(percentLabel(value))
                .font(.caption)
                .foregroundColor(highlighted ? accent : .secondary)
                .frame(width: 38, alignment: .trailing)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }
}
