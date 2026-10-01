//
//  LogView.swift
//  TagLeafony
//

import SwiftUI

// ============================================================================
//  ログ画面。設定タブの奥に置いてある。
//
//  なぜ必要か:
//      実機を持って部屋の外まで歩く検証では、Xcode のコンソールが見られない。
//      画面にログが出ていないと、そもそも検証が成立しない。
//
//      実際、Leafony がアドバタイズを止めていた件も、
//      バックグラウンドでの受信頻度も、この画面が無ければ分からなかった。
//
//  なぜ奥に置くか:
//      デモで審査員が見るのは「離れて表示が変わる」瞬間。
//      ログが流れている画面は製品に見えない。
//      普段は隠れていて、必要なときだけ開ければよい。
// ============================================================================

struct LogView: View {

    @ObservedObject private var link = TagLinkManager.shared

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // LazyVStack は画面に入った分だけ描画する。
                // ログが数百行になっても重くならない。
                LazyVStack(alignment: .leading, spacing: 2) {

                    // ログは単なる String の配列で、同じ文字列が重複しうる。
                    // そのまま id: \.self にすると ID が衝突して描画が壊れるので、
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
                // 歩きながら見るので、常に最新行を表示しておく。
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
