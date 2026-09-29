import XCTest

/// Headless tests for the preset Image Adjustment capture (#188). `DisplayPreset` and
/// `GammaAdjustment` compile directly into this test target.
final class DisplayPresetImageAdjustmentTests: XCTestCase {

    /// Presets saved before the capture existed must not start controlling Image Adjustment.
    func testLegacyPresetJSONDoesNotIncludeImageAdjustment() throws {
        let legacy = Data("""
        {"id":"11111111-2222-3333-4444-555555555555","name":"Work","icon":"display",
         "displays":[{"id":"99999999-8888-7777-6666-555555555555",
         "displayUUID":"ABC","brightness":0.65}]}
        """.utf8)
        let preset = try JSONDecoder().decode(DisplayPreset.self, from: legacy)
        XCTAssertFalse(preset.includesImageAdjustment)
        XCTAssertFalse(preset.includes(.imageAdjustment))
    }

    /// A captured neutral adjustment stays included, so applying it resets the display.
    func testNeutralImageAdjustmentRoundTripsAsIncluded() throws {
        let entry = DisplayPresetEntry(displayUUID: "ABC", imageAdjustment: GammaAdjustment())
        let preset = DisplayPreset(name: "Day", icon: "sun.max", displays: [entry])
        let data = try JSONEncoder().encode(preset)
        let decoded = try JSONDecoder().decode(DisplayPreset.self, from: data)
        XCTAssertTrue(decoded.includesImageAdjustment)
        XCTAssertEqual(decoded.displays.first?.imageAdjustment, GammaAdjustment())
    }

    /// A preset fades to its adjustment: values blend, invert waits for the last step.
    func testFadeStepsBlendValuesAndEndOnTheTarget() {
        let night = GammaAdjustment(contrast: -40, colorTemperature: 60, quantizationLevels: 16, isInverted: true)
        let half = GammaAdjustment().interpolated(to: night, fraction: 0.5)
        XCTAssertEqual(half.contrast, -20)
        XCTAssertEqual(half.colorTemperature, 30)
        XCTAssertEqual(half.quantizationLevels, 136)
        XCTAssertFalse(half.isInverted)
        XCTAssertEqual(GammaAdjustment().interpolated(to: night, fraction: 1), night)
    }
}
