//
//  LogView.swift
//  TagLeafony
//

import SwiftUI

// ============================================================================
//  ログ画面。設定タブの奥に置いてある。
// ============================================================================

struct LogView: View {

    @ObservedObject private var link = TagLinkManager.shared

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // LazyVStack は画面に入った分だけ描画
                LazyVStack(alignment: .leading, spacing: 2) {

                    // enumerated() で添字を付けて、それを ID にする。
                    ForEach(Array(link.logs.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))  // 等幅で時刻が揃う
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)   // 数値を書き写せるように
                            .id(index)                 // scrollTo の目印
                    }
                }
                .padding(12)
            }
            .onChange(of: link.logs.count) { _, count in
                // 歩きながら見るので、常に最新行を表示
                guard count > 0 else { return }
                proxy.scrollTo(count - 1, anchor: .bottom)
            }
        }
        .navigationTitle("ログ")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        LogView()
    }
}
