//
//  SettingsTabView.swift
//  TagLeafony
//

import SwiftUI

// ============================================================================
//  「設定」タブ。
//
//  いまは開発者向けの項目だけ。ログをここへ移したことで、
//  タグタブが状態表示に専念できるようになった。
//
//  これから足す予定のもの:
//      - アカウントの入力欄（サーバー側が決まってから。起動導線には置かない）
//      - プロファイル選択（人用30秒 / モノ用5分）
//      - 通知の許可状態
//      - タグの登録解除
// ============================================================================

struct SettingsTabView: View {

    @ObservedObject private var link = TagLinkManager.shared

    var body: some View {
        NavigationStack {
            Form {
                Section("開発者向け") {
                    // 検証用の細かいログの切り替え。
                    // 普段は off。到達距離や受信頻度を測るときだけ on にする。
                    Toggle("詳細ログ", isOn: $link.verboseLogging)

                    NavigationLink("ログを見る") {
                        LogView()
                    }
                }
            }
            .navigationTitle("設定")
        }
    }
}

#Preview {
    SettingsTabView()
}
