import XCTest

/// The crispctl preset commands (#188): the reply scripts parse, and how a typed
/// selector finds one preset.
final class CrispControlPresetTests: XCTestCase {
    /// Scripts and Shortcuts parse this reply, so its field names are the contract.
    func testPresetListRepliesWithEveryPresetUnderStableKeys() throws {
        let preset = CrispControlPreset(
            id: "11111111-2222-3333-4444-555555555555", name: "Night",
            captures: ["brightness", "imageAdjustment"], displays: ["37D8832A-2D66-02CA-B9F7-8F30A301B230"], active: true
        )
        let list = CrispControlModel.handle(Data(#"{"command":"listPresets"}"#.utf8), displays: [], presets: [preset])
        XCTAssertEqual(list.response, .success(presets: [preset]))
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: CrispControlModel.encode(list.response)) as? [String: Any]
        )
        let listed = try XCTUnwrap((json["presets"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(listed.keys), ["id", "name", "captures", "displays", "active"])
        XCTAssertEqual(listed["captures"] as? [String], ["brightness", "imageAdjustment"])
    }

    func testPresetApplyResolvesByIDThenNameAndRefusesSharedOrUnknownNames() {
        func preset(_ id: String, _ name: String) -> CrispControlPreset {
            .init(id: id, name: name, captures: ["brightness"], displays: [], active: false)
        }
        let presets = [preset("AAAA", "Night"), preset("BBBB", "Work"), preset("CCCC", "work"), preset("Night", "Other")]
        func apply(_ selector: String) -> CrispControlResult {
            CrispControlModel.handle(
                Data(#"{"command":"applyPreset","selector":"\#(selector)"}"#.utf8), displays: [], presets: presets
            )
        }
        // An id wins over a name, even another preset's name; a name matches in any case.
        XCTAssertEqual(apply("aaaa").presetToApply, "AAAA")
        XCTAssertEqual(apply("Night").presetToApply, "Night")
        XCTAssertEqual(apply("other").presetToApply, "Night")
        // Two presets named alike: refused, and the ids to use instead are named.
        XCTAssertNil(apply("WORK").presetToApply)
        XCTAssertEqual(apply("WORK").response, .failure("2 presets are named 'WORK'; use an id: BBBB, CCCC"))
        XCTAssertEqual(apply("Day").response, .failure("no preset named 'Day'; presets: Night, Work, work, Other"))
        let none = CrispControlModel.handle(Data(#"{"command":"applyPreset","selector":"Day"}"#.utf8), displays: [])
        XCTAssertEqual(none.response, .failure("no preset named 'Day'; presets: none saved"))
        let missing = CrispControlModel.handle(Data(#"{"command":"applyPreset"}"#.utf8), displays: [])
        XCTAssertEqual(missing.response, .failure("preset is required"))
    }
}
