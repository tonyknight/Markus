import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Custom-drawn Preview callout for GitHub alerts. Chrome (fill, left
/// bar, label) uses one `tokens.callout` color; the type is the keyword
/// plus an SF Symbol, not a second well. Body text is already themed
/// by `PreviewElementRenderer`. Not a fold type.
final class CalloutAttachment: NSTextAttachment {
    let type: GitHubAlertType
    let body: NSAttributedString
    let chrome: PlatformColorType
    let zoomScale: CGFloat

    private let padding: CGFloat
    private let barWidth: CGFloat = 3
    private let barGap: CGFloat = 10
    private let labelGap: CGFloat = 6
    private let labelBodyGap: CGFloat = 6
    private let cornerRadius: CGFloat = 6
    private let symbolSize: CGFloat
    private let labelFont: PlatformFontType

    private var measuredWidth: CGFloat = 0
    private var measuredHeight: CGFloat = 0

    init(
        type: GitHubAlertType,
        body: NSAttributedString,
        chrome: PlatformColorType,
        zoomScale: CGFloat
    ) {
        self.type = type
        self.body = body
        self.chrome = chrome
        self.zoomScale = zoomScale
        let scale = max(0.5, zoomScale)
        padding = 10 * scale
        symbolSize = 14 * scale
        labelFont = PlatformFont.heading(size: 13 * scale)
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
        let width = max(proposedLineFragment.width, 80)
        if width != measuredWidth {
            measuredWidth = width
            measuredHeight = layoutHeight(for: width)
        }
        return CGRect(x: 0, y: 0, width: width, height: measuredHeight)
    }

    override func image(forBounds imageBounds: CGRect, textContainer: NSTextContainer?, characterIndex: Int) -> PlatformImage? {
        let size = imageBounds.size
        guard size.width > 0, size.height > 0 else { return nil }
        let pixelWidth = Int(ceil(size.width))
        let pixelHeight = Int(ceil(size.height))
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        draw(in: context, size: size)

        guard let cgImage = context.makeImage() else { return nil }
        #if os(macOS)
        return NSImage(cgImage: cgImage, size: size)
        #else
        return UIImage(cgImage: cgImage)
        #endif
    }

    private func contentX() -> CGFloat {
        padding + barWidth + barGap
    }

    private func contentWidth(for width: CGFloat) -> CGFloat {
        max(20, width - contentX() - padding)
    }

    private func labelHeight() -> CGFloat {
        max(symbolSize, ceil(labelFont.ascender - labelFont.descender + labelFont.leading))
    }

    private func bodyHeight(for width: CGFloat) -> CGFloat {
        guard body.length > 0 else { return 0 }
        let constraint = CGSize(width: contentWidth(for: width), height: CGFloat.greatestFiniteMagnitude)
        let rect = body.boundingRect(with: constraint, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        return ceil(rect.height)
    }

    private func layoutHeight(for width: CGFloat) -> CGFloat {
        let bodyH = bodyHeight(for: width)
        let gap = bodyH > 0 ? labelBodyGap : 0
        return padding + labelHeight() + gap + bodyH + padding
    }

    private func draw(in context: CGContext, size: CGSize) {
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)

        let bounds = CGRect(origin: .zero, size: size)
        let clip = CGPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )

        context.saveGState()
        context.addPath(clip)
        context.clip()
        context.setFillColor(chrome.withAlphaComponent(0.14).cgColor)
        context.fill(bounds)
        context.setFillColor(chrome.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: barWidth, height: size.height))
        context.restoreGState()

        context.setStrokeColor(chrome.withAlphaComponent(0.45).cgColor)
        context.setLineWidth(1)
        context.addPath(clip)
        context.strokePath()

        #if os(macOS)
        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: true)
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = graphicsContext
        defer { NSGraphicsContext.current = previous }
        #else
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }
        #endif

        let x = contentX()
        let labelH = labelHeight()
        let symbolRect = CGRect(x: x, y: padding, width: symbolSize, height: symbolSize)
        drawSymbol(in: symbolRect)

        let labelX = x + symbolSize + labelGap
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: chrome,
        ]
        let labelSize = (type.label as NSString).size(withAttributes: labelAttributes)
        let labelY = padding + max(0, (labelH - labelSize.height) / 2)
        (type.label as NSString).draw(
            at: CGPoint(x: labelX, y: labelY),
            withAttributes: labelAttributes
        )

        guard body.length > 0 else { return }
        let bodyY = padding + labelH + labelBodyGap
        let bodyRect = CGRect(
            x: x,
            y: bodyY,
            width: contentWidth(for: size.width),
            height: max(0, size.height - bodyY - padding)
        )
        body.draw(with: bodyRect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
    }

    private func drawSymbol(in rect: CGRect) {
        #if os(macOS)
        guard let image = NSImage(systemSymbolName: type.symbolName, accessibilityDescription: type.label) else {
            return
        }
        let configured = image.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: rect.height, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [chrome]))
        ) ?? image
        configured.draw(in: rect)
        #else
        let config = UIImage.SymbolConfiguration(pointSize: rect.height, weight: .semibold)
        guard let image = UIImage(systemName: type.symbolName, withConfiguration: config)?
            .withTintColor(chrome, renderingMode: .alwaysOriginal) else { return }
        image.draw(in: rect)
        #endif
    }
}
