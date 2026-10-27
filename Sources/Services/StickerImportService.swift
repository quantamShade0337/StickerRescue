import CryptoKit
import Foundation

actor StickerImportService {
    typealias ProgressHandler = @MainActor @Sendable (ImportProgress) -> Void

    private let fileManager: FileManager
    private let store: LocalLibraryStore
    private let processor: StickerImageProcessor

    init(fileManager: FileManager = .default, store: LocalLibraryStore, processor: StickerImageProcessor = StickerImageProcessor()) {
        self.fileManager = fileManager
        self.store = store
        self.processor = processor
    }

    func importFolder(_ folderURL: URL, progress: ProgressHandler) async throws -> StickerLibrary {
        let isUsingSecurityScope = folderURL.startAccessingSecurityScopedResource()
        defer {
            if isUsingSecurityScope { folderURL.stopAccessingSecurityScopedResource() }
        }

        await progress(ImportProgress(stage: .discovering, completed: 0, total: 0, filename: nil))
        let candidates = try discoverStickerFiles(in: folderURL)
        guard !candidates.isEmpty else { throw StickerRescueError.noStickerFiles }

        let batchID = UUID().uuidString.lowercased()
        let batchURL = try await store.prepareBatch(id: batchID)
        var knownHashes = Set<String>()
        var acceptedPaths: [String] = []
        var acceptedData: [Data] = []
        var failures: [StickerFailure] = []
        var duplicateCount = 0
        var convertedCount = 0

        for (index, fileURL) in candidates.enumerated() {
            try Task.checkCancellation()
            await progress(ImportProgress(
                stage: .processing,
                completed: index,
                total: candidates.count,
                filename: fileURL.lastPathComponent
            ))

            do {
                let sourceData = try coordinatedRead(from: fileURL)
                let hash = SHA256.hash(data: sourceData).map { String(format: "%02x", $0) }.joined()
                guard knownHashes.insert(hash).inserted else {
                    duplicateCount += 1
                    continue
                }

                let result = try processor.process(data: sourceData, sourceExtension: fileURL.pathExtension)
                if result.wasConverted { convertedCount += 1 }

                let relativePath = String(format: "sticker-%04d.webp", acceptedPaths.count + 1)
                try result.data.write(to: batchURL.appending(path: relativePath), options: .atomic)
                acceptedPaths.append(relativePath)
                acceptedData.append(result.data)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failures.append(StickerFailure(filename: fileURL.lastPathComponent, reason: error.localizedDescription))
            }
        }

        await progress(ImportProgress(stage: .processing, completed: candidates.count, total: candidates.count, filename: nil))
        guard acceptedPaths.count >= WhatsAppLimits.minimumStickersPerPack else {
            throw StickerRescueError.tooFewValidStickers(acceptedPaths.count)
        }

        await progress(ImportProgress(stage: .packing, completed: 0, total: acceptedPaths.count, filename: nil))
        let packs = try createPacks(batchID: batchID, batchURL: batchURL, stickerPaths: acceptedPaths, stickerData: acceptedData)
        let diagnostics = ImportDiagnostics(
            filesDiscovered: candidates.count,
            validStickers: acceptedPaths.count,
            convertedStickers: convertedCount,
            duplicatesRemoved: duplicateCount,
            failedStickers: failures.count,
            generatedPacks: packs.count
        )
        let library = StickerLibrary(
            batchID: batchID,
            sourceFolderName: folderURL.lastPathComponent,
            importedAt: Date(),
            packs: packs,
            diagnostics: diagnostics,
            failures: failures
        )

        await progress(ImportProgress(stage: .saving, completed: 0, total: 1, filename: nil))
        try await store.save(library)
        await progress(ImportProgress(stage: .saving, completed: 1, total: 1, filename: nil))
        return library
    }

    private func discoverStickerFiles(in folderURL: URL) throws -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .nameKey]
        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { throw StickerRescueError.cannotAccessFolder }

        var results: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            let values = try? url.resourceValues(forKeys: keys)
            guard values?.isRegularFile == true else { continue }
            let fileExtension = url.pathExtension.lowercased()
            if fileExtension == "webp" || fileExtension == "png" { results.append(url) }
        }
        return results.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    private func coordinatedRead(from url: URL) throws -> Data {
        var coordinatorError: NSError?
        var readResult: Result<Data, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinatorError) { coordinatedURL in
            readResult = Result { try Data(contentsOf: coordinatedURL, options: [.mappedIfSafe]) }
        }
        if let coordinatorError { throw coordinatorError }
        guard let readResult else { throw StickerImageProcessingError.unreadable }
        return try readResult.get()
    }

    private func createPacks(batchID: String, batchURL: URL, stickerPaths: [String], stickerData: [Data]) throws -> [RecoveredPack] {
        let sizes = PackDistributor.sizes(for: stickerPaths.count)
        var packs: [RecoveredPack] = []
        var startIndex = 0

        for (packIndex, size) in sizes.enumerated() {
            let endIndex = startIndex + size
            let packNumber = packIndex + 1
            let trayPath = String(format: "tray-%02d.png", packNumber)
            let trayData = try processor.makeTrayImage(from: stickerData[startIndex])
            try trayData.write(to: batchURL.appending(path: trayPath), options: .atomic)
            packs.append(RecoveredPack(
                id: "com.ethansoh.stickerrescue.\(batchID).\(packNumber)",
                name: String(format: "Recovered %02d", packNumber),
                publisher: "Ethan",
                trayImagePath: trayPath,
                stickerPaths: Array(stickerPaths[startIndex..<endIndex]),
                isAdded: false
            ))
            startIndex = endIndex
        }
        return packs
    }
}
