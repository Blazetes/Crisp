import Foundation

/// Per-display software image adjustment parameters. Slider values run -100...+100
/// with 0 = neutral, except quantizationLevels (2...256, 256 = no quantization).
/// See docs/brightness-notes.md (gamma and software brightness) for the slider math.
struct GammaAdjustment: Codable, Equatable {
    var contrast: Double = 0.0
    var gammaVal: Double = 0.0          // gamma exponent 1.0 at 0
    var gain: Double = 0.0              // multiplier 1.0 at 0
    var colorTemperature: Double = 0.0  // 6500 K at 0
    var rGamma: Double = 0.0            // per-channel gamma offset
    var gGamma: Double = 0.0
    var bGamma: Double = 0.0
    var rGain: Double = 0.0             // per-channel gain offset
    var gGain: Double = 0.0
    var bGain: Double = 0.0
    var quantizationLevels: Int = 256
    var isInverted: Bool = false
    var isPaused: Bool = false

    /// Every value at neutral (pause does not count): nothing to apply or save.
    var isNeutral: Bool {
        contrast == 0 && gammaVal == 0 && gain == 0 && colorTemperature == 0 &&
        rGamma == 0 && gGamma == 0 && bGamma == 0 &&
        rGain == 0 && gGain == 0 && bGain == 0 && !isInverted &&
        quantizationLevels == 256
    }
}
