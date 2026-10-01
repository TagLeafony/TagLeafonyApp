//
//  ContentView.swift
//  TagLeafony
//
//  Created by nomushun on 2026/09/07.
//

import SwiftUI

// ============================================================================
//  アプリの土台。3つのタブを並べるだけ。
//
//  タブにした理由:
//      - 3つとも「やること」が違う（見張る / 作る / 設定する）ので分かれる
//      - 作りかけの画面が階層の奥に埋もれない。全部1タップで届く
//      - 「ホームに何を置くか」を決めずに進められる
//
//  中身のまだ決まっていないタブは、空のまま置いてある。
//  作り込む順番は タグ → 設定 → 表示内容 の予定。
// ============================================================================

struct ContentView: View {
    var body: some View {
        TabView {
            TagTabView()
                .tabItem { Label("タグ", systemImage: "tag") }

            DisplayTabView()
                .tabItem { Label("表示内容", systemImage: "rectangle.on.rectangle") }

            SettingsTabView()
                .tabItem { Label("設定", systemImage: "gearshape") }
        }
    }
}

#Preview {
    // Core Bluetooth はシミュレータで動かない（state が常に .unsupported）ので、
    // プレビューで確認できるのはレイアウトだけ。検証は必ず実機で行う。
    ContentView()
}
