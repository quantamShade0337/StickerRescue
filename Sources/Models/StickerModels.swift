import Foundation

struct StickerLibrary: Codable, Equatable, Sendable {
    static let formatVersion = 1

    let formatVersion: Int
    let batchID: String
    let sourceFolderName: String
    let importedAt: Date
    var packs: [RecoveredPack]
    let diagnostics: ImportDiagnostics
    let failures: [StickerFailure]

    init(batchID: String, sourceFolderName: String, importedAt: Date, packs: [RecoveredPack], diagnostics: ImportDiagnostics, failures: [StickerFailure]) {
        self.formatVersion = Self.formatVersion
        self.batchID = batchID
        self.sourceFolderName = sourceFolderName
        self.importedAt = importedAt
        self.packs = packs
        self.diagnostics = diagnostics
        self.failures = failures
    }
}

struct RecoveredPack: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let publisher: String
    let trayImagePath: String
    let stickerPaths: [String]
    var isAdded: Bool

    var stickerCount: Int { stickerPaths.count }
}

struct ImportDiagnostics: Codable, Equatable, Sendable {
    let filesDiscovered: Int
    let validStickers: Int
    let convertedStickers: Int
    let duplicatesRemoved: Int
    let failedStickers: Int
    let generatedPacks: Int
}

struct StickerFailure: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let filename: String
    let reason: String

    init(filename: String, reason: String) {
        self.id = UUID()
        self.filename = filename
        self.reason = reason
    }
}

struct ImportProgress: Equatable, Sendable {
    enum Stage: String, Equatable, Sendable {
        case discovering = "Finding stickers"
        case processing = "Processing stickers"
        case packing = "Creating packs"
        case saving = "Saving library"
    }

    let stage: Stage
    let completed: Int
    let total: Int
    let filename: String?

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(max(Double(completed) / Double(total), 0), 1)
    }
}

enum StickerRescueError: LocalizedError, Sendable {
    case cannotAccessFolder
    case noStickerFiles
    case tooFewValidStickers(Int)
    case cannotCreateStorage
    case corruptSavedLibrary
    case whatsappUnavailable
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .cannotAccessFolder:
            "StickerRescue could not access that folder. Select it again in Files."
        case .noStickerFiles:
            "No .webp or .png files were found in the selected folder."
        case .tooFewValidStickers(let count):
            "Only \(count) valid sticker\(count == 1 ? "" : "s") remained. WhatsApp needs at least 3 per pack."
        case .cannotCreateStorage:
            "StickerRescue could not create its local storage folder."
        case .corruptSavedLibrary:
            "The saved sticker library could not be read. Import the folder again."
        case .whatsappUnavailable:
            "WhatsApp is not installed or cannot be opened on this iPhone."
        case .exportFailed(let reason):
            "The sticker pack could not be prepared: \(reason)"
        }
    }
}

enum PackDistributor {
    static func sizes(for stickerCount: Int) -> [Int] {
        guard stickerCount >= WhatsAppLimits.minimumStickersPerPack else { return [] }

        let maximum = WhatsAppLimits.maximumStickersPerPack
        let fullPackCount = stickerCount / maximum
        let remainder = stickerCount % maximum

        if remainder == 0 {
            return Array(repeating: maximum, count: fullPackCount)
        }
        if remainder >= WhatsAppLimits.minimumStickersPerPack {
            return Array(repeating: maximum, count: fullPackCount) + [remainder]
        }

        guard fullPackCount > 0 else { return [] }
        var sizes = Array(repeating: maximum, count: fullPackCount)
        sizes[sizes.count - 1] -= WhatsAppLimits.minimumStickersPerPack - remainder
        sizes.append(WhatsAppLimits.minimumStickersPerPack)
        return sizes
    }
}
