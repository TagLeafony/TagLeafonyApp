//
//  DisplayContent.swift
//  TagLeafony
//

import Combine
import Foundation
import UIKit

// ============================================================================
//  登録した表示内容の、1件ぶんのデータ。
//
//  本体（bitmapBase64）と有効/無効の情報（isActive）はサーバーが正。
//  name と sourceText はサーバーのスキーマに存在しないフィールドなので、
//  ContentStore がローカルだけで持つ対応表（image_id → LocalMeta）から補う。
// ============================================================================

struct DisplayContent: Identifiable, Equatable {

    /// サーバー側の image_id。
    var id: Int

    /// 一覧で見分けるための名前。サーバーには保存されない。
    var name: String

    var createdAt: Date

    /// 1bpp に詰めたものを Base64 にした文字列。タグへ送るのも、サーバーに保存するのもこれ。
    var bitmapBase64: String

    /// 文字から作った場合の元の文字列。写真から作った場合は nil。サーバーには保存されない。
    var sourceText: String?

    /// このデバイスで現在表示中（アクティブ）かどうか。
    var isActive: Bool

    /// スケジュール（切り替え前/切り替え後のどちらか）に使われているかどうか。
    var isScheduled: Bool

    /// BLE再接続時に表示するフォールバック画像として設定されているかどうか。
    var isFallback: Bool

    /// 保存しているデータから画像に戻す。
    var image: UIImage? {
        DisplayBitmap.unpack(base64: bitmapBase64)
    }
}

// ============================================================================
//  表示内容の保管庫。
//
//  サーバー（list_images / upload_image / set_active_image / delete_image）と同期する。
//  この4つのAPIには「既存画像の更新」が無いため、「直す」は内部的に
//  delete_image → upload_image の2段階で実現している（replace(oldId:...)）。
// ============================================================================

@MainActor
final class ContentStore: ObservableObject {

    static let shared = ContentStore()

    @Published private(set) var contents: [DisplayContent] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    /// name・sourceText はサーバーに保存されないので、端末内だけで持つ対応表。
    private struct LocalMeta: Codable {
        var name: String
        var sourceText: String?
    }

    private var localMeta: [Int: LocalMeta] = [:]

