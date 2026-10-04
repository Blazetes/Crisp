import XCTest

/// Headless tests for the preset HDR capture (#198).
final class DisplayPresetHDRTests: XCTestCase {

    /// Presets saved before the capture existed must not start switching HDR.
    func testLegacyPresetJSONDoesNotIncludeHDR() throws {
        let legacy = Data("""
        {"id":"11111111-2222-3333-4444-555555555555","name":"Work","icon":"display",
         "displays":[{"id":"99999999-8888-7777-6666-555555555555",
         "displayUUID":"ABC","brightness":0.65}]}
        """.utf8)
        let preset = try JSONDecoder().decode(DisplayPreset.self, from: legacy)
        XCTAssertFalse(preset.includes(.hdr))
    }

    /// HDR off is a stored value, so applying the preset turns HDR off.
    func testHDROffRoundTripsAsIncluded() throws {
        let entries = [DisplayPresetEntry(displayUUID: "ABC", hdr: false),
                       DisplayPresetEntry(displayUUID: "DEF")]
        let preset = DisplayPreset(name: "Day", icon: "sun.max", displays: entries)
        let decoded = try JSONDecoder().decode(DisplayPreset.self, from: JSONEncoder().encode(preset))
        XCTAssertTrue(decoded.includes(.hdr))
        XCTAssertEqual(decoded.displays.map(\.hdr), [false, nil])
    }
}
