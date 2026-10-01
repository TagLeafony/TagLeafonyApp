//
//  ImageBinarizer.swift
//  TagLeafony
//

import Foundation
import UIKit

// ============================================================================
//  写真を 296×128 の白黒2値に変換
// ============================================================================

enum ImageBinarizer {

    // 枠への収め方のプリセット
    enum Fit {
        case contain
        case cover
    }

    struct Transform: Equatable {
        // 拡大率
        var scale: CGFloat = 1
        // 中央からのずらし量
        var offset: CGSize = .zero

        static let identity = Transform()
    }

    // プリセットに対応する拡大率を求める
    static func fitScale(for image: UIImage, mode: Fit) -> CGFloat {
        guard let cg = image.cgImage, cg.width > 0, cg.height > 0 else { return 1 }

        let w = CGFloat(DisplayBitmap.width)
        let h = CGFloat(DisplayBitmap.height)
        let iw = CGFloat(cg.width)
        let ih = CGFloat(cg.height)

        switch mode {
        case .contain: return min(w / iw, h / ih)   // 小さいほうに合わせる＝全部入る
        case .cover:   return max(w / iw, h / ih)   // 大きいほうに合わせる＝埋まる
        }
    }

    /// 白黒への分け方
    enum Method: Equatable {
        /// 明るさで一刀両断（0〜255）
        case threshold(UInt8)
        /// 誤差拡散（Floyd–Steinberg）
        case dither
    }

    /// 写真を 296×128 の白黒2値の画像にする
    static func render(_ source: UIImage, transform: Transform, method: Method) -> UIImage? {
        guard let cgSource = source.cgImage else { return nil }

        let w = DisplayBitmap.width
        let h = DisplayBitmap.height

        // 白地に写真を描いて,グレースケールで取り出す
        var gray = [UInt8](repeating: 255, count: w * h)

        let drawn: Bool = gray.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress,
                  let context = CGContext(
                    data: base,
                    width: w, height: h,
                    bitsPerComponent: 8, bytesPerRow: w,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue
                  ) else { return false }

            // 余白を白で塗っておく
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: w, height: h))

            context.draw(cgSource, in: destination(for: cgSource, transform: transform))
            return true
        }
        guard drawn else { return nil }

        // 白黒に分ける
        switch method {
        case .threshold(let value):
            applyThreshold(&gray, value: value)
        case .dither:
            applyFloydSteinberg(&gray, width: w, height: h)
        }

        // 画像に戻す
        var result: CGImage?
        gray.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress,
                  let context = CGContext(
                    data: base,
                    width: w, height: h,
                    bitsPerComponent: 8, bytesPerRow: w,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue
                  ) else { return }
            result = context.makeImage()
        }

        return result.map { UIImage(cgImage: $0) }
    }

    // MARK: - 収め方

    // 元画像をどの矩形に描くか決める
    private static func destination(for image: CGImage, transform: Transform) -> CGRect {
        let w = CGFloat(DisplayBitmap.width)
        let h = CGFloat(DisplayBitmap.height)

        let dw = CGFloat(image.width) * transform.scale
        let dh = CGFloat(image.height) * transform.scale

        return CGRect(
            x: (w - dw) / 2 + transform.offset.width,

            // 上下は符号を反転する
            y: (h - dh) / 2 - transform.offset.height,

            width: dw,
            height: dh
        )
    }

    // MARK: - しきい値

    /// 明るさで一刀両断に分ける
    private static func applyThreshold(_ gray: inout [UInt8], value: UInt8) {
        for i in gray.indices {
            gray[i] = gray[i] < value ? 0 : 255
        }
    }

    // MARK: - 誤差拡散（Floyd–Steinberg）

    /// 黒い点の密度で濃淡を表現する
    private static func applyFloydSteinberg(_ gray: inout [UInt8], width: Int, height: Int) {
        // 誤差を足し引きするため、いったん Int に移す。
        var buffer = gray.map { Int($0) }

        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x

                let old = buffer[index]
                let new = old < 128 ? 0 : 255
                buffer[index] = new

                let error = old - new
                guard error != 0 else { continue }

                // 右
                if x + 1 < width {
                    buffer[index + 1] += error * 7 / 16
                }
                if y + 1 < height {
                    // 左下
                    if x > 0 {
                        buffer[index + width - 1] += error * 3 / 16
                    }
                    // 下
                    buffer[index + width] += error * 5 / 16
                    // 右下
                    if x + 1 < width {
                        buffer[index + width + 1] += error * 1 / 16
                    }
                }
            }
        }

        // 0〜255 に収めて戻す。
        for i in gray.indices {
            gray[i] = UInt8(max(0, min(255, buffer[i])))
        }
    }
}
