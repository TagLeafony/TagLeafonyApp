//
//  SettingsTabView.swift
//  TagLeafony
//

import SwiftUI

// ============================================================================
//  「設定」タブ。
// ============================================================================

struct SettingsTabView: View {

    @ObservedObject private var link = TagLinkManager.shared

    var body: some View {
        NavigationStack {
            Form {
                Section("開発者向け") {
                    // 検証用の細かいログの切り替え
                    // 普段は off。到達距離や受信頻度を測るときだけ on にする
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
