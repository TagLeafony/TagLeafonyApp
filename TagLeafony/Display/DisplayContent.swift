//
//  DisplayContent.swift
//  TagLeafony
//

import Combine
import Foundation
import UIKit

// ============================================================================
//  登録した表示内容の、1件ぶんのデータと保管庫。
//
//  ★いまは端末の中に保存している★
//      本来の保存先はサーバー（担当Bの /api/upload_image）だが、
//      APIがまだ固まっていない。待っていると手が止まるので、
//      まず端末内で完結させておき、あとで保存先だけ差し替える。
//
//      ContentStore の save / delete の中身を API 呼び出しに置き換えれば、
//      画面側は一切触らずに移行できる。
//
//  何を持つか:
//      - bitmapBase64 … タグへ送るデータそのもの。これが本体
//      - sourceText   … 文字から作った場合の元の文字列
//
//      元の文字列を残しているのは、あとで直せるようにするため。
//      ビットマップだけ持っていると、誤字ひとつ直すのに一から入力し直しになる。
//
//      写真の元データは持っていない。持つと数百KB×件数になるうえ、
//      撮り直しは選び直せば済むため。文字だけ特別扱いしている。
// ============================================================================

struct DisplayContent: Identifiable, Codable, Equatable {

    var id = UUID()

    /// 一覧で見分けるための名前。
    var name: String

    var createdAt = Date()

    /// 1bpp に詰めたものを Base64 にした文字列。
    /// サーバーへ送るのも、タグが受け取るのもこれ。
    var bitmapBase64: String

    /// 文字から作った場合の元の文字列。写真から作った場合は nil。
    var sourceText: String?

    /// 保存しているデータから画像に戻す。
    ///
    /// 作ったときの UIImage を持ち回すのではなく、送るデータから戻している。
    /// こうすると **画面に見えるものとタグへ送るものが必ず一致する**。
    var image: UIImage? {
        DisplayBitmap.unpack(base64: bitmapBase64)
    }
}

// ============================================================================
//  保管庫。
// ============================================================================

@MainActor
final class ContentStore: ObservableObject {

    static let shared = ContentStore()

    @Published private(set) var contents: [DisplayContent] = []

    /// 保存先のファイル。Documents の下に JSON で置く。
    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("display-contents.json")
    }()

    private init() {
        load()
    }

    // MARK: - 追加・更新・削除

    /// 追加、または同じ id のものを置き換える。
    func save(_ content: DisplayContent) {
        if let index = contents.firstIndex(where: { $0.id == content.id }) {
            contents[index] = content
        } else {
            contents.insert(content, at: 0)   // 新しいものを上に
        }
        persist()
    }

    func delete(_ content: DisplayContent) {
        contents.removeAll { $0.id == content.id }
        persist()
    }

    /// スワイプ削除から呼ばれる。
    ///
    /// remove(atOffsets:) は SwiftUI 側で定義されているので、
    /// このファイルでは使えない（UI を知らないファイルにしておきたい）。
    /// 後ろから消せば添字がずれないので、自前で書く。
    func delete(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) where contents.indices.contains(index) {
            contents.remove(at: index)
        }
        persist()
    }

    // MARK: - 読み書き

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([DisplayContent].self, from: data)
        else { return }   // 無ければ空のまま始める
        contents = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(contents) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
