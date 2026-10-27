import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import StickerRescue

struct PackDistributionTests {
    @Test("Every pack is valid and all stickers are retained", arguments: [
        (3, [3]),
        (29, [29]),
        (30, [30]),
        (31, [28, 3]),
        (32, [29, 3]),
        (33, [30, 3]),
        (59, [30, 29]),
        (60, [30, 30]),
        (61, [30, 28, 3]),
        (62, [30, 29, 3]),
        (361, [30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 28, 3]),
    ])
    func validDistribution(stickerCount: Int, expected: [Int]) {
        let sizes = PackDistributor.sizes(for: stickerCount)

        #expect(sizes == expected)
        #expect(sizes.reduce(0, +) == stickerCount)
        #expect(sizes.allSatisfy { (3...30).contains($0) })
    }

    @Test("Counts below WhatsApp's minimum produce no pack", arguments: 0...2)
    func rejectsTooFew(stickerCount: Int) {
        #expect(PackDistributor.sizes(for: stickerCount).isEmpty)
    }
}

struct StickerImageProcessorTests {
    @Test("Official WhatsApp sample images normalize successfully", arguments: ["webp", "png"])
    func officialSample(extension fileExtension: String) throws {
        let data = try fixtureData(named: "OfficialSample", extension: fileExtension)

        let result = try StickerImageProcessor().process(data: data, sourceExtension: fileExtension)
        let properties = try imageProperties(result.data)

        #expect(result.data.count <= WhatsAppLimits.maximumStaticStickerBytes)
        #expect(properties.type == UTType.webP.identifier)
        #expect(properties.width == 512)
        #expect(properties.height == 512)
        #expect(properties.frameCount == 1)
    }

    @Test("A non-square transparent PNG becomes a compliant static WebP")
    func convertsTransparentPNG() throws {
        let processor = StickerImageProcessor()
        let source = try makeTransparentPNG(width: 320, height: 160)

        let result = try processor.process(data: source, sourceExtension: "png")
        let properties = try imageProperties(result.data)

        #expect(result.wasConverted)
        #expect(result.data.count <= WhatsAppLimits.maximumStaticStickerBytes)
        #expect(properties.type == UTType.webP.identifier)
        #expect(properties.width == 512)
        #expect(properties.height == 512)
        #expect(properties.frameCount == 1)
        #expect(try cornerAlpha(result.data) == 0)
    }

    @Test("A compliant WebP is preserved byte-for-byte")
    func preservesCompliantWebP() throws {
        let processor = StickerImageProcessor()
        let firstPass = try processor.process(
            data: makeTransparentPNG(width: 240, height: 300),
            sourceExtension: "png"
        )
        let secondPass = try processor.process(data: firstPass.data, sourceExtension: "webp")

        #expect(!secondPass.wasConverted)
        #expect(secondPass.data == firstPass.data)
    }

    @Test("Tray icons are valid 96-pixel PNG files")
    func createsTrayImage() throws {
        let processor = StickerImageProcessor()
        let sticker = try processor.process(
            data: makeTransparentPNG(width: 200, height: 100),
            sourceExtension: "png"
        )

        let tray = try processor.makeTrayImage(from: sticker.data)
        let properties = try imageProperties(tray)

        #expect(tray.count <= WhatsAppLimits.maximumTrayImageBytes)
        #expect(properties.type == UTType.png.identifier)
        #expect(properties.width == 96)
        #expect(properties.height == 96)
        #expect(properties.frameCount == 1)
    }

    @Test("Corrupt image data fails cleanly")
    func rejectsCorruptInput() {
        #expect(throws: StickerImageProcessingError.self) {
            try StickerImageProcessor().process(data: Data("not an image".utf8), sourceExtension: "webp")
        }
    }
}

struct LocalLibraryStoreTests {
    @Test("Manifest and Added status survive a disk round trip")
    func roundTrip() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "StickerRescueTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LocalLibraryStore(rootURL: root)
        let batchID = "test-batch"
        _ = try await store.prepareBatch(id: batchID)
        let pack = RecoveredPack(
            id: "test.pack.1",
            name: "Recovered 01",
            publisher: "Ethan",
            trayImagePath: "tray.png",
            stickerPaths: ["1.webp", "2.webp", "3.webp"],
            isAdded: false
        )
        let library = StickerLibrary(
            batchID: batchID,
            sourceFolderName: "WhatsApp Stickers",
            importedAt: Date(timeIntervalSince1970: 1_700_000_000),
            packs: [pack],
            diagnostics: ImportDiagnostics(
                filesDiscovered: 3,
                validStickers: 3,
                convertedStickers: 3,
                duplicatesRemoved: 0,
                failedStickers: 0,
                generatedPacks: 1
            ),
            failures: []
        )

        try await store.save(library)
        let loaded = try #require(try await store.load())
        #expect(loaded == library)

        let updated = try #require(try await store.updateAddedState(packID: pack.id, isAdded: true))
        #expect(updated.packs.first?.isAdded == true)
        #expect(try await store.load()?.packs.first?.isAdded == true)
    }
}

struct StickerImportServiceTests {
    @Test("Recursive import removes duplicates, reports failures, and keeps building packs")
    func endToEndImport() async throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: "StickerRescueImportTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let sourceFolder = temporaryRoot.appending(path: "WhatsApp Stickers", directoryHint: .isDirectory)
        let nestedFolder = sourceFolder.appending(path: "Nested", directoryHint: .isDirectory)
        let storageFolder = temporaryRoot.appending(path: "Storage", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: nestedFolder, withIntermediateDirectories: true)