    /// 保存先のファイル。Documents の下に JSON で置く。
    private let localMetaFileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("display-content-local-meta.json")
    }()

    private init() {
        loadLocalMeta()
    }

    // MARK: - サーバーとの同期

    /// 一覧を取り直す。デバイスが未登録なら空のまま（エラー扱いはしない）。
    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let deviceId = DeviceManager.shared.device?.deviceId,
              let token = AuthManager.shared.currentToken()
        else {
            contents = []
            return
        }

        do {
            let response = try await APIClient.shared.listImages(deviceId: deviceId, token: token)
            contents = response.images.map(makeContent)
        } catch {
            handle(error)
        }
    }

    /// 新しい表示内容をアップロードする。
    func upload(name: String, bitmapBase64: String, sourceText: String?) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let (deviceId, token) = requireDeviceAndToken() else { return }

        do {
            let response = try await APIClient.shared.uploadImage(
                deviceId: deviceId, base64Data: bitmapBase64, token: token
            )
            localMeta[response.imageId] = LocalMeta(name: name, sourceText: sourceText)
            persistLocalMeta()
            await refresh()
        } catch {
            handle(error)
        }
    }

    /// 既存の内容を直す。
    ///
    /// このAPIには「更新」が無く、新規作成（API 2）と削除（API 7）しかない。
    /// そのため「直す」は、旧データを削除してから新しいデータをアップロードする形で実現する。
    /// 見た目は上書き保存だが、サーバー上では image_id が変わる。
    func replace(oldId: Int, name: String, bitmapBase64: String, sourceText: String?) async {
        await delete(id: oldId)
        await upload(name: name, bitmapBase64: bitmapBase64, sourceText: sourceText)
    }

    /// 通常表示する画像として設定する。
    func setActive(_ content: DisplayContent) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let (deviceId, token) = requireDeviceAndToken() else { return }

        do {
            _ = try await APIClient.shared.setActiveImage(deviceId: deviceId, imageId: content.id, token: token)
            await refresh()
        } catch {
            handle(error)
        }
    }

    /// BLE再接続時に表示するフォールバック画像として設定する。
    func setFallback(_ content: DisplayContent) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let (deviceId, token) = requireDeviceAndToken() else { return }

        do {
            _ = try await APIClient.shared.setFallbackImage(deviceId: deviceId, imageId: content.id, token: token)
            await refresh()
        } catch {
            handle(error)
        }
    }

    /// 指定した時刻に before → after へ自動で切り替わるよう設定する。
    func setSchedule(beforeId: Int, afterId: Int, switchTime: Date) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let (deviceId, token) = requireDeviceAndToken() else { return }

        do {
            _ = try await APIClient.shared.setScheduledImage(
                deviceId: deviceId, imageIdBefore: beforeId, imageIdAfter: afterId,
                switchTime: ISO8601DateFormatter().string(from: switchTime), token: token
            )
            await refresh()
        } catch {
            handle(error)
        }
    }

    func delete(_ content: DisplayContent) async {
        await delete(id: content.id)
    }

    /// スワイプ削除から呼ばれる。
    func delete(at offsets: IndexSet) async {
        for index in offsets.sorted(by: >) where contents.indices.contains(index) {
            await delete(id: contents[index].id)
        }
    }

    // MARK: - 内部

    private func delete(id: Int) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let (deviceId, token) = requireDeviceAndToken() else { return }

        do {
            _ = try await APIClient.shared.deleteImage(deviceId: deviceId, imageId: id, token: token)
            localMeta.removeValue(forKey: id)
            persistLocalMeta()
            await refresh()
        } catch {
            handle(error)
        }
    }

    private func requireDeviceAndToken() -> (deviceId: String, token: String)? {
        guard let deviceId = DeviceManager.shared.device?.deviceId else {
            errorMessage = "デバイスが登録されていません。設定タブでデバイスを登録してください。"
            return nil
        }
        guard let token = AuthManager.shared.currentToken() else {
            errorMessage = "ログインの有効期限が切れました。もう一度ログインしてください。"
            return nil
        }
        return (deviceId, token)
    }

    private func makeContent(from image: ImageDTO) -> DisplayContent {
        let meta = localMeta[image.imageId]
        return DisplayContent(
            id: image.imageId,
            name: meta?.name ?? image.status,
            createdAt: Self.parseDate(image.createdAt),
            bitmapBase64: image.base64Data,
            sourceText: meta?.sourceText,
            isActive: image.isActive,
            isScheduled: image.isScheduled,
            isFallback: image.isFallback
        )
    }

    private func handle(_ error: Error) {
        if let apiError = error as? APIError, case .unauthorized = apiError {
            AuthManager.shared.handleUnauthorized()
            return
        }
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    // MARK: - 日付の解釈

    // サーバー（JSの toISOString()）はミリ秒付きのISO8601を返すため、
    // 標準オプションのISO8601DateFormatterだけでは解釈できず nil になることがある。
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainFormatter = ISO8601DateFormatter()

    private static func parseDate(_ string: String) -> Date {
        fractionalFormatter.date(from: string) ?? plainFormatter.date(from: string) ?? Date()
    }

    // MARK: - ローカルのみの対応表（name・sourceText）の読み書き

    private func loadLocalMeta() {
        guard let data = try? Data(contentsOf: localMetaFileURL),
              let decoded = try? JSONDecoder().decode([Int: LocalMeta].self, from: data)
        else { return }
        localMeta = decoded
    }

    private func persistLocalMeta() {
        guard let data = try? JSONEncoder().encode(localMeta) else { return }
        try? data.write(to: localMetaFileURL, options: .atomic)
    }
}
