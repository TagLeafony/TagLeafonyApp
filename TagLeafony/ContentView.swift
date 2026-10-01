//
//  ContentView.swift
//  TagLeafony
//
//  Created by nomushun on 2026/09/07.
//

import SwiftUI

// ============================================================================
//  アプリの土台。3つのタブを並べるだけ
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
    ContentView()
}
