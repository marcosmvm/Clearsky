import XCTest

/// The product replaced the word "overdue" with "Needs a new plan" everywhere,
/// including code comments and doc strings. This test walks `Sources/` at test time
/// and fails if that retired word ever creeps back in.
final class NoRetiredWordTests: XCTestCase {

    func testSourcesDoNotContainTheRetiredWord() throws {
        let sourcesURL = try Self.sourcesDirectory()

        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: sourcesURL, includingPropertiesForKeys: nil) else {
            XCTFail("Could not enumerate Sources directory at \(sourcesURL.path)")
            return
        }

        var checkedFileCount = 0
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "swift" else { continue }
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            checkedFileCount += 1
            XCTAssertFalse(
                contents.lowercased().contains("overdue"),
                "\(fileURL.lastPathComponent) contains the retired word \"overdue\" — " +
                "the product word is \"Needs a new plan\"."
            )
        }

        XCTAssertGreaterThan(checkedFileCount, 0, "Expected to find Swift source files under \(sourcesURL.path)")
    }

    /// Resolves `Sources/` relative to this test file's own location, so the check
    /// works regardless of the working directory `swift test` is invoked from.
    private static func sourcesDirectory() throws -> URL {
        // This file lives at .../ClearskyCore/Tests/ClearskyCoreTests/NoRetiredWordTests.swift
        let thisFile = URL(fileURLWithPath: #filePath)
        let packageRoot = thisFile
            .deletingLastPathComponent() // NoRetiredWordTests.swift -> ClearskyCoreTests/
            .deletingLastPathComponent() // ClearskyCoreTests/ -> Tests/
            .deletingLastPathComponent() // Tests/ -> package root
        return packageRoot.appendingPathComponent("Sources", isDirectory: true)
    }
}
