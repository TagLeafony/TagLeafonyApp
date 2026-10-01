//
//  AlertScheduler.swift
//  TagLeafony
//

import Foundation
import UserNotifications

// ============================================================================
//  「タグが離れました」の通知を予約する。
//
//  なぜ通知の予約なのか:
//      アプリはバックグラウンドで数秒しか動かず、そのあとサスペンドされる。
//      サスペンド中は Timer も asyncAfter も止まるので、
//      「最後に見えてから30秒」を自分で測ることができない。
//
//      そこで OS の通知スケジューラに測らせる。
//      予約した通知は、アプリがサスペンドされていても、
//      OS に終了させられていても、時間どおりに発火する。
//
//  仕組み:
//      タグを見つけるたびに、30秒後に発火する通知を予約し直す。
//      同じ識別子で予約すると前の予約が上書きされるので、
//      「予約し直す」ことが「キャンセルする」ことを兼ねる。
//
//          発見 → 30秒後の通知を予約
//          発見 → 予約し直し（前のは消える）
//          発見 → 予約し直し
//           ×  ← タグが見えなくなる
//                最後に予約したものが、30秒後に発火する
//
//  ★守ること★
//      通知が発火したこと ≠ アプリの状態が変わったこと。
//      通知はユーザーへの告知だけを担当する。
//      アプリの状態は TagLinkManager が lastSeenAt から計算し直す。
//      ここを混ぜると、通知を消しただけで状態が食い違う。
//
//  まだやらないこと:
//      - 「これは紛失ではない」ボタン（保留への切り替え）
//        取り消す手段が無いうちは、二段階にしても警告が鳴るだけで
//        ユーザーにできることがない。状態機械と一緒に入れる。
// ============================================================================

final class AlertScheduler {

    static let shared = AlertScheduler()
    private init() {}

    /// 通知の識別子。
    ///
    /// ★同じ識別子で予約し直すと、前の予約が置き換わる★
    /// これがキャンセルの代わりになっている。
    /// 複数のタグに対応するときは、タグごとに別の識別子が要る。
    private let awayIdentifier = "tag.away"

    /// 予約し直す最小間隔（秒）。
    ///
    /// 発見は0.3秒ごとに来る。そのたびに予約すると、
    /// 1秒に3回以上も通知APIを叩くことになり、電池にも悪い。
    ///
    /// 間引くと、発火のタイミングが最大この秒数だけ遅れる。
    /// 「30秒ちょうど」ではなく「25〜30秒」で鳴るようになるが、
    /// 実用上は問題ない範囲。
    private let rearmThrottle: TimeInterval = 5

    /// 最後に予約し直した時刻。間引きの判定に使う。
    private var lastRearmAt: Date?

    /// 通知の許可が下りているか。
    /// 拒否されていても予約自体はエラーにならず、ただ表示されないだけ。
    private(set) var isAuthorized = false

    // MARK: - 許可

    /// 通知の許可を求める。初回に1度だけダイアログが出る。
    ///
    /// 拒否されても他の機能は動く。表示されないだけ。
    func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                    completion?(granted)
                }
            }
    }

    // MARK: - 予約

    /// 「離れました」の通知を予約し直す。
    ///
    /// タグを見つけるたびに呼ぶ。前の予約は自動的に置き換わる。
    ///
    /// - Parameters:
    ///   - seconds: 何秒後に発火させるか（TagLinkManager の awayThreshold）
    ///   - lastSeenAt: 通知の本文に入れる「最後に確認できた時刻」
    /// - Returns: 実際に予約し直したら true。間引かれたら false
    @discardableResult
    func rearm(after seconds: TimeInterval, lastSeenAt: Date) -> Bool {
        // 間引き。前回から一定時間経っていなければ何もしない。
        if let last = lastRearmAt, Date().timeIntervalSince(last) < rearmThrottle {
            return false
        }

        // UNTimeIntervalNotificationTrigger は 0 以下を受け付けない。
        guard seconds > 0 else { return false }

        lastRearmAt = Date()

        let content = UNMutableNotificationContent()
        content.title = "タグが離れました"
        content.body  = "最後に確認できたのは "
            + lastSeenAt.formatted(date: .omitted, time: .shortened)
            + " です"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)

        let request = UNNotificationRequest(
            identifier: awayIdentifier,   // 同じIDなので前の予約を置き換える
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
        return true
    }

    // MARK: - 取り消し

    /// 予約を取り消す。見張りを止めたときに呼ぶ。
    ///
    /// 呼ばないと、停止した後も30秒後に通知が鳴る。
    func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [awayIdentifier])
        lastRearmAt = nil
    }
}
