//
//  APIModels.swift
//  TagLeafony
//

import Foundation

// ============================================================================
//  サーバー（Cloudflare Worker）とやり取りするJSONの型。
//
//  サーバー側のJSONキーは snake_case（例: device_id）だが、
//  Swift側は camelCase（例: deviceId）で持つ。
//  変換は APIClient の JSONEncoder/JSONDecoder の
//  convertToSnakeCase / convertFromSnakeCase に任せているので、
//  ここでは Swift らしい名前のまま書けばよい。
// ============================================================================

// MARK: - 共通：エラー応答

/// サーバーがエラー時に返す形 { "error": "..." }
struct ErrorResponse: Decodable {
    let error: String
}

// MARK: - 認証（API A / B）

struct RegisterRequest: Encodable {
    let email: String
    let password: String
}

struct RegisterResponse: Decodable {
    let success: Bool
    let userId: String
    let email: String
    let message: String
}

struct LoginRequest: Encodable {
    let email: String
    let password: String
}

struct LoginResponse: Decodable {
    let success: Bool
    let userId: String
    let email: String
    let token: String
    let message: String
}

// MARK: - デバイス管理（API C / D / E）

struct RegisterDeviceRequest: Encodable {
    let deviceId: String
    let deviceName: String?
    let token: String
}

struct RegisterDeviceResponse: Decodable {
    let success: Bool
    let deviceId: String
    let deviceName: String?
    let ownerUserId: String
    let createdAt: String
    let message: String
}

/// デバイス一覧（API D）の1件分。
struct DeviceDTO: Decodable, Identifiable {
    let deviceId: String
    let deviceName: String?
    let ownerUserId: String
    let createdAt: String
    let imageCount: Int
    let activeImageId: Int?

    var id: String { deviceId }
}

struct ListDevicesResponse: Decodable {
    let success: Bool
    let devices: [DeviceDTO]
    let count: Int
}

struct DeleteDeviceRequest: Encodable {
    let token: String
}

struct DeleteDeviceResponse: Decodable {
    let success: Bool
    let message: String
    let deviceId: String
}

// MARK: - ナノコン向け（API 1）

/// デバイスが「今表示すべき画像」。アクティブ設定とスケジュール設定、
/// どちらを採用するかはサーバー側で switch_time と現在時刻を比較して判定される。
/// mode が "scheduled" のときだけ switchTime、"active" のときだけ setAt が入る。
struct CurrentImageResponse: Decodable {
    let success: Bool
    let imageId: Int?
    let base64Data: String?
    let mode: String?
    let switchTime: String?
    let setAt: String?
    let message: String
}

// MARK: - 画像管理（API 2 / 3 / 5 / 6 / 7 / 8）

struct UploadImageRequest: Encodable {
    let deviceId: String
    let base64Data: String
    let token: String
}

struct UploadImageResponse: Decodable {
    let success: Bool
    let imageId: Int
    let deviceId: String
    let createdAt: String
    let message: String
}

/// 画像一覧（API 3）の1件分。
struct ImageDTO: Decodable, Identifiable {
    let imageId: Int
    let base64Data: String
    let createdAt: String
    let isActive: Bool
    let isScheduled: Bool
    let isFallback: Bool
    let status: String

    var id: Int { imageId }
}

struct ListImagesResponse: Decodable {
    let success: Bool
    let deviceId: String
    let images: [ImageDTO]
    let count: Int
}

struct SetActiveImageRequest: Encodable {
    let deviceId: String
    let imageId: Int
    let token: String
}

struct SetActiveImageResponse: Decodable {
    let success: Bool
    let deviceId: String
    let activeImageId: Int
    let setAt: String
    let message: String
}

struct DeleteImageRequest: Encodable {
    let deviceId: String
    let imageId: Int
    let token: String
}

struct DeleteImageResponse: Decodable {
    let success: Bool
    let deviceId: String
    let imageId: Int
    let message: String
}

struct SetScheduledImageRequest: Encodable {
    let deviceId: String
    let imageIdBefore: Int
    let imageIdAfter: Int
    /// ISO 8601形式の文字列（例: "2024-01-01T14:00:00Z"）。
    let switchTime: String
    let token: String
}

struct SetScheduledImageResponse: Decodable {
    let success: Bool
    let deviceId: String
    let imageIdBefore: Int
    let imageIdAfter: Int
    let switchTime: String
    let setAt: String
    let message: String
}

struct SetFallbackImageRequest: Encodable {
    let deviceId: String
    let imageId: Int
    let token: String
}

struct SetFallbackImageResponse: Decodable {
    let success: Bool
    let deviceId: String
    let fallbackImageId: Int
    let setAt: String
    let message: String
}
