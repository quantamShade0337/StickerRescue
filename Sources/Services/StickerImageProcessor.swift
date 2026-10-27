import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ProcessedSticker: Sendable {
    let data: Data
    let wasConverted: Bool
}

enum StickerImageProcessingError: LocalizedError, Sendable {
    case unreadable
    case cannotDecode
    case invalidDimensions
    case cannotRender
    case cannotEncode
    case cannotMeetFileSize(Int)

    var errorDescription: String? {
        switch self {
        case .unreadable: "The file could not be read."
        case .cannotDecode: "The image format is corrupt or unsupported."
        case .invalidDimensions: "The image has invalid dimensions."
        case .cannotRender: "The image could not be rendered with transparency."
        case .cannotEncode: "The image could not be converted to WebP."
        case .cannotMeetFileSize(let bytes):
            "The converted image is \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)); the limit is 100 KB."
        }
    }
}

struct StickerImageProcessor {
    private static let canvasSize = WhatsAppLimits.stickerDimension
    private static let bytesPerPixel = 4

    func process(data: Data, sourceExtension: String) throws -> ProcessedSticker {
        guard !data.isEmpty else { throw StickerImageProcessingError.unreadable }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw StickerImageProcessingError.cannotDecode
        }
        guard image.width > 0, image.height > 0 else {
            throw StickerImageProcessingError.invalidDimensions
        }

        let isCompliantWebP = sourceExtension.lowercased() == "webp"
            && CGImageSourceGetType(source) == UTType.webP.identifier as CFString
            && CGImageSourceGetCount(source) == 1
            && image.width == Self.canvasSize
            && image.height == Self.canvasSize
            && data.count <= WhatsAppLimits.maximumStaticStickerBytes
        if isCompliantWebP {
            return ProcessedSticker(data: data, wasConverted: false)
        }

        let pixels = try renderRGBA(image)
        let encoded = try encodeWebP(pixels: pixels)
        try validateOutput(encoded)
        return ProcessedSticker(data: encoded, wasConverted: true)
    }

    func makeTrayImage(from stickerData: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(stickerData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw StickerImageProcessingError.cannotDecode
        }

        let size = WhatsAppLimits.trayImageDimension
        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * Self.bytesPerPixel,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw StickerImageProcessingError.cannotRender }

        context.interpolationQuality = .high
        context.clear(CGRect(x: 0, y: 0, width: size, height: size))
        context.draw(image, in: aspectFitRect(image: image, canvasWidth: size, canvasHeight: size))
        guard let output = context.makeImage(),
              let destinationData = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(destinationData, UTType.png.identifier as CFString, 1, nil) else {
            throw StickerImageProcessingError.cannotRender
        }

        CGImageDestinationAddImage(destination, output, nil)
        guard CGImageDestinationFinalize(destination) else { throw StickerImageProcessingError.cannotEncode }
        let data = destinationData as Data
        guard data.count <= WhatsAppLimits.maximumTrayImageBytes else {
            throw StickerImageProcessingError.cannotMeetFileSize(data.count)
        }
        return data
    }

    private func renderRGBA(_ image: CGImage) throws -> Data {
        let byteCount = Self.canvasSize * Self.canvasSize * Self.bytesPerPixel
        var pixels = Data(count: byteCount)
        let didRender = pixels.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard let baseAddress = rawBuffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: Self.canvasSize,
                    height: Self.canvasSize,
                    bitsPerComponent: 8,
                    bytesPerRow: Self.canvasSize * Self.bytesPerPixel,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return false }

            context.interpolationQuality = .high
            context.clear(CGRect(x: 0, y: 0, width: Self.canvasSize, height: Self.canvasSize))
            context.draw(image, in: aspectFitRect(image: image, canvasWidth: Self.canvasSize, canvasHeight: Self.canvasSize))
            unpremultiplyRGBA(rawBuffer.bindMemory(to: UInt8.self))
            return true
        }
        guard didRender else { throw StickerImageProcessingError.cannotRender }
        return pixels
    }

    private func encodeWebP(pixels: Data) throws -> Data {
        let qualities: [Float] = [86, 78, 70, 62, 54, 46, 38, 30, 22, 14, 8, 3]
        var smallest: Data?

        for quality in qualities {
            let candidate: Data? = pixels.withUnsafeBytes { rawBuffer in
                guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return nil }
                var output: UnsafeMutablePointer<UInt8>?
                let byteCount = WebPEncodeRGBA(
                    baseAddress,
                    Int32(Self.canvasSize),
                    Int32(Self.canvasSize),
                    Int32(Self.canvasSize * Self.bytesPerPixel),
                    quality,
                    &output
                )
                guard byteCount > 0, let output else { return nil }
                defer { WebPFree(output) }
                return Data(bytes: output, count: byteCount)
            }

            guard let candidate else { continue }
            if smallest == nil || candidate.count < (smallest?.count ?? .max) {
                smallest = candidate
            }
            if candidate.count <= WhatsAppLimits.maximumStaticStickerBytes {
                return candidate
            }
        }

        guard let smallest else { throw StickerImageProcessingError.cannotEncode }
        throw StickerImageProcessingError.cannotMeetFileSize(smallest.count)
    }

    private func validateOutput(_ data: Data) throws {
        guard data.count <= WhatsAppLimits.maximumStaticStickerBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width == Self.canvasSize,
              image.height == Self.canvasSize else {
            throw StickerImageProcessingError.cannotEncode
        }
    }

    private func aspectFitRect(image: CGImage, canvasWidth: Int, canvasHeight: Int) -> CGRect {
        let scale = min(CGFloat(canvasWidth) / CGFloat(image.width), CGFloat(canvasHeight) / CGFloat(image.height))
        let width = CGFloat(image.width) * scale
        let height = CGFloat(image.height) * scale
        return CGRect(
            x: (CGFloat(canvasWidth) - width) / 2,
            y: (CGFloat(canvasHeight) - height) / 2,
            width: width,
            height: height
        ).integral
    }

    private func unpremultiplyRGBA(_ pixels: UnsafeMutableBufferPointer<UInt8>) {
        guard pixels.count >= Self.bytesPerPixel else { return }
        for offset in stride(from: 0, to: pixels.count, by: Self.bytesPerPixel) {
            let alpha = Int(pixels[offset + 3])
            guard alpha > 0, alpha < 255 else { continue }
            pixels[offset] = UInt8(min(255, Int(pixels[offset]) * 255 / alpha))
            pixels[offset + 1] = UInt8(min(255, Int(pixels[offset + 1]) * 255 / alpha))
            pixels[offset + 2] = UInt8(min(255, Int(pixels[offset + 2]) * 255 / alpha))
        }
    }
}
