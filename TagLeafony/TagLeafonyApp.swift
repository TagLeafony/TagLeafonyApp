//
//  TagLeafonyApp.swift
//  TagLeafony
//
//  Created by nomushun on 2026/09/07.
//

import SwiftUI

@main
struct TagLeafonyApp: App {

    // アプリが前面／背面のどちらにいるかを SwiftUI から受け取る
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            // ログイン済みかどうかで画面を切り替える。
            // TagLinkManager.shared に最初に触れるのはログイン後（RootView → ContentView → TagTabView）
            // になるので、ここでは明示的に生成しない。
            RootView()
                .onChange(of: scenePhase) { _, phase in
                    // 未ログイン中は TagLinkManager.shared に触れない
                    // （触れた時点でBLE監視が生成されてしまうため）
                    guard AuthManager.shared.isLoggedIn else { return }

                    switch phase {
                    case .background:
                        // ホーム画面に戻った,または画面がロックされた
                        TagLinkManager.shared.enterBackground()
                    case .active:
                        // 前面に戻ってきた
                        TagLinkManager.shared.enterForeground()
                    default:
                        // .inactive は前面と背面の移行の途中
                        break
                    }
                }
        }
    }
}
