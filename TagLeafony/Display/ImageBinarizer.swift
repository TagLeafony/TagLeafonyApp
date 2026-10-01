//
//  ImageBinarizer.swift
//  TagLeafony
//

import Foundation
import UIKit

// ============================================================================
//  写真を 296×128 の白黒2値に変換する。
//
//  なぜ難しいか:
//      電子ペーパーには中間の灰色がない。黒か白かしかない。
//      写真は中間色だらけなので、どう振り分けるかで見え方が決まる。
//
//  2つの方法を用意してある:
//
//      しきい値  … 明るさで一刀両断に分ける
//                  ロゴ・線画・文字の写真に向く
//                  写真に使うと真っ黒な塊になりがち
//
//      ディザ    … 黒い点の密度で濃淡を表現する
//                  新聞の網点と同じ考え方
//                  写真に向く。線画だとざらつく
//
//  どちらが良いかは絵による。両方試せるようにして、
//  プレビューを見ながら選んでもらう。
// ============================================================================

enum ImageBinarizer {

    /// 枠への収め方のプリセット。
    enum Fit {
        /// 全体を入れる。余白は白。何も切れないが、横長の画面なので上下が空く
        case contain
        /// 画面を埋める。はみ出した部分は切れる
        case cover
    }

    /// 写真をどう置くか。
    ///
    /// 単位はすべて **296×128 の座標系**。画面上のポイントではない。
    /// 指で動かすときは、プレビューの表示幅から換算して渡す。
    struct Transform: Equatable {
        /// 拡大率。1.0 で元画像の等倍（1ピクセルが1ピクセル）
        var scale: CGFloat = 1
        /// 中央からのずらし量。右・下が正
        var offset: CGSize = .zero

        static let identity = Transform()
    }

    /// プリセットに対応する拡大率を求める。
    ///
    /// 「全体を入れる」「画面を埋める」ボタンを押したときの初期値に使う。
    /// 押したあとは指で自由に動かせる。
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

    /// 白黒への分け方。
    enum Method: Equatable {
        /// 明るさで一刀両断（0〜255）
        case threshold(UInt8)
        /// 誤差拡散（Floyd–Steinberg）
        case dither
    }

    /// 写真を 296×128 の白黒2値の画像にする。
    static func render(_ source: UIImage, transform: Transform, method: Method) -> UIImage? {
        guard let cgSource = source.cgImage else { return nil }

        let w = DisplayBitmap.width
        let h = DisplayBitmap.height

        // ---- 1. 白地に写真を描いて、グレースケールで取り出す ----
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

            // 余白を白で塗っておく。contain のとき上下が黒くならないように。
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: w, height: h))

            context.draw(cgSource, in: destination(for: cgSource, transform: transform))
            return true
        }
        guard drawn else { return nil }

        // ---- 2. 白黒に分ける ----
        switch method {
        case .threshold(let value):
            applyThreshold(&gray, value: value)
        case .dither:
            applyFloydSteinberg(&gray, width: w, height: h)
        }

        // ---- 3. 画像に戻す ----
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

    /// 元画像をどの矩形に描くか決める。
    ///
    /// 中央に置いてから、指定されたぶんだけずらす。
    /// 枠からはみ出した部分は自然に切れ、足りない部分は白のまま残る。
    private static func destination(for image: CGImage, transform: Transform) -> CGRect {
        let w = CGFloat(DisplayBitmap.width)
        let h = CGFloat(DisplayBitmap.height)

        let dw = CGFloat(image.width) * transform.scale
        let dh = CGFloat(image.height) * transform.scale

        return CGRect(
            x: (w - dw) / 2 + transform.offset.width,

            // ★上下は符号を反転する★
            // CGContext の座標は左下が原点で、上へ行くほど y が増える。
            // 画面のドラッグは下へ動かすと y が増えるので、そのまま足すと
            // 指と逆向きに動く。ここで合わせる。
            //
            // Transform.offset は「画面と同じ向き（下が正）」で持つ、
            // という約束にしておきたいので、使う側ではなく描画側で吸収する。
            y: (h - dh) / 2 - transform.offset.height,

            width: dw,
            height: dh
        )
    }

    // MARK: - しきい値

    /// 明るさで一刀両断に分ける。
    private static func applyThreshold(_ gray: inout [UInt8], value: UInt8) {
        for i in gray.indices {
            gray[i] = gray[i] < value ? 0 : 255
        }
    }

    // MARK: - 誤差拡散（Floyd–Steinberg）

    /// 黒い点の密度で濃淡を表現する。
    ///
    /// 考え方:
    ///   あるピクセルを白か黒に丸めると、本来の明るさとの差（誤差）が出る。
    ///   その誤差を右と下のまだ処理していないピクセルへ配って、
    ///   全体としては元の明るさに近づける。
    ///
    ///   配る割合は決まっていて、
    ///         *   7/16
    ///   3/16 5/16 1/16
    ///   の形に散らす（* が処理中のピクセル）。
    ///
    /// 誤差でマイナスや255超えが出るので、計算は Int で行う。
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
