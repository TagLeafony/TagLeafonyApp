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
//  サーバー（current_image）は switch_time を過ぎた後も、スケジュールの行が
//  残っている限りそれを優先してしまい、アクティブ設定に戻す手段が無かった。
//  そのため、現在の設定を確認できるAPI 9・解除できるAPI 10を追加してもらい、
//  この画面で「今の設定を見る」「フォームに呼び出して直す」「削除する」を行う。
// ============================================================================

struct ScheduleSettingsView: View {

    @ObservedObject private var store = ContentStore.shared

    @State private var beforeId: Int?
    @State private var afterId: Int?
    @State private var switchTime = Date()

    var body: some View {
        Form {
            if let schedule = store.currentSchedule {
                Section("現在の設定") {
                    LabeledContent("切り替え前", value: name(for: schedule.beforeId))
                    LabeledContent("切り替え後", value: name(for: schedule.afterId))
                    LabeledContent("切り替え時刻", value: schedule.switchTime.formatted(date: .numeric, time: .shortened))
                }

                Section {
                    Button("スケジュールを削除", role: .destructive) {
                        clear()
                    }
                    .disabled(store.isLoading)
                }
            }

            if store.contents.count < 2 {
                Section {
                    Text("スケジュールを設定するには、表示内容を2つ以上登録してください。")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("新規スケジュールの設定") {
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
                    DatePicker("切り替え時刻", selection: $switchTime)
                }

                if let errorMessage = store.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button(store.currentSchedule == nil ? "設定する" : "この内容で更新する") {
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
        .task {
            await store.loadSchedule()
            applyCurrentScheduleToForm()
        }
    }

    private var canSubmit: Bool {
        guard let beforeId, let afterId else { return false }
        return beforeId != afterId
    }

    private func name(for imageId: Int) -> String {
        store.contents.first(where: { $0.id == imageId })?.name ?? "不明な画像"
    }

    /// サーバーに今設定されている内容を、フォームの初期値として反映する。
    /// すでに手で触っている場合は上書きしない。
    private func applyCurrentScheduleToForm() {
        guard let schedule = store.currentSchedule, beforeId == nil, afterId == nil else { return }
        beforeId = schedule.beforeId
        afterId = schedule.afterId
        switchTime = schedule.switchTime
    }

    private func submit() {
        guard let beforeId, let afterId else { return }
        Task {
            await store.setSchedule(beforeId: beforeId, afterId: afterId, switchTime: switchTime)
        }
    }

    private func clear() {
        Task {
            await store.clearSchedule()
            beforeId = nil
            afterId = nil
        }
    }
}

#Preview {
    NavigationStack {
        ScheduleSettingsView()
    }
}
