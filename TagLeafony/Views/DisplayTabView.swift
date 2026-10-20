//
//  DisplayTabView.swift
//  TagLeafony
//

import SwiftUI

// ============================================================================
//  「表示内容」タブの入口。登録済みの一覧を出す。
// ============================================================================

struct DisplayTabView: View {

    @ObservedObject private var store = ContentStore.shared
    @ObservedObject private var deviceManager = DeviceManager.shared

    var body: some View {
        NavigationStack {
            Group {
                if deviceManager.device == nil {
                    noDeviceState
                } else if store.contents.isEmpty && !store.isLoading {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("表示内容")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        DisplayEditorView(editing: nil)
                    } label: {
                        Label("新しく作る", systemImage: "plus")
                    }
                    .disabled(deviceManager.device == nil)
                }
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        ScheduleSettingsView()
                    } label: {
                        Label("スケジュール設定", systemImage: "clock")
                    }
                    .disabled(deviceManager.device == nil || store.contents.count < 2)
                }
            }
        }
        .task { await store.refresh() }
        .alert("エラー", isPresented: errorBinding) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )
    }

    // MARK: - 一覧

    private var list: some View {
        List {
            ForEach(store.contents) { content in
                NavigationLink {
                    DisplayEditorView(editing: content)
                } label: {
                    row(content)
                }
                .swipeActions(edge: .leading) {
                    if !content.isActive {
                        Button("表示") {
                            Task { await store.setActive(content) }
                        }
                        .tint(.green)
                    }
                    if !content.isFallback {
                        Button("接続回復用") {
                            Task { await store.setFallback(content) }
                        }
                        .tint(.orange)
                    }
                }
            }
            .onDelete { offsets in
                Task { await store.delete(at: offsets) }
            }
        }
        .refreshable { await store.refresh() }
    }

    private func row(_ content: DisplayContent) -> some View {
        HStack(spacing: 12) {
            // 296×128 の比率のまま小さく出す
            Group {
                if let image = content.image {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    // 復元に失敗した場合
                    Rectangle().fill(.quaternary)
                }
            }
            .frame(width: 92, height: 40)
            .border(.quaternary)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(content.name)
                        .lineLimit(1)

                    if content.isActive {
                        badge("表示中", color: .green)
                    }
                    if content.isScheduled {
                        badge("スケジュール設定中", color: .blue)
                    }
                    if content.isFallback {
                        badge("接続回復用", color: .orange)
                    }
                }
                Text(content.createdAt.formatted(date: .numeric, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - 空のとき

    private var emptyState: some View {
        ContentUnavailableView {
            Label("表示内容がありません", systemImage: "rectangle.on.rectangle")
        } description: {
            Text("タグに表示する文字や写真を登録します。")
        } actions: {
            NavigationLink {
                DisplayEditorView(editing: nil)
            } label: {
                Text("新しく作る")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - デバイス未登録のとき

    private var noDeviceState: some View {
        ContentUnavailableView {
            Label("デバイスが未登録です", systemImage: "tag.slash")
        } description: {
            Text("設定タブの「デバイス管理」から、タグのdevice_idを登録してください。")
        }
    }
}

#Preview {
    DisplayTabView()
}
