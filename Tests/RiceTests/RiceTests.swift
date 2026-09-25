import XCTest
@testable import Rice

final class RiceTests: XCTestCase {
    func testPresetsValidateAndRoundTrip() throws {
        for theme in RicePresets.all {
            try RiceValidator.validate(theme)
            let bytes = try RicePack.builtIn(theme).archive()
            let imported = try RicePack.read(bytes)
            XCTAssertEqual(imported.manifest, theme)
        }
    }

    func testRejectsUnknownCapabilityAndScriptNode() throws {
        var theme = RicePresets.all[0]
        theme.requires = ["run-script"]
        XCTAssertThrowsError(try RiceValidator.validate(theme))
        theme.requires = []
        theme.components[0].root.children?[0].type = "script"
        XCTAssertThrowsError(try RiceValidator.validate(theme))
    }

    func testRejectsDuplicateJSONKey() throws {
        let data = Data(#"{"id":"one","id":"two"}"#.utf8)
        XCTAssertThrowsError(try StrictJSON.checkDuplicateKeys(data))
    }

    func testRejectsTruncatedArchiveAndInvalidPath() throws {
        XCTAssertThrowsError(try RicePack.read(Data([1, 2, 3])))
        XCTAssertFalse(RiceValidator.safePath("assets/../secret"))
        XCTAssertFalse(RiceValidator.safePath("/absolute"))
        XCTAssertFalse(RiceValidator.safePath("assets\\bad"))
    }

    func testAtomicStoreRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RiceStore(root: root)
        var state = try store.read()
        state.activeThemeID = "dusk"
        try store.write(state)
        XCTAssertEqual(try store.read().activeThemeID, "dusk")
    }

    func testImportedThemeCommitsAfterFiles() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RiceStore(root: root)
        var theme = RicePresets.all[0]
        theme.id = "imported-paper"
        let pack = RicePack.builtIn(theme)
        try store.install(pack.manifest, files: pack.files)
        XCTAssertTrue(try store.read().themes.contains(where: { $0.id == theme.id }))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.assetURL(themeID: theme.id, path: theme.license).path))
        XCTAssertThrowsError(try store.install(pack.manifest, files: pack.files))
    }

    func testExamplePacksImport() throws {
        for name in ["paper-sample", "dusk-sample", "geometry-sample"] {
            let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "ricepack"))
            let pack = try RicePack.read(Data(contentsOf: url))
            XCTAssertEqual(pack.manifest.id, name)
        }
    }

    func testMaliciousPackFixturesFailSafely() throws {
        for name in ["traversal", "duplicate-member", "duplicate-json-key", "script-node",
                     "unknown-capability", "compressed", "missing-license", "case-collision",
                     "deep-tree", "hash-mismatch", "missing-asset", "malformed-image",
                     "fake-length", "symlink"] {
            let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "ricepack"))
            XCTAssertThrowsError(try RicePack.read(Data(contentsOf: url)), name)
        }
        let valid = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "valid-image", withExtension: "ricepack"))
        let pack = try RicePack.read(Data(contentsOf: valid))
        XCTAssertEqual(pack.manifest.assets.count, 1)
        let images = RiceImages.load(component: pack.manifest.components[0], theme: pack.manifest) { pack.files[$0.path] }
        XCTAssertNotNil(images["pixel"])
    }

    func testProceduralArtworkExportsPNG() throws {
        for pattern in RicePattern.allCases where pattern != .photo {
            let image = RiceArtwork.render(theme: RicePresets.all[0], size: CGSize(width: 320, height: 640), icon: false, pattern: pattern)
            XCTAssertEqual(image.size.width, 320)
            XCTAssertEqual(image.cgImage?.width, 320)
            XCTAssertNotNil(image.pngData())
        }
    }

    func testContrastCalculation() {
        XCTAssertEqual(RiceContrast.ratio("#000000", "#FFFFFF") ?? 0, 21, accuracy: 0.001)
        XCTAssertEqual(RiceContrast.ratio("#123456", "#123456") ?? 0, 1, accuracy: 0.001)
    }
}
