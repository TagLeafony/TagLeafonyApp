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

    var body: some View {
        NavigationStack {
            Group {
                if store.contents.isEmpty {
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
                }
            }
        }
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
            }
            .onDelete { store.delete(at: $0) }
        }
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
                Text(content.name)
                    .lineLimit(1)
                Text(content.createdAt.formatted(date: .numeric, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
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
}

#Preview {
    DisplayTabView()
}
