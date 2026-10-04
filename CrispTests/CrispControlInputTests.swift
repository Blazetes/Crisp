import XCTest

/// crispctl's input commands (#196): which display they reach, and which they refuse.
final class CrispControlInputTests: XCTestCase {
    private let display = CrispControlDisplay(
        id: 7, name: "Q27G3XMN", brightness: 56, isBuiltin: false,
        uuid: "37D8832A-2D66-02CA-B9F7-8F30A301B230", brightnessBackend: .ddc
    )
    private let held = CrispControlDisplay(
        id: 9, name: "M32UC", brightness: 0, isBuiltin: false,
        uuid: "DECC7CEF-5E36-4E9B-8F18-CE11AE5902AD", connected: false
    )

    func testInputCommandsResolveTheDisplayAndPassTheTypedInput() {
        let list = CrispControlModel.handle(Data(#"{"command":"listInputs","selector":"7"}"#.utf8), displays: [display])
        XCTAssertEqual(list.inputListDisplayID, display.id)
        let set = CrispControlModel.handle(
            Data(#"{"command":"setInput","selector":"37d8832a-2d66-02ca-b9f7-8f30a301b230","input":"0x11"}"#.utf8),
            displays: [display]
        )
        XCTAssertEqual(set.inputChange, .init(displayID: display.id, input: "0x11"))
    }

    /// Inputs go over the display's DDC channel: a held display has none until it is
    /// reconnected, and the built-in panel has none at all.
    func testInputCommandsRefuseDisplaysWithoutAChannel() {
        let builtin = CrispControlDisplay(id: 1, name: "Built-in", brightness: 50, isBuiltin: true, uuid: "B")
        let cases: [(String, String)] = [
            (#"{"command":"listInputs","selector":"9"}"#, "display is not connected; 'display connect' switches it back to this Mac"),
            (#"{"command":"setInput","selector":"1","input":"hdmi1"}"#, "the built-in display has no inputs"),
            (#"{"command":"setInput","selector":"7"}"#, "input is required"),
            (#"{"command":"listInputs"}"#, "display is required")
        ]
        for (request, error) in cases {
            let result = CrispControlModel.handle(Data(request.utf8), displays: [display, held, builtin])
            XCTAssertEqual(result.response.error, error, request)
            XCTAssertNil(result.inputChange, request)
            XCTAssertNil(result.inputListDisplayID, request)
        }
    }
}
