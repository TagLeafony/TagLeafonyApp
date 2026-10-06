//
//  DisplayEditorView.swift
//  TagLeafony
//

import PhotosUI
import SwiftUI

// ============================================================================
//  表示内容を作る・直す画面
// ============================================================================

struct DisplayEditorView: View {

    /// 直すときは既存のものを渡す,新規なら nil
    let editing: DisplayContent?

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = ContentStore.shared

    private enum Source: String, CaseIterable {
        case text  = "文字"
        case photo = "写真"
        case test  = "市松模様"
    }

    @State private var source: Source = .text
    @State private var name = ""

    // 文字
    @State private var text = "山田 太郎\n090-1234-5678"

    // 写真
    @State private var pickerItem: PhotosPickerItem?
    @State private var pickedImage: UIImage?
    @State private var useDither = true
    @State private var threshold: Double = 128

    // 写真の置き方
    @State private var transform = ImageBinarizer.Transform.identity

    // 指を動かしている最中の差分
    @GestureState private var dragDelta: CGSize = .zero
    @GestureState private var pinchDelta: CGFloat = 1

    // 指の動きを足し込んだ,いま表示すべき置き方
    private var liveTransform: ImageBinarizer.Transform {
        ImageBinarizer.Transform(
            scale: transform.scale * pinchDelta,
            offset: CGSize(width: transform.offset.width + dragDelta.width,
                           height: transform.offset.height + dragDelta.height)
        )
    }

    // 画面に出す 296×128 の白黒画像
    private var rendered: UIImage? {
        switch source {
        case .text:
            return TextRenderer.render(text)
        case .test:
            return DisplayBitmap.testPattern()
        case .photo:
            guard let pickedImage else { return nil }
            return ImageBinarizer.render(
                pickedImage,
                transform: liveTransform,
                method: useDither ? .dither : .threshold(UInt8(threshold))
            )
        }
    }

    private var packed: Data? { rendered.flatMap { DisplayBitmap.pack($0) } }

    var body: some View {
        Form {
            Section {
                Picker("作り方", selection: $source) {
                    ForEach(Source.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section {
                preview
                sizeInfo
            } header: {
                Text("プレビュー")
            } footer: {
                if source == .photo && pickedImage != nil {
                    Text("ドラッグで位置、ピンチで大きさを変えられます。枠からはみ出した部分は切れます。")
                }
            }

            switch source {
            case .text:  textSection
            case .photo: photoSection
            case .test:  testSection
            }

            Section("名前") {
                TextField("一覧での表示名", text: $name)
            }
        }
        .navigationTitle(editing == nil ? "新しい表示内容" : "表示内容を直す")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }
                    .disabled(packed == nil)
            }
        }
        .onAppear(perform: loadExisting)
    }

    // MARK: - 保存

    private func save() {
        guard let packed else { return }

        let content = DisplayContent(
            id: editing?.id ?? UUID(),              // 直すときは id を引き継ぐ
            name: name.isEmpty ? suggestedName : name,
            createdAt: editing?.createdAt ?? Date(),
            bitmapBase64: packed.base64EncodedString(),
            sourceText: source == .text ? text : nil
        )

        store.save(content)
        dismiss()
    }

    // 名前を入れなかったときの既定
    private var suggestedName: String {
        switch source {
        case .text:
            let firstLine = text.split(separator: "\n").first.map(String.init) ?? ""
            return firstLine.isEmpty ? "文字" : firstLine
        case .photo: return "写真"
        case .test:  return "市松模様"
        }
    }

    // 直すときに,保存してある内容を画面へ戻す
    private func loadExisting() {
        guard let editing, name.isEmpty else { return }
        name = editing.name
        if let sourceText = editing.sourceText {
            source = .text
            text = sourceText
        }
    }

    // MARK: - プレビュー

