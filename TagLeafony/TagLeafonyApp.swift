//
//  TagLeafonyApp.swift
//  TagLeafony
//
//  Created by nomushun on 2026/09/07.
//

import SwiftUI

@main
struct TagLeafonyApp: App {

    // アプリが前面／背面のどちらにいるかを SwiftUI から受け取る。
    //
    // UIApplication.didEnterBackgroundNotification でも取れるが、
    // SwiftUI ライフサイクルのアプリでは scenePhase のほうが確実。
    // 背面での受信頻度を測るための計測用で、BLE の動作には影響しない。
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // ★ここで明示的に触って、起動直後に生成を確定させる★
        //
        // 復元（willRestoreState）はアプリ起動の非常に早い段階で配送される。
        // その時点で CBCentralManager が作られていないと、復元イベントは
        // 届かずに捨てられる。エラーも警告も出ないので気づけない。
        _ = TagLinkManager.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .background:
                        // ホーム画面に戻った、または画面がロックされた
                        TagLinkManager.shared.enterBackground()
                    case .active:
                        // 前面に戻ってきた
                        TagLinkManager.shared.enterForeground()
                    default:
                        // .inactive は前面と背面の移行の途中。何もしない。
                        break
                    }
                }
        }
    }
}
