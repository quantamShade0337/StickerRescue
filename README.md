# StickerRescue

StickerRescue is a personal, offline iOS utility that imports recovered WhatsApp `.webp` and `.png` sticker files from Files, normalizes them, and sends valid packs to WhatsApp.

## Requirements

- Xcode 16 or newer
- iOS 17 or newer
- A physical iPhone with WhatsApp installed
- An Apple ID added to Xcode for personal signing

## Run on an iPhone

1. Open `StickerRescue.xcodeproj`.
2. Select the **StickerRescue** target, open **Signing & Capabilities**, and choose your Personal Team.
3. If Xcode reports that the bundle identifier is unavailable, change `com.ethansoh.StickerRescue` to a unique value.
4. Connect and unlock the iPhone, select it as the run destination, and press **Run**.
5. If iOS asks you to trust the developer, follow the prompt in **Settings > General > VPN & Device Management** (the wording varies by iOS version).

## Import and export

1. Make the recovered `WhatsApp Stickers` folder available in the iPhone Files app (iCloud Drive, On My iPhone, or an attached drive).
2. In StickerRescue, tap **Select Sticker Folder** and select that folder itself.
3. Leave StickerRescue open while it validates, deduplicates, converts, and saves the collection.
4. Tap **Add to WhatsApp** on each generated pack, then confirm the save in WhatsApp before returning to StickerRescue for the next pack.

StickerRescue never modifies the selected originals. Processed copies and the import manifest are stored in the app's Application Support directory.

## WhatsApp implementation

The pack limits, JSON payload, local pasteboard type, and `whatsapp://stickerPack` handoff are adapted from Meta's official [`WhatsApp/stickers`](https://github.com/WhatsApp/stickers) iOS sample at commit `06144a1f6077bbb346e1230032fc4e0bce996d03`. Its BSD license is included in `Vendor/OfficialWhatsApp/LICENSE`.

WebP encoding uses a locally bundled libwebp 1.6.0 XCFramework built for physical iPhones and Apple-silicon simulators. The libwebp license and patent grant are included in `Vendor/libwebp-1.6.0`.