    // 296×128 をそのままの比率で見せる
    @ViewBuilder
    private var preview: some View {
        if let rendered {
            VStack(spacing: 6) {
                GeometryReader { geo in
                    // 画面上のポイント → 296×128 の座標 への換算係数
                    let factor = CGFloat(DisplayBitmap.width) / max(geo.size.width, 1)

                    Image(uiImage: rendered)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .border(.secondary)
                        .gesture(source == .photo ? dragGesture(factor: factor) : nil)
                        .simultaneousGesture(source == .photo ? pinchGesture() : nil)
                }
                .aspectRatio(
                    CGFloat(DisplayBitmap.width) / CGFloat(DisplayBitmap.height),
                    contentMode: .fit
                )

                Text("\(DisplayBitmap.width) × \(DisplayBitmap.height)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } else {
            ContentUnavailableView(
                "写真が選ばれていません",
                systemImage: "photo",
                description: Text("下の「写真を選ぶ」から選んでください。")
            )
        }
    }

    private func dragGesture(factor: CGFloat) -> some Gesture {
        DragGesture()
            .updating($dragDelta) { value, state, _ in
                state = CGSize(width: value.translation.width * factor,
                               height: value.translation.height * factor)
            }
            .onEnded { value in
                transform.offset.width  += value.translation.width * factor
                transform.offset.height += value.translation.height * factor
            }
    }

    private func pinchGesture() -> some Gesture {
        MagnifyGesture()
            .updating($pinchDelta) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                transform.scale *= value.magnification
            }
    }

    // タグへ送るときのデータ量
    private var sizeInfo: some View {
        if let packed, let rendered {
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("1bpp", value: "\(packed.count) バイト")
                LabeledContent("Base64", value: "\(packed.base64EncodedString().count) 文字")
                if let png = rendered.pngData() {
                    LabeledContent("PNG（参考）", value: "\(png.count) バイト")
                }
            }
            .font(.caption)
            .monospacedDigit()
        }
        return EmptyView()
    }

    // MARK: - 文字

    private var textSection: some View {
        Section("文字") {
            TextEditor(text: $text)
                .frame(minHeight: 100)
        }
    }

    // MARK: - 写真

    @ViewBuilder
    private var photoSection: some View {
        Section("写真") {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label(pickedImage == nil ? "写真を選ぶ" : "写真を変える",
                      systemImage: "photo.on.rectangle")
            }
            .onChange(of: pickerItem) { _, item in
                Task { await load(item) }
            }

            if pickedImage != nil {
                Button("位置と大きさをリセット") { applyFit(.contain) }
            }
        }

        if pickedImage != nil {
            Section {
                Toggle("ディザで濃淡を出す", isOn: $useDither)

                if !useDither {
                    VStack(alignment: .leading) {
                        Text("しきい値 \(Int(threshold))")
                            .font(.caption)
                            .monospacedDigit()
                        Slider(value: $threshold, in: 0...255, step: 1)
                    }
                }
            } footer: {
                Text(useDither
                     ? "黒い点の密度で濃淡を表現します。新聞の網点と同じ考え方で、写真に向きます。"
                     : "明るさで白黒を一刀両断に分けます。ロゴや線画に向きます。真っ黒・真っ白になったらスライダーで調整してください。")
            }
        }
    }

    private func applyFit(_ mode: ImageBinarizer.Fit) {
        guard let pickedImage else { return }
        transform = ImageBinarizer.Transform(
            scale: ImageBinarizer.fitScale(for: pickedImage, mode: mode),
            offset: .zero
        )
    }

    private func load(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        pickedImage = image
        applyFit(.contain)   // まず全体が見える状態から始める
    }

    // MARK: - 市松模様

    private var testSection: some View {
        Section {
            EmptyView()
        } footer: {
            Text("ビットの並べ方の確認用です。保存してタグに出し、きれいな市松になれば合っています。縞模様ならパックの向き、白黒が逆なら極性、上下逆なら反転の設定が違います。左上の黒い帯で向きも分かります。")
        }
    }
}

#Preview {
    NavigationStack {
        DisplayEditorView(editing: nil)
    }
}
