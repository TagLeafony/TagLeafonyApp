//
//  DisplayBitmap.swift
//  TagLeafony
//

import Foundation
import UIKit

// ============================================================================
//  296×128 の白黒画像を、タグへ送れる形に変換
//
//  変換の流れ:
//      UIImage（296×128・白黒）
//          ↓ グレースケールのバイト列として読み出す
//      1ピクセル = 1バイト（37,888バイト）
//          ↓ しきい値で白黒に分け、8ピクセルを1バイトに詰める
//      1ピクセル = 1ビット（4,736バイト）
//          ↓
//      Base64（約6.3KB）
// ============================================================================

enum DisplayBitmap {

    // 電子ペーパーの解像度
    static let width  = 296
    static let height = 128

    // 1行あたりのバイト数（37バイト）と全体のバイト数（4,736バイト）
    static var bytesPerRow: Int { width / 8 }
    static var byteCount: Int { bytesPerRow * height }

    // MARK: - 担当Aと合わせる設定

    enum Format {
        // 1バイトに詰める8ピクセルの向き
        // 横パック = 横に並んだ8ピクセル
        // 縦パック = 縦に並んだ8ピクセル
        static let horizontalPacking = true

        // 1バイトの最上位ビット（MSB）が左端のピクセルか
        static let msbIsLeft = true

        // ビットが 0 のとき黒か。
        static let zeroIsBlack = true

        // 上下を反転するか
        static let flipVertical = false

        /// 白黒に分けるしきい値（0〜255）
        static let threshold: UInt8 = 128
    }

    // MARK: - 変換

    // UIImage を 1bpp のバイト列に変換する。
    static func pack(_ image: UIImage) -> Data? {
        guard let cgImage = image.cgImage else { return nil }

        // グレースケールで読み出す
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

        // しきい値で白黒に分けて8ピクセルを1バイトに詰める
        var packed = [UInt8](repeating: 0, count: byteCount)

        for y in 0..<height {
            let sourceRow = Format.flipVertical ? (height - 1 - y) : y

            for x in 0..<width {
                let isBlack = gray[sourceRow * width + x] < Format.threshold

                let bit = Format.zeroIsBlack ? !isBlack : isBlack
                guard bit else { continue }

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

    /// Base64 文字列にする
    static func base64(_ image: UIImage) -> String? {
        pack(image)?.base64EncodedString()
    }

    // MARK: - 復元

    // Base64 から画像に戻す
    static func unpack(base64: String) -> UIImage? {
        guard let data = Data(base64Encoded: base64), data.count == byteCount else { return nil }
        return unpack(data)
    }

    // バイト列から画像に戻す
    static func unpack(_ data: Data) -> UIImage? {
        guard data.count == byteCount else { return nil }

        var gray = [UInt8](repeating: 255, count: width * height)

        for y in 0..<height {
            // pack()と同じ並べ方で読み出す
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

    /// ビットの並べ方が合っているかを確かめるための市松模様
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

            // 左上の目印
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: blockSize * 3, height: blockSize))
        }
    }
}
