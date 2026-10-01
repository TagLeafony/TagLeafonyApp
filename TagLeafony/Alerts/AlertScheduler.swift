//
//  AlertScheduler.swift
//  TagLeafony
//

import Foundation
import UserNotifications

// ============================================================================
//  「タグが離れました」の通知を予約
//  タグを見つけるたびに,30秒後に発火する通知を予約し直す
//
//  発見 → 30秒後の通知を予約
//  発見 → 予約し直し（前のは消える）
//  発見 → 予約し直し
//           ×  ← タグが見えなくなる
//                最後に予約したものが、30秒後に発火する
// ============================================================================

final class AlertScheduler {

    static let shared = AlertScheduler()
    private init() {}

    // 通知の識別子
    private let awayIdentifier = "tag.away"

    // 予約し直す最小間隔
    private let rearmThrottle: TimeInterval = 5

    // 最後に予約し直した時刻
    private var lastRearmAt: Date?

    // 通知の許可が下りているか。
    private(set) var isAuthorized = false

    // MARK: - 許可

    // 通知の許可を求める,初回に1度だけダイアログが出る
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

    // 「離れました」の通知を予約し直す
    @discardableResult
    func rearm(after seconds: TimeInterval, lastSeenAt: Date) -> Bool {
        // 間引き,前回から一定時間経っていなければ何もしない
        if let last = lastRearmAt, Date().timeIntervalSince(last) < rearmThrottle {
            return false
        }

        // UNTimeIntervalNotificationTriggerは0以下を受け付けない。
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

    // 予約を取り消す
    func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [awayIdentifier])
        lastRearmAt = nil
    }
}
