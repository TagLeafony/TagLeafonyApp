//
//  TextRenderer.swift
//  TagLeafony
//

import Foundation
import UIKit

// ============================================================================
//  文字を 296×128 の白黒画像に描く。
//
//  なぜアプリ側で描くのか:
//      マイコンに日本語フォントを載せるのは容量的に厳しい。
//      iOS にはフォントが揃っているので、こちら側で絵にしてから送る。
//      タグは受け取った絵をそのまま出すだけでよくなる。
//
//  2つの工夫:
//      1. 文字サイズを自動で決める
//         入力量に応じて、枠に収まる最大のサイズを探す。
//         ユーザーが文字数を気にしなくて済む。
//
//      2. アンチエイリアスを切る
//         通常の描画は文字の縁を灰色でぼかす。あとで白黒2値にするとき、
//         その灰色が消えて細い線が途切れる。最初から2値で描いたほうが
//         きれいに出る。
// ============================================================================

enum TextRenderer {

    /// 上下左右の余白（ピクセル）。
    /// 電子ペーパーの端は筐体で隠れることがあるので、少し内側に寄せる。
    static let margin: CGFloat = 8

    /// 試す文字サイズの範囲。大きいほうから順に試して、収まったところで止める。
    static let maxFontSize: CGFloat = 56
    static let minFontSize: CGFloat = 10

    /// 文字を 296×128 の白黒画像に描く。
    ///
    /// - Parameter text: 表示する文字。改行はそのまま反映される。
    /// - Returns: 白地に黒文字の画像。
    static func render(_ text: String) -> UIImage {
        let size = CGSize(width: DisplayBitmap.width, height: DisplayBitmap.height)
        let box = CGRect(origin: .zero, size: size).insetBy(dx: margin, dy: margin)

        let fontSize = fittingFontSize(for: text, in: box.size)
        let attributes = textAttributes(fontSize: fontSize)

        // scale = 1 にすると「1ポイント = 1ピクセル」になる。
        // 既定のままだと Retina 倍率がかかって 296×128 にならない。
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            // ★アンチエイリアスを切る★
            // 切らないと文字の縁が灰色になり、1bpp に変換するとき
            // しきい値の加減で細い線が消える。
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

    /// 枠に収まる最大の文字サイズを探す。
    ///
    /// 大きいほうから1ptずつ試して、最初に収まったものを採用する。
    /// 試行は最大47回なので、入力のたびに呼んでも重くない。
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
