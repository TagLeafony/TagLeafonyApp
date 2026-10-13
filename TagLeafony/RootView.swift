//
//  RootView.swift
//  TagLeafony
//

import SwiftUI

// ============================================================================
//  アプリの入口。ログイン状態によって表示する画面を切り替える。
//
//  ContentView（タブ画面）が描画されるのはログイン後だけなので、
//  その中でTagLinkManager.sharedに最初に触れるタイミングも
//  自然とログイン後まで遅れる（＝未ログイン中はBLE監視が始まらない）。
//  TagLinkManager.swift自体はこのために変更していない。
// ============================================================================

struct RootView: View {

    @ObservedObject private var auth = AuthManager.shared

    var body: some View {
        Group {
            if auth.isLoggedIn {
                ContentView()
            } else {
                LoginView()
            }
        }
        // ログイン済みの状態でこの画面が出た瞬間（起動時にKeychainから復元された場合も含む）と、
        // ログイン状態がtrueに変わった瞬間の両方で実行される。
        .task(id: auth.isLoggedIn) {
            guard auth.isLoggedIn else { return }
            await DeviceManager.shared.loadDevices()
        }
        .onChange(of: auth.isLoggedIn) { _, loggedIn in
            // ここで呼ぶのはログアウト時のみ。
            // ログインしたことが一度もなければこのonChangeは発火しないため、
            // TagLinkManager.sharedに触れて誤って先に生成してしまうことはない。
            if !loggedIn {
                TagLinkManager.shared.stop()
                DeviceManager.shared.reset()
            }
        }
    }
}

#Preview {
    RootView()
}
