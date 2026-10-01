//
//  TextRenderer.swift
//  TagLeafony
//

import Foundation
import UIKit

// ============================================================================
//  文字を 296×128 の白黒画像に描く。
// ============================================================================

enum TextRenderer {

    // 上下左右の余白（ピクセル）
    static let margin: CGFloat = 8

    // 試す文字サイズの範囲
    static let maxFontSize: CGFloat = 56
    static let minFontSize: CGFloat = 10

    // 文字を296×128の白黒画像に描く
    static func render(_ text: String) -> UIImage {
        let size = CGSize(width: DisplayBitmap.width, height: DisplayBitmap.height)
        let box = CGRect(origin: .zero, size: size).insetBy(dx: margin, dy: margin)

        let fontSize = fittingFontSize(for: text, in: box.size)
        let attributes = textAttributes(fontSize: fontSize)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            // アンチエイリアスを切る
            ctx.cgContext.setShouldAntialias(false)
            ctx.cgContext.setAllowsAntialiasing(false)

            // 縦方向の中央に寄せる。
            let bounds = (text as NSString).boundingRect(
                with: CGSize(width: box.width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes,
                context: nil
            )
            let y = box.minY + max(0, (box.height - bounds.height) / 2)
            let drawRect = CGRect(x: box.minX, y: y, width: box.width, height: bounds.height)

            (text as NSString).draw(with: drawRect,
                                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                                    attributes: attributes,
                                    context: nil)
        }
    }

    // MARK: - 文字サイズの自動決定

    // 枠に収まる最大の文字サイズを探す。
    private static func fittingFontSize(for text: String, in size: CGSize) -> CGFloat {
        guard !text.isEmpty else { return maxFontSize }

        var fontSize = maxFontSize
        while fontSize > minFontSize {
            let bounds = (text as NSString).boundingRect(
                with: CGSize(width: size.width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: textAttributes(fontSize: fontSize),
                context: nil
            )
            if bounds.height <= size.height { return fontSize }
            fontSize -= 1
        }
        return minFontSize
    }

    private static func textAttributes(fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping   // 長い行は折り返す

        return [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: UIColor.black,
            .paragraphStyle: paragraph
        ]
    }
}
