import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// A custom-drawn `NSTextAttachment` for a GFM thematic break (`---`,
/// `***`, `___`): a horizontal rule spanning the available line width,
/// not the literal dash/asterisk/underscore characters (R10). Sized
/// from `proposedLineFragment` so it always fills the container, unlike
/// `TableAttachment`'s fixed measured grid.
final class ThematicBreakAttachment: NSTextAttachment {
    let color: PlatformColorType
    static let ruleHeight: CGFloat = 9

    init(color: PlatformColorType) {
        self.color = color
        super.init(data: nil, ofType: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any],
        location: NSTextLocation,
        textContainer: NSTextContainer?,
        proposedLineFragment: CGRect,
        position: CGPoint
    ) -> CGRect {
        let width = max(proposedLineFragment.width, 10)
        return CGRect(x: 0, y: 0, width: width, height: Self.ruleHeight)
    }

    override func image(forBounds imageBounds: CGRect, textContainer: NSTextContainer?, characterIndex: Int) -> PlatformImage? {
        let size = imageBounds.size
        guard size.width > 0, size.height > 0 else { return nil }
        let width = Int(ceil(size.width))
        let height = Int(ceil(size.height))
        guard width > 0, height > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setStrokeColor(color.cgColor)
        context.setLineWidth(1)
        let midY = size.height / 2
        context.move(to: CGPoint(x: 0, y: midY))
        context.addLine(to: CGPoint(x: size.width, y: midY))
        context.strokePath()

        guard let cgImage = context.makeImage() else { return nil }
        #if os(macOS)
        return NSImage(cgImage: cgImage, size: size)
        #else
        return UIImage(cgImage: cgImage)
        #endif
    }
}