        var firstStickerData: Data?
        for index in 0..<33 {
            let data = try makeTransparentPNG(width: 120 + index, height: 90 + index, seed: index)
            if index == 0 { firstStickerData = data }
            let destinationFolder = index.isMultiple(of: 2) ? sourceFolder : nestedFolder
            try data.write(to: destinationFolder.appending(path: String(format: "%03d.png", index)))
        }
        let duplicateData = try #require(firstStickerData)
        let duplicateURL = nestedFolder.appending(path: "duplicate.png")
        try duplicateData.write(to: duplicateURL)
        try Data("not an image".utf8).write(to: nestedFolder.appending(path: "broken.webp"))

        let store = LocalLibraryStore(rootURL: storageFolder)
        let service = StickerImportService(store: store)
        let library = try await service.importFolder(sourceFolder) { _ in }

        #expect(library.diagnostics.filesDiscovered == 35)
        #expect(library.diagnostics.validStickers == 33)
        #expect(library.diagnostics.convertedStickers == 33)
        #expect(library.diagnostics.duplicatesRemoved == 1)
        #expect(library.diagnostics.failedStickers == 1)
        #expect(library.diagnostics.generatedPacks == 2)
        #expect(library.packs.map(\.stickerCount) == [30, 3])
        #expect(library.failures.first?.filename == "broken.webp")
        #expect(try Data(contentsOf: duplicateURL) == duplicateData)

        for pack in library.packs {
            #expect((3...30).contains(pack.stickerCount))
            for relativePath in pack.stickerPaths {
                let url = await store.absoluteURL(batchID: library.batchID, relativePath: relativePath)
                let data = try Data(contentsOf: url)
                let properties = try imageProperties(data)
                #expect(properties.type == UTType.webP.identifier)
                #expect(properties.width == 512)
                #expect(properties.height == 512)
                #expect(data.count <= WhatsAppLimits.maximumStaticStickerBytes)
            }
        }
    }
}

@MainActor
struct StickerPackPayloadTests {
    @Test("Official payload contains a valid tray and three WebP stickers")
    func validPayload() throws {
        let processor = StickerImageProcessor()
        let sticker = try processor.process(
            data: makeTransparentPNG(width: 180, height: 220),
            sourceExtension: "png"
        ).data
        let tray = try processor.makeTrayImage(from: sticker)
        let pack = try StickerPack(
            identifier: "com.ethansoh.stickerrescue.test.1",
            name: "Recovered 01",
            publisher: "Ethan",
            trayImagePNGData: tray
        )
        for _ in 0..<3 { try pack.addSticker(imageData: sticker) }

        let payload = try pack.makePayload()
        let stickers = try #require(payload["stickers"] as? [[String: Any]])

        #expect(payload["name"] as? String == "Recovered 01")
        #expect(payload["publisher"] as? String == "Ethan")
        #expect(stickers.count == 3)
        #expect(JSONSerialization.isValidJSONObject(payload))
    }

    @Test("Export refuses a pack with fewer than three stickers")
    func rejectsUndersizedPack() throws {
        let processor = StickerImageProcessor()
        let sticker = try processor.process(
            data: makeTransparentPNG(width: 128, height: 128),
            sourceExtension: "png"
        ).data
        let pack = try StickerPack(
            identifier: "com.ethansoh.stickerrescue.test.2",
            name: "Recovered 02",
            publisher: "Ethan",
            trayImagePNGData: processor.makeTrayImage(from: sticker)
        )
        try pack.addSticker(imageData: sticker)
        try pack.addSticker(imageData: sticker)

        #expect(throws: StickerPackValidationError.self) {
            try pack.makePayload()
        }
    }
}

private struct TestImageProperties {
    let type: String?
    let width: Int
    let height: Int
    let frameCount: Int
}

private final class TestBundleToken: NSObject {}

private func fixtureData(named name: String, extension fileExtension: String) throws -> Data {
    let bundle = Bundle(for: TestBundleToken.self)
    let url = bundle.url(forResource: name, withExtension: fileExtension, subdirectory: "Fixtures")
        ?? bundle.url(forResource: name, withExtension: fileExtension)
    return try Data(contentsOf: #require(url))
}

private func imageProperties(_ data: Data) throws -> TestImageProperties {
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    return TestImageProperties(
        type: CGImageSourceGetType(source) as String?,
        width: image.width,
        height: image.height,
        frameCount: CGImageSourceGetCount(source)
    )
}

private func makeTransparentPNG(width: Int, height: Int, seed: Int = 0) throws -> Data {
    let bytesPerRow = width * 4
    var pixels = Data(count: bytesPerRow * height)
    let image = try pixels.withUnsafeMutableBytes { rawBuffer -> CGImage in
        let context = try #require(CGContext(
            data: rawBuffer.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        let hueComponent = CGFloat(seed % 20) / 20
        context.setFillColor(red: 0.1 + hueComponent * 0.7, green: 0.55, blue: 0.95 - hueComponent * 0.6, alpha: 0.9)
        context.fill(CGRect(x: width / 4, y: height / 4, width: width / 2, height: height / 2))
        return try #require(context.makeImage())
    }

    let output = try #require(CFDataCreateMutable(nil, 0))
    let destination = try #require(CGImageDestinationCreateWithData(
        output,
        UTType.png.identifier as CFString,
        1,
        nil
    ))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return output as Data
}

private func cornerAlpha(_ data: Data) throws -> UInt8 {
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    var pixel = [UInt8](repeating: 0, count: 4)
    let context = try #require(CGContext(
        data: &pixel,
        width: 1,
        height: 1,
        bitsPerComponent: 8,
        bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.draw(
        image,
        in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
    )
    return pixel[3]
}
