//
//  ScheduleSettingsView.swift
//  TagLeafony
//

import SwiftUI

// ============================================================================
//  設定タブの中に置く、スケジュール設定画面。
//
//  指定した時刻を境に「切り替え前」の画像から「切り替え後」の画像へ
//  自動で切り替わるように設定する（API 6）。
//
//  サーバーには「今設定されているスケジュールを取得する」APIが無いため、
//  この画面は新しく設定するだけのフォームで、現在の設定内容は表示できない。
//  （どの画像がスケジュールに使われているかは、表示内容タブの一覧に付く
//  「スケジュール予定」バッジで確認できる。）
// ============================================================================

struct ScheduleSettingsView: View {

    @ObservedObject private var store = ContentStore.shared

    @State private var beforeId: Int?
    @State private var afterId: Int?
    @State private var switchTime = Date()
    @State private var successMessage: String?

    var body: some View {
        Form {
            if store.contents.count < 2 {
                Section {
                    Text("スケジュールを設定するには、表示内容を2つ以上登録してください。")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("切り替え前後の画像") {
                    Picker("切り替え前", selection: $beforeId) {
                        Text("選択してください").tag(Int?.none)
                        ForEach(store.contents) { content in
                            Text(content.name).tag(Optional(content.id))
                        }
                    }
                    Picker("切り替え後", selection: $afterId) {
                        Text("選択してください").tag(Int?.none)
                        ForEach(store.contents) { content in
                            Text(content.name).tag(Optional(content.id))
                        }
                    }
                }

                Section("切り替え時刻") {
                    DatePicker("時刻", selection: $switchTime)
                }

                if let successMessage {
                    Section {
                        Text(successMessage)
                            .foregroundStyle(.green)
                    }
                }

                if let errorMessage = store.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button("設定する") {
                        submit()
                    }
                    .disabled(!canSubmit || store.isLoading)
                }
            }
        }
        .navigationTitle("スケジュール設定")
        .overlay {
            if store.isLoading {
                ProgressView()
            }
        }
    }

    private var canSubmit: Bool {
        guard let beforeId, let afterId else { return false }
        return beforeId != afterId
    }

    private func submit() {
        guard let beforeId, let afterId else { return }
        successMessage = nil
        Task {
            await store.setSchedule(beforeId: beforeId, afterId: afterId, switchTime: switchTime)
            if store.errorMessage == nil {
                successMessage = "スケジュールを設定しました"
            }
        }
    }
}

#Preview {
    NavigationStack {
        ScheduleSettingsView()
    }
}
