//
//  TagTabView.swift
//  TagLeafony
//

import SwiftUI

// ============================================================================
//  「タグ」タブ。デモの主役になる画面。
//
//  審査で見せる瞬間は「離れて名札の表示が変わる」ところで、
//  そのときスマホ画面も一緒に見られる。状態の変化が一目で分かることを
//  最優先にする。
//
//  仮デザインの方針:
//      1. 平常時は静かに、異常時に強く主張する
//         → 平常時からカラフルだと、緊急時の変化が目立たない
//      2. 色だけで区別しない
//         → アイコンの形でも分かるようにする（色覚に依存させない）
//      3. 開発用の操作は目立たせない
//         → 開始／停止は下端に小さく置く
//
//  まだ載せていないもの（設計が固まってから足す）:
//      - タグが実際に表示している内容（サーバーから取得）
//      - 保留への切り替え（サーバー経由）
//      - 電池残量
//    動かないボタンを置くと「壊れている」ように見えるので、出さない。
// ============================================================================

struct TagTabView: View {

    // TagLinkManager はアプリ全体で1つ（シングルトン）なので、
    // ここは「観測するだけ」の @ObservedObject でよい。
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
        // 状態が変わるときに色と文字がふっと切り替わる。
        // デモで「いま変わった」ことを見せるための演出。
        .animation(.easeInOut(duration: 0.4), value: link.presence)
    }

    // MARK: - 状態カード

    private var statusCard: some View {
        VStack(spacing: 14) {

            // 色だけでなく形でも区別する。
            Image(systemName: presenceIcon)
                .font(.system(size: 64))
                .foregroundStyle(presenceColor)

            Text(presenceText)
                .font(.largeTitle.bold())
                .foregroundStyle(presenceColor)

            Text(lastSeenText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // 最後に確認できてからの経過。
            // 見えていれば 0 付近を行き来し、離れると増え続ける。
            // 判定の閾値に近づいていく様子がそのまま見えるので、
            // 「いま何が起きているか」が説明なしで伝わる。
            if link.isRunning {
                Text("\(Int(link.elapsed)) 秒前に確認")
                    .font(.caption)
                    .foregroundStyle(link.elapsed > 5 ? .orange : .secondary)
                    .monospacedDigit()   // 数字が揺れないように等幅にする
            }

            // 受信回数は検証用の情報なので、詳細ログのときだけ出す。
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

    /// タグの電子ペーパーに出ている内容を映す枠。
    ///
    /// 296×128 の縦横比をそのまま使う。デモでは、電子ペーパーとスマホ画面が
    /// 同時に匿名 → 個人情報へ変わるのを見せたいので、ここは主役級の大きさで置く。
    ///
    /// 中身はサーバーから取得する設計だが、まだ実装していないので枠だけ。
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

    /// 本来は自動で動くべきもの。デモ中にボタンが目立つと説明が要るので、
    /// 下端に小さく置いておく。いずれ設定タブへ移すか、消す。
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

    /// 最終確認時刻の文言。まだ一度も確認できていない場合を分ける。
    private var lastSeenText: String {
        guard let at = link.lastSeenAt else { return "まだ一度も確認できていません" }
        return "最終確認 " + at.formatted(date: .omitted, time: .standard)
    }

    /// 画面全体をうっすら染める。
    /// 平常時はほぼ無色で、離れたときだけ赤みが差す。
    /// 遠くからでも異常が分かるようにするための演出。
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
