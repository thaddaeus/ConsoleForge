import XCTest
@testable import ConsoleForge

/// Opening a screenshot in the Documents viewer.
///
/// The acceptance criteria ARE these test names. The reported symptom was that sessions
/// open screenshots and "they just fail as not being text": `DocumentLoad.read` finds a
/// NUL byte in the first block, returns `.binary`, and the viewer renders a dead-end
/// notice. The first test below fails on that code — it reports `.binary` for a real PNG.
///
/// The two control tests exist because the obvious fix over-reaches. Detecting images by
/// asking ImageIO about every file reclassifies an SVG as a picture, when SVG is source a
/// developer opened the viewer to READ; and it must not swallow the honest binary notice
/// for files that are genuinely not viewable.
final class DocumentImageTests: XCTestCase {

    private func read(_ name: String) -> DocumentLoad {
        DocumentLoad.read(Fixture.url("documents/\(name)").path)
    }

    func testAScreenshotLoadsAsAnImageRatherThanBinary() {
        guard case .image = read("screenshot.png") else {
            return XCTFail("expected .image, got \(read("screenshot.png"))")
        }
    }

    func testThePixelDimensionsComeFromTheFileHeader() {
        guard case .image(let image) = read("screenshot.png") else {
            return XCTFail("expected .image, got \(read("screenshot.png"))")
        }
        // 7 x 3, deliberately non-square: a width/height transposition fails this.
        XCTAssertEqual(image.pixelWidth, 7)
        XCTAssertEqual(image.pixelHeight, 3)
    }

    func testTheImageDataIsCarriedWholeSoItCanBeDecoded() {
        guard case .image(let image) = read("screenshot.png") else {
            return XCTFail("expected .image, got \(read("screenshot.png"))")
        }
        // Truncating an image is corrupting it — unlike text, there is no useful prefix.
        let onDisk = try? Data(contentsOf: Fixture.url("documents/screenshot.png"))
        XCTAssertEqual(image.data.count, onDisk?.count)
        XCTAssertEqual(image.byteCount, onDisk?.count)
    }

    func testAnSVGStaysTextRatherThanBecomingAPicture() {
        // ImageIO decodes SVG. A viewer that renders it loses the source you opened it for.
        guard case .text(let text, _, _) = read("diagram.svg") else {
            return XCTFail("expected .text, got \(read("diagram.svg"))")
        }
        XCTAssertTrue(text.contains("<svg"))
    }

    func testBinaryThatIsNotAnImageStillReportsBinary() {
        guard case .binary(let bytes) = read("opaque.bin") else {
            return XCTFail("expected .binary, got \(read("opaque.bin"))")
        }
        XCTAssertEqual(bytes, 2048)
    }
}
