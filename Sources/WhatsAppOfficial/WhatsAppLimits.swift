import Foundation

// Values from Meta's official WhatsApp/stickers iOS sample (Limits.swift).
enum WhatsAppLimits {
    static let maximumStaticStickerBytes = 100 * 1024
    static let maximumTrayImageBytes = 50 * 1024
    static let stickerDimension = 512
    static let trayImageDimension = 96
    static let minimumStickersPerPack = 3
    static let maximumStickersPerPack = 30
    static let maximumMetadataCharacters = 128
}
