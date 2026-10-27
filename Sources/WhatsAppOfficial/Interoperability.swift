// Adapted from WhatsApp/stickers iOS/WAStickersThirdParty/Interoperability.swift.
// The upstream BSD license is included at Vendor/OfficialWhatsApp/LICENSE.

import UIKit

@MainActor
enum Interoperability {
    private static let officialSampleBundleIdentifier = "WA.WAStickersThirdParty"
    private static let pasteboardExpirationSeconds: TimeInterval = 60
    private static let pasteboardStickerPackDataType = "net.whatsapp.third-party.sticker-pack"
    private static let whatsAppURL = URL(string: "whatsapp://stickerPack")
    private static let whatsAppProbeURL = URL(string: "whatsapp://")

    static func canSend() -> Bool {
        guard let whatsAppProbeURL else { return false }
        return UIApplication.shared.canOpenURL(whatsAppProbeURL)
    }

    static func send(json: [String: Any]) -> Bool {
        guard Bundle.main.bundleIdentifier?.contains(officialSampleBundleIdentifier) != true,
              let whatsAppURL,
              JSONSerialization.isValidJSONObject(json),
              let dataToSend = try? JSONSerialization.data(withJSONObject: json) else { return false }

        UIPasteboard.general.setItems(
            [[pasteboardStickerPackDataType: dataToSend]],
            options: [
                .localOnly: true,
                .expirationDate: Date(timeIntervalSinceNow: pasteboardExpirationSeconds),
            ]
        )
        UIApplication.shared.open(whatsAppURL)
        return true
    }
}
