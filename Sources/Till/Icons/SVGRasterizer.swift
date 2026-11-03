import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum SVGRasterizerError: Error, Equatable {
    case decodeFailed
    case renderFailed
    case encodeFailed
}

/// SVG -> PNG on the host (design §5 step 3, R1/V7). `NSImage` decodes the SVG; the
/// result is rendered at a fixed pixel size through `cgImage(forProposedRect:)` and
/// encoded with ImageIO, which keeps the whole path off AppKit drawing contexts.
/// Transparent background preserved (white-on-clear for monotone icons).
enum SVGRasterizer {
    static func pngData(from svg: Data, pixels: Int = 256) throws -> Data {
        guard let image = NSImage(data: svg),
              image.size.width > 0, image.size.height > 0 else {
            throw SVGRasterizerError.decodeFailed
        }
        let scale = CGFloat(pixels) / max(image.size.width, image.size.height)
        var rect = NSRect(
            x: 0, y: 0,
            width: max(1, (image.size.width * scale).rounded()),
            height: max(1, (image.size.height * scale).rounded()))
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            throw SVGRasterizerError.renderFailed
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil) else {
            throw SVGRasterizerError.encodeFailed
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { throw SVGRasterizerError.encodeFailed }
        return output as Data
    }
}
