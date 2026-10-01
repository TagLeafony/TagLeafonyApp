//
//  DisplayBitmap.swift
//  TagLeafony
//

import Foundation
import UIKit

// ============================================================================
//  296×128 の白黒画像を、タグへ送れる形に変換する。
//
//  変換の流れ:
//      UIImage（296×128・白黒）
//          ↓ グレースケールのバイト列として読み出す
//      1ピクセル = 1バイト（37,888バイト）
//          ↓ しきい値で白黒に分け、8ピクセルを1バイトに詰める
//      1ピクセル = 1ビット（4,736バイト）
//          ↓
//      Base64（約6.3KB）
//
//  ★ビットの並べ方は担当A待ち★
//      同じ4,736バイトでも、並べ方が違うと絵が壊れる。
//      下の Format で切り替えられるようにしてあるので、
//      決まったら値を変えるだけで済む。
//
//      確かめ方: testPattern() で市松模様を作り、タグに出してみる。
//      ずれていれば一目で分かる。
// ============================================================================

enum DisplayBitmap {

    /// 電子ペーパーの解像度。296 は 8 で割り切れるので、行末の端数が出ない。
    static let width  = 296
    static let height = 128

    /// 1行あたりのバイト数（37バイト）と、全体のバイト数（4,736バイト）。
    static var bytesPerRow: Int { width / 8 }
    static var byteCount: Int { bytesPerRow * height }

    // MARK: - ★担当Aと合わせる設定★

    enum Format {
        /// 1バイトに詰める8ピクセルの向き。
        /// 横パック = 横に並んだ8ピクセル（2.9インチの電子ペーパーでは一般的）
        /// 縦パック = 縦に並んだ8ピクセル（SSD1306系のOLEDに多い）
        static let horizontalPacking = true

        /// 1バイトの最上位ビット（MSB）が左端のピクセルか。
        static let msbIsLeft = true

        /// ビットが 0 のとき黒か。
        /// コントローラによって逆のことがある。反転して見えたらここを変える。
        static let zeroIsBlack = true

        /// 上下を反転するか。
        /// 絵が上下逆さに出たら true にする。
        static let flipVertical = false

        /// 白黒に分けるしきい値（0〜255）。
        /// これより暗ければ黒。文字だけなら何でもよいが、写真では効く。
        static let threshold: UInt8 = 128
    }

    // MARK: - 変換

    /// UIImage を 1bpp のバイト列に変換する。
    ///
    /// - Parameter image: 296×128 で描かれた画像。サイズが違っても引き伸ばされる。
    /// - Returns: 4,736バイトのデータ。失敗したら nil。
    static func pack(_ image: UIImage) -> Data? {
        guard let cgImage = image.cgImage else { return nil }

        // ---- 1. グレースケールで読み出す ----
        // 1ピクセル = 1バイト（0 が黒、255 が白）の素直な形に直す。
        // 元画像がカラーでもここで灰色になる。
        //
        // ★withUnsafeMutableBytes の中で描画を終わらせること★
        // CGContext(data: &gray, ...) と書くと、ポインタが有効なのは
        // その行の実行中だけ。あとから context.draw を呼ぶと、
        // すでに無効になったポインタに書き込むことになる。
        // たいてい動いてしまうが、保証のない書き方。
        var gray = [UInt8](repeating: 255, count: width * height)

        let drawn: Bool = gray.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress,
                  let context = CGContext(
                    data: base,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue
                  ) else { return false }

            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        // ---- 2. しきい値で白黒に分けて、8ピクセルを1バイトに詰める ----
        var packed = [UInt8](repeating: 0, count: byteCount)

        for y in 0..<height {
            // 上下反転の指定があれば、読む行を逆順にする。
            let sourceRow = Format.flipVertical ? (height - 1 - y) : y

            for x in 0..<width {
                let isBlack = gray[sourceRow * width + x] < Format.threshold

                // そのピクセルを 1 にするか 0 にするか。
                let bit = Format.zeroIsBlack ? !isBlack : isBlack
                guard bit else { continue }   // 0 のままでよいので何もしない

                let index: Int
                let shift: Int

                if Format.horizontalPacking {
                    // 横パック: 1バイト = 横に並んだ8ピクセル
                    index = y * bytesPerRow + (x / 8)
                    shift = Format.msbIsLeft ? (7 - x % 8) : (x % 8)
                } else {
                    // 縦パック: 1バイト = 縦に並んだ8ピクセル
                    index = (y / 8) * width + x
                    shift = Format.msbIsLeft ? (7 - y % 8) : (y % 8)
                }

                packed[index] |= (1 << shift)
            }
        }

        return Data(packed)
    }

    /// Base64 文字列にする。サーバーへ送る形。
    static func base64(_ image: UIImage) -> String? {
        pack(image)?.base64EncodedString()
    }

    // MARK: - 復元

    /// Base64 から画像に戻す。pack() の逆。
    ///
    /// 一覧のサムネイルに使う。元の UIImage を保存しておくのではなく
    /// 送るデータから戻すことで、**画面に見えているものと、タグへ送るものが
    /// 必ず一致する**ようになる。食い違いが起きない。
    static func unpack(base64: String) -> UIImage? {
        guard let data = Data(base64Encoded: base64), data.count == byteCount else { return nil }
        return unpack(data)
    }

    /// バイト列から画像に戻す。
    static func unpack(_ data: Data) -> UIImage? {
        guard data.count == byteCount else { return nil }

        var gray = [UInt8](repeating: 255, count: width * height)

        for y in 0..<height {
            // pack() と同じ並べ方で読み出す。
            let targetRow = Format.flipVertical ? (height - 1 - y) : y

            for x in 0..<width {
                let index: Int
                let shift: Int

                if Format.horizontalPacking {
                    index = y * bytesPerRow + (x / 8)
                    shift = Format.msbIsLeft ? (7 - x % 8) : (x % 8)
                } else {
                    index = (y / 8) * width + x
                    shift = Format.msbIsLeft ? (7 - y % 8) : (y % 8)
                }

                let bit = (data[index] >> shift) & 1 == 1
                let isBlack = Format.zeroIsBlack ? !bit : bit
                gray[targetRow * width + x] = isBlack ? 0 : 255
            }
        }

        var result: CGImage?
        gray.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress,
                  let context = CGContext(
                    data: base,
                    width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue
                  ) else { return }
            result = context.makeImage()
        }
        return result.map { UIImage(cgImage: $0) }
    }

    // MARK: - 確認用

    /// ビットの並べ方が合っているかを確かめるための市松模様。
    ///
    /// タグに出してみて、
    ///   きれいな市松      → 並べ方が合っている
    ///   縦縞・横縞になる  → パックの向きが違う
    ///   白黒が逆          → zeroIsBlack が違う
    ///   上下逆            → flipVertical が違う
    ///
    /// 左上に小さな黒い四角を入れてあるので、向きも分かる。
    static func testPattern(blockSize: Int = 8) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1          // 1ポイント = 1ピクセルにする
        format.opaque = true

        let size = CGSize(width: width, height: height)
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            UIColor.black.setFill()
            for y in stride(from: 0, to: height, by: blockSize) {
                for x in stride(from: 0, to: width, by: blockSize) {
                    let isBlack = ((x / blockSize) + (y / blockSize)) % 2 == 0
                    if isBlack {
                        ctx.fill(CGRect(x: x, y: y, width: blockSize, height: blockSize))
                    }
                }
            }

            // 左上の目印。向きが逆だとここが別の角に来る。
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: blockSize * 3, height: blockSize))
        }
    }
}
