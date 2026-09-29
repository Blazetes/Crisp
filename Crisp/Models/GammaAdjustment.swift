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

    /// The step `fraction` (0...1) of the way to `target`, for a fade. Invert and
    /// pause cannot blend, so they take the target's value at the end.
    func interpolated(to target: GammaAdjustment, fraction: Double) -> GammaAdjustment {
        guard fraction < 1 else { return target }
        func mix(_ from: Double, _ to: Double) -> Double { from + (to - from) * fraction }
        var step = self
        step.contrast = mix(contrast, target.contrast)
        step.gammaVal = mix(gammaVal, target.gammaVal)
        step.gain = mix(gain, target.gain)
        step.colorTemperature = mix(colorTemperature, target.colorTemperature)
        step.rGamma = mix(rGamma, target.rGamma)
        step.gGamma = mix(gGamma, target.gGamma)
        step.bGamma = mix(bGamma, target.bGamma)
        step.rGain = mix(rGain, target.rGain)
        step.gGain = mix(gGain, target.gGain)
        step.bGain = mix(bGain, target.bGain)
        step.quantizationLevels = Int(mix(Double(quantizationLevels), Double(target.quantizationLevels)).rounded())
        return step
    }
}

/// crispctl's names for the adjustment (CrispControlImageSetting): clearer on the
/// command line than the field names, which the saved state already uses.
extension GammaAdjustment {
    func setting(_ setting: CrispControlImageSetting, to value: Double) -> GammaAdjustment {
        var adjustment = self
        switch setting {
        case .contrast: adjustment.contrast = value
        case .gamma: adjustment.gammaVal = value
        case .gain: adjustment.gain = value
        case .temperature: adjustment.colorTemperature = value
        case .redGamma: adjustment.rGamma = value
        case .greenGamma: adjustment.gGamma = value
        case .blueGamma: adjustment.bGamma = value
        case .redGain: adjustment.rGain = value
        case .greenGain: adjustment.gGain = value
        case .blueGain: adjustment.bGain = value
        case .quantization: adjustment.quantizationLevels = Int(value)
        case .invert: adjustment.isInverted = value == 1
        }
        return adjustment
    }

    func controlValues(displayID: UInt32, uuid: String, name: String) -> CrispControlImageAdjustment {
        CrispControlImageAdjustment(
            displayID: displayID, uuid: uuid, name: name, contrast: contrast, gamma: gammaVal, gain: gain,
            temperature: colorTemperature,
            redGamma: rGamma, greenGamma: gGamma, blueGamma: bGamma,
            redGain: rGain, greenGain: gGain, blueGain: bGain,
            quantization: quantizationLevels, invert: isInverted, paused: isPaused
        )
    }
}
