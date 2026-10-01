//
//  TagTabView.swift
//  TagLeafony
//

import SwiftUI

// ============================================================================
//  「タグ」タブ。デモの主役になる画面。
// ============================================================================

struct TagTabView: View {

    @ObservedObject private var link = TagLinkManager.shared

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)

            statusCard
            displayPreview

            Spacer(minLength: 0)

            startStopButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
        .background(backgroundTint)
        // 状態が変わるときに色と文字がふっと切り替わる
        .animation(.easeInOut(duration: 0.4), value: link.presence)
    }

    // MARK: - 状態カード

    private var statusCard: some View {
        VStack(spacing: 14) {

            // 色だけでなく形でも区別する
            Image(systemName: presenceIcon)
                .font(.system(size: 64))
                .foregroundStyle(presenceColor)

            Text(presenceText)
                .font(.largeTitle.bold())
                .foregroundStyle(presenceColor)

            Text(lastSeenText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // 最後に確認できてからの経過
            if link.isRunning {
                Text("\(Int(link.elapsed)) 秒前に確認")
                    .font(.caption)
                    .foregroundStyle(link.elapsed > 5 ? .orange : .secondary)
                    .monospacedDigit()   // 数字が揺れないように等幅にする
            }

            // 受信回数は検証用の情報なので、詳細ログのときだけ出す
            if link.verboseLogging {
                Text("累計 \(link.discoverCount) 回受信")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.background.secondary)
        )
    }

    // MARK: - タグの表示内容

    // タグの電子ペーパーに出ている内容を映す枠
    private var displayPreview: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    .tertiary,
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
                .aspectRatio(296.0 / 128.0, contentMode: .fit)
                .overlay {
                    Text("表示内容は未設定")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }

            Text("タグの表示")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 操作（開発用）

    private var startStopButton: some View {
        Button(link.isRunning ? "停止" : "開始") {
            link.isRunning ? link.stop() : link.start()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(link.isRunning ? .red : .accentColor)
    }

    // MARK: - 状態ごとの見た目

    private var presenceText: String {
        switch link.presence {
        case .unknown: return link.isRunning ? "探しています" : "停止中"
        case .present: return "近くにあります"
        case .away:    return "離れています"
        }
    }

    private var presenceIcon: String {
        switch link.presence {
        case .unknown: return link.isRunning ? "dot.radiowaves.left.and.right" : "pause.circle"
        case .present: return "checkmark.circle.fill"
        case .away:    return "exclamationmark.triangle.fill"
        }
    }

    private var presenceColor: Color {
        switch link.presence {
        case .unknown: return .secondary
        case .present: return .green
        case .away:    return .red
        }
    }

    /// 最終確認時刻の文言
    private var lastSeenText: String {
        guard let at = link.lastSeenAt else { return "まだ一度も確認できていません" }
        return "最終確認 " + at.formatted(date: .omitted, time: .standard)
    }

    /// 画面全体をうっすら染める
    private var backgroundTint: some View {
        Group {
            switch link.presence {
            case .away: Color.red.opacity(0.10)
            default:    Color.clear
            }
        }
        .ignoresSafeArea()
    }
}

#Preview {
    TagTabView()
}
