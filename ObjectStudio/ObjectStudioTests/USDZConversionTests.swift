import XCTest
import SceneKit
@testable import ObjectStudio

final class USDZConversionTests: XCTestCase {
    func testGLBLoadsAndExportsReadableUSDZ() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("triangle.glb")
        try Data(base64Encoded: "Z2xURgIAAACQAQAAUAEAAEpTT057ImFzc2V0Ijp7InZlcnNpb24iOiIyLjAifSwic2NlbmUiOjAsInNjZW5lcyI6W3sibm9kZXMiOlswXX1dLCJub2RlcyI6W3sibWVzaCI6MH1dLCJtZXNoZXMiOlt7InByaW1pdGl2ZXMiOlt7ImF0dHJpYnV0ZXMiOnsiUE9TSVRJT04iOjB9fV19XSwiYnVmZmVycyI6W3siYnl0ZUxlbmd0aCI6MzZ9XSwiYnVmZmVyVmlld3MiOlt7ImJ1ZmZlciI6MCwiYnl0ZU9mZnNldCI6MCwiYnl0ZUxlbmd0aCI6MzZ9XSwiYWNjZXNzb3JzIjpbeyJidWZmZXJWaWV3IjowLCJjb21wb25lbnRUeXBlIjo1MTI2LCJjb3VudCI6MywidHlwZSI6IlZFQzMiLCJtaW4iOlswLDAsMF0sIm1heCI6WzEsMSwwXX1dfSAkAAAAQklOAAAAAAAAAAAAAAAAAAAAgD8AAAAAAAAAAAAAAAAAAIA/AAAAAA==")!.write(to: source)
        let scene = try await USDZConverter.loadScene(source)
        XCTAssertFalse(scene.rootNode.childNodes.isEmpty)
        let result = try await USDZConverter.convertToUSDZ(source)
        XCTAssertEqual(result.pathExtension, "usdz")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.path))
        let reopened = try SCNScene(url: result, options: nil)
        XCTAssertFalse(reopened.rootNode.childNodes.isEmpty)
    }
}

