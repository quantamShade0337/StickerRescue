// Adapted from WhatsApp/stickers iOS/WAStickersThirdParty/StickerPack.swift.
// It intentionally keeps the official `sendToWhatsApp` payload and URL flow.
// The upstream BSD license is included at Vendor/OfficialWhatsApp/LICENSE.

import Foundation
import ImageIO
import UniformTypeIdentifiers

enum StickerPackValidationError: LocalizedError {
    case emptyMetadata
    case metadataTooLong
    case invalidStickerCount(Int)
    case invalidTrayImage
    case invalidSticker(Int)

    var errorDescription: String? {
        switch self {
        case .emptyMetadata: "Pack identifier, name, and publisher must not be empty."
        case .metadataTooLong: "Pack metadata must be 128 characters or fewer."
        case .invalidStickerCount(let count): "The pack contains \(count) stickers; WhatsApp requires 3–30."
        case .invalidTrayImage: "The tray image is empty or larger than 50 KB."
        case .invalidSticker(let index): "Sticker \(index + 1) is empty or larger than 100 KB."
        }
    }
}

@MainActor
final class StickerPack {
    let identifier: String
    let name: String
    let publisher: String
    let trayImagePNGData: Data
    private var stickers: [Data] = []

    init(identifier: String, name: String, publisher: String, trayImagePNGData: Data) throws {
        guard !identifier.isEmpty, !name.isEmpty, !publisher.isEmpty else {
            throw StickerPackValidationError.emptyMetadata
        }
        guard identifier.count <= WhatsAppLimits.maximumMetadataCharacters,
              name.count <= WhatsAppLimits.maximumMetadataCharacters,
              publisher.count <= WhatsAppLimits.maximumMetadataCharacters else {
            throw StickerPackValidationError.metadataTooLong
        }
        guard Self.isValidImage(
            trayImagePNGData,
            type: .png,
            dimension: WhatsAppLimits.trayImageDimension,
            maximumBytes: WhatsAppLimits.maximumTrayImageBytes
        ) else {
            throw StickerPackValidationError.invalidTrayImage
        }
        self.identifier = identifier
        self.name = name
        self.publisher = publisher
        self.trayImagePNGData = trayImagePNGData
    }

    func addSticker(imageData: Data) throws {
        guard stickers.count < WhatsAppLimits.maximumStickersPerPack,
              Self.isValidImage(
                imageData,
                type: .webP,
                dimension: WhatsAppLimits.stickerDimension,
                maximumBytes: WhatsAppLimits.maximumStaticStickerBytes
              ) else {
            throw StickerPackValidationError.invalidSticker(stickers.count)
        }
        stickers.append(imageData)
    }

    func sendToWhatsApp(completionHandler: @escaping (Bool) -> Void) throws {
        completionHandler(Interoperability.send(json: try makePayload()))
    }

    func makePayload() throws -> [String: Any] {
        guard (WhatsAppLimits.minimumStickersPerPack...WhatsAppLimits.maximumStickersPerPack).contains(stickers.count) else {
            throw StickerPackValidationError.invalidStickerCount(stickers.count)
        }

        return [
            "identifier": identifier,
            "name": name,
            "publisher": publisher,
            "tray_image": trayImagePNGData.base64EncodedString(),
            "stickers": stickers.map {
                ["image_data": $0.base64EncodedString(), "emojis": [String]()] as [String: Any]
            },
        ]
    }

    private static func isValidImage(
        _ data: Data,
        type: UTType,
        dimension: Int,
        maximumBytes: Int
    ) -> Bool {
        guard !data.isEmpty,
              data.count <= maximumBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) == type.identifier as CFString,
              CGImageSourceGetCount(source) == 1,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return false
        }
        return image.width == dimension && image.height == dimension
    }
}
