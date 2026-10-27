import Foundation

actor LocalLibraryStore {
    private let fileManager: FileManager
    private let rootURL: URL
    private let manifestURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        self.fileManager = fileManager
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let resolvedRootURL = rootURL ?? applicationSupport.appending(path: "StickerRescue", directoryHint: .isDirectory)
        self.rootURL = resolvedRootURL
        self.manifestURL = resolvedRootURL.appending(path: "library.json", directoryHint: .notDirectory)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func prepareBatch(id: String) throws -> URL {
        do {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            let batchURL = rootURL.appending(path: id, directoryHint: .isDirectory)
            try fileManager.createDirectory(at: batchURL, withIntermediateDirectories: true)
            return batchURL
        } catch {
            throw StickerRescueError.cannotCreateStorage
        }
    }

    func save(_ library: StickerLibrary) throws {
        let data = try encoder.encode(library)
        try data.write(to: manifestURL, options: .atomic)
        removeOldBatches(keeping: library.batchID)
    }

    func load() throws -> StickerLibrary? {
        guard fileManager.fileExists(atPath: manifestURL.path) else { return nil }
        do {
            let library = try decoder.decode(StickerLibrary.self, from: Data(contentsOf: manifestURL))
            guard library.formatVersion == StickerLibrary.formatVersion else {
                throw StickerRescueError.corruptSavedLibrary
            }
            return library
        } catch let error as StickerRescueError {
            throw error
        } catch {
            throw StickerRescueError.corruptSavedLibrary
        }
    }

    func updateAddedState(packID: String, isAdded: Bool) throws -> StickerLibrary? {
        guard var library = try load(),
              let index = library.packs.firstIndex(where: { $0.id == packID }) else {
            return nil
        }
        library.packs[index].isAdded = isAdded
        try save(library)
        return library
    }

    func absoluteURL(batchID: String, relativePath: String) -> URL {
        rootURL
            .appending(path: batchID, directoryHint: .isDirectory)
            .appending(path: relativePath, directoryHint: .notDirectory)
    }

    private func removeOldBatches(keeping batchID: String) {
        guard let children = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for child in children where child.lastPathComponent != batchID && child != manifestURL {
            guard (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            try? fileManager.removeItem(at: child)
        }
    }
}
