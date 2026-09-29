import AppIntents

// Crisp's actions in the Shortcuts app (#188). Each one sends the request crispctl
// would, through CrispControlServer.handle, so the checks, the errors and the
// serialisation of connection changes are crispctl's. Metadata: scripts/appintents.sh.

/// Sends one crispctl request in-process; a refusal becomes the action's error.
@MainActor
private func send(_ request: CrispControlRequest) async throws -> CrispControlResponse {
    guard let server = CrispControlServer.running else { throw ShortcutsActionError.notReady }
    let response = await server.handle(request)
    guard response.ok else { throw ShortcutsActionError.refused(response.error ?? "") }
    return response
}

enum ShortcutsActionError: Error, CustomLocalizedStringResourceConvertible {
    case notReady
    case refused(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notReady: "Crisp is still starting. Try again."
        case .refused(let reason): "Crisp refused: \(reason)"
        }
    }
}

// MARK: - Entities

/// A saved preset as the Shortcuts app lists it.
struct PresetEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Crisp Preset"
    static let defaultQuery = PresetQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct PresetQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [PresetEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [PresetEntity] {
        try await send(.init(command: .listPresets)).presets?.compactMap { preset in
            UUID(uuidString: preset.id).map { PresetEntity(id: $0, name: preset.name) }
        } ?? []
    }
}

/// A display as the Shortcuts app lists it, by uuid, which survives an unplug or a
/// wake. Displays Crisp holds disconnected are listed too, so Reconnect can name them.
struct DisplayEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Crisp Display"
    static let defaultQuery = DisplayQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct DisplayQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [DisplayEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [DisplayEntity] {
        try await send(.init(command: .list)).displays?.compactMap { display in
            display.uuid.map { DisplayEntity(id: $0, name: display.name) }
        } ?? []
    }
}

/// The Image Adjustment sliders, named as in the menu. Invert stays in crispctl: a
/// switch does not fit the action's number.
enum ImageSettingEntity: String, AppEnum {
    case contrast, gamma, gain, temperature
    case redGamma = "red-gamma", greenGamma = "green-gamma", blueGamma = "blue-gamma"
    case redGain = "red-gain", greenGain = "green-gain", blueGain = "blue-gain"
    case quantization

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Image Adjustment Setting"
    static let caseDisplayRepresentations: [ImageSettingEntity: DisplayRepresentation] = [
        .contrast: "Contrast",
        .gamma: "Gamma",
        .gain: "Gain",
        .temperature: "Color Temp",
        .redGamma: "Gamma R",
        .greenGamma: "Gamma G",
        .blueGamma: "Gamma B",
        .redGain: "Gain R",
        .greenGain: "Gain G",
        .blueGain: "Gain B",
        .quantization: "Quantization"
    ]
}

// MARK: - Actions

/// The action behind scheduled presets: a Time of Day automation runs it.
struct ApplyPresetIntent: AppIntent {
    static let title: LocalizedStringResource = "Apply Crisp Preset"
    static let description = IntentDescription("Applies a preset saved in Crisp, the same as clicking it in the menu.")

    @Parameter(title: "Preset")
    var preset: PresetEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Apply \(\.$preset)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        _ = try await send(.init(command: .applyPreset, selector: preset.id.uuidString))
        return .result()
    }
}

struct SetBrightnessIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Display Brightness"
    static let description = IntentDescription("Sets a display's brightness in percent. Above 100 needs Extra Brightness on.")

    @Parameter(title: "Display")
    var display: DisplayEntity

    @Parameter(title: "Brightness")
    var brightness: Double

    static var parameterSummary: some ParameterSummary {
        Summary("Set \(\.$display) to \(\.$brightness) %")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        _ = try await send(.init(command: .setBrightness, brightness: brightness, selector: display.id))
        return .result()
    }
}

struct GetBrightnessIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Display Brightness"
    static let description = IntentDescription("Returns a display's brightness in percent.")

    @Parameter(title: "Display")
    var display: DisplayEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Get the brightness of \(\.$display)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Double> {
        let response = try await send(.init(command: .getBrightness, selector: display.id))
        return .result(value: response.display?.brightness ?? 0)
    }
}

struct SetExtraBrightnessIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Extra Brightness"
    static let description = IntentDescription("Turns Extra Brightness on or off for a display that supports it.")

    @Parameter(title: "Display")
    var display: DisplayEntity

    @Parameter(title: "On")
    var enabled: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Set Extra Brightness of \(\.$display) to \(\.$enabled)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        _ = try await send(.init(command: .setBrightnessBoost, selector: display.id, enabled: enabled))
        return .result()
    }
}

struct SetHDRIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Display HDR"
    static let description = IntentDescription("Turns HDR on or off for an external display that supports it.")

    @Parameter(title: "Display")
    var display: DisplayEntity

    @Parameter(title: "On")
    var enabled: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Set HDR of \(\.$display) to \(\.$enabled)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        _ = try await send(.init(command: .setHDR, selector: display.id, enabled: enabled))
        return .result()
    }
}

struct DisconnectDisplayIntent: AppIntent {
    static let title: LocalizedStringResource = "Disconnect Display"
    static let description = IntentDescription("Takes a display out of the layout, the same as Disconnect Display in the menu.")

    @Parameter(title: "Display")
    var display: DisplayEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Disconnect \(\.$display)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        _ = try await send(.init(command: .disconnectDisplay, selector: display.id))
        return .result()
    }
}

struct ReconnectDisplayIntent: AppIntent {
    static let title: LocalizedStringResource = "Reconnect Display"
    static let description = IntentDescription("Puts a display that Crisp disconnected back in the layout.")

    @Parameter(title: "Display")
    var display: DisplayEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Reconnect \(\.$display)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        _ = try await send(.init(command: .connectDisplay, selector: display.id))
        return .result()
    }
}

struct SetImageAdjustmentIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Image Adjustment"
    // swiftlint:disable:next line_length
    static let description = IntentDescription("Sets one Image Adjustment slider, the same as moving it in the menu. Most run from -100 to 100 with 0 as neutral; Quantization runs from 2 to 256.")

    @Parameter(title: "Display")
    var display: DisplayEntity

    @Parameter(title: "Setting")
    var setting: ImageSettingEntity

    @Parameter(title: "Value")
    var value: Double

    static var parameterSummary: some ParameterSummary {
        Summary("Set \(\.$setting) of \(\.$display) to \(\.$value)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        _ = try await send(.init(
            command: .setImage, selector: display.id,
            setting: CrispControlImageSetting(rawValue: setting.rawValue), value: value
        ))
        return .result()
    }
}

struct ResetImageAdjustmentIntent: AppIntent {
    static let title: LocalizedStringResource = "Reset Image Adjustment"
    static let description = IntentDescription("Sets every Image Adjustment slider back to neutral, the same as Reset All in the menu.")

    @Parameter(title: "Display")
    var display: DisplayEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Reset Image Adjustment of \(\.$display)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        _ = try await send(.init(command: .resetImage, selector: display.id))
        return .result()
    }
}
