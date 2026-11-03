import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum SVGRasterizerError: Error, Equatable {
    case decodeFailed
    case renderFailed
    case encodeFailed
}

/// SVG -> PNG on the host (design §5 step 3, R1/V7).
///
/// `NSImage` decodes the SVG and `cgImage(forProposedRect:)` rasterizes it, but that call
/// does not guarantee a pixel size (it can follow the display's backing scale: measured on
/// the operator's Mac, 2026-11-02, the first version produced a width != 256). So the
/// result is always redrawn into a CGContext of exactly the requested pixel size. This is
/// pure CoreGraphics + ImageIO after the decode, so it is also safe off the main thread.
/// Transparent background preserved (white-on-clear for monotone icons).
enum SVGRasterizer {
    static func pngData(from svg: Data, pixels: Int = 256) throws -> Data {
        guard pixels > 0, let image = NSImage(data: svg),
              image.size.width > 0, image.size.height > 0 else {
            throw SVGRasterizerError.decodeFailed
        }
        let longSide = max(image.size.width, image.size.height)
        let width = max(1, Int((image.size.width * CGFloat(pixels) / longSide).rounded()))
        let height = max(1, Int((image.size.height * CGFloat(pixels) / longSide).rounded()))

        // Render the source at 2x the target so downscaling stays sharp whatever scale
        // the system applies.
        var proposed = NSRect(x: 0, y: 0, width: CGFloat(width * 2), height: CGFloat(height * 2))
        guard let source = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
            throw SVGRasterizerError.renderFailed
        }

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw SVGRasterizerError.renderFailed }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let exact = context.makeImage() else { throw SVGRasterizerError.renderFailed }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil) else {
            throw SVGRasterizerError.encodeFailed
        }
        CGImageDestinationAddImage(destination, exact, nil)
        guard CGImageDestinationFinalize(destination) else { throw SVGRasterizerError.encodeFailed }
        return output as Data
    }
}
