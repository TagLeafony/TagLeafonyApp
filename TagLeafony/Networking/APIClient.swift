//
//  APIClient.swift
//  TagLeafony
//

import Foundation

// ============================================================================
//  サーバー（Cloudflare Worker）と通信する窓口。
//
//  サーバー側（workers.js）の実装に合わせて、認証トークンは
//  Authorization ヘッダーではなく、リクエストのボディ（またはクエリ）の
//  "token" フィールドで送る。
// ============================================================================

enum APIError: Error, LocalizedError {
    case badRequest(String)
    case unauthorized
    case forbidden(String)
    case notFound(String)
    case conflict(String)
    case server(String)
    case network(Error)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .badRequest(let message): return message
        case .unauthorized: return "ログインの有効期限が切れました。もう一度ログインしてください。"
        case .forbidden(let message): return message
        case .notFound(let message): return message
        case .conflict(let message): return message
        case .server(let message): return message
        case .network: return "サーバーに接続できませんでした。通信状況を確認してください。"
        case .decoding: return "サーバーの応答を解釈できませんでした。"
        }
    }
}

final class APIClient {

    static let shared = APIClient()

    private let baseURL = URL(string: "https://tag-app.happy-tanbarin2.workers.dev")!

    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init(session: URLSession = .shared) {
        self.session = session

        encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase

        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    // MARK: - 認証（API A / B）

    func register(email: String, password: String) async throws -> RegisterResponse {
        try await send(.post, path: "/api/register", body: RegisterRequest(email: email, password: password))
    }

    func login(email: String, password: String) async throws -> LoginResponse {
        try await send(.post, path: "/api/login", body: LoginRequest(email: email, password: password))
    }

    // MARK: - デバイス管理（API C / D / E）

    func registerDevice(deviceId: String, deviceName: String?, token: String) async throws -> RegisterDeviceResponse {
        try await send(
            .post, path: "/api/devices",
            body: RegisterDeviceRequest(deviceId: deviceId, deviceName: deviceName, token: token)
        )
    }

    func listDevices(token: String) async throws -> ListDevicesResponse {
        try await send(.get, path: "/api/devices", queryItems: [URLQueryItem(name: "token", value: token)])
    }

    func deleteDevice(deviceId: String, token: String) async throws -> DeleteDeviceResponse {
        try await send(
            .delete, path: "/api/devices/\(deviceId)",
            body: DeleteDeviceRequest(token: token)
        )
    }

    // MARK: - ナノコン向け（API 1）

    /// 認証不要。device_id だけで、アクティブ設定とスケジュール設定のうち
    /// サーバーが「今表示すべき」と判定した画像を取得する。
    func currentImage(deviceId: String) async throws -> CurrentImageResponse {
        try await send(.get, path: "/api/current_image", queryItems: [URLQueryItem(name: "device_id", value: deviceId)])
    }

    // MARK: - 画像管理（API 2 / 3 / 5 / 6 / 7 / 8）

    func uploadImage(deviceId: String, base64Data: String, token: String) async throws -> UploadImageResponse {
        try await send(
            .post, path: "/api/upload_image",
            body: UploadImageRequest(deviceId: deviceId, base64Data: base64Data, token: token)
        )
    }

    func listImages(deviceId: String, token: String) async throws -> ListImagesResponse {
        try await send(
            .get, path: "/api/list_images",
            queryItems: [
                URLQueryItem(name: "device_id", value: deviceId),
                URLQueryItem(name: "token", value: token),
            ]
        )
    }

    func setActiveImage(deviceId: String, imageId: Int, token: String) async throws -> SetActiveImageResponse {
        try await send(
            .post, path: "/api/set_active_image",
            body: SetActiveImageRequest(deviceId: deviceId, imageId: imageId, token: token)
        )
    }

    func deleteImage(deviceId: String, imageId: Int, token: String) async throws -> DeleteImageResponse {
        try await send(
            .delete, path: "/api/delete_image",
            body: DeleteImageRequest(deviceId: deviceId, imageId: imageId, token: token)
        )
    }

    func setScheduledImage(
        deviceId: String, imageIdBefore: Int, imageIdAfter: Int, switchTime: String, token: String
    ) async throws -> SetScheduledImageResponse {
        try await send(
            .post, path: "/api/set_scheduled_image",
            body: SetScheduledImageRequest(
                deviceId: deviceId, imageIdBefore: imageIdBefore, imageIdAfter: imageIdAfter,
                switchTime: switchTime, token: token
            )
        )
    }

    func setFallbackImage(deviceId: String, imageId: Int, token: String) async throws -> SetFallbackImageResponse {
        try await send(
            .post, path: "/api/set_fallback_image",
            body: SetFallbackImageRequest(deviceId: deviceId, imageId: imageId, token: token)
        )
    }

    func getScheduledImage(deviceId: String, token: String) async throws -> GetScheduledImageResponse {
        try await send(
            .get, path: "/api/scheduled_image",
            queryItems: [
                URLQueryItem(name: "device_id", value: deviceId),
                URLQueryItem(name: "token", value: token),
            ]
        )
    }

    func deleteScheduledImage(deviceId: String, token: String) async throws -> DeleteScheduledImageResponse {
        try await send(
            .delete, path: "/api/scheduled_image",
            body: DeleteScheduledImageRequest(deviceId: deviceId, token: token)
        )
    }

    // MARK: - 共通の送受信

    private enum Method: String {
        case get = "GET"
        case post = "POST"
        case delete = "DELETE"
    }

    /// ボディなし（GET、クエリのみ）のリクエスト用。
    private func send<Response: Decodable>(
        _ method: Method,
        path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        try await perform(method: method, path: path, queryItems: queryItems, httpBody: nil)
    }

    /// JSONボディ付きのリクエスト用。
    private func send<Body: Encodable, Response: Decodable>(
        _ method: Method,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: Body
    ) async throws -> Response {
        let httpBody = try encoder.encode(body)
        return try await perform(method: method, path: path, queryItems: queryItems, httpBody: httpBody)
    }

    private func perform<Response: Decodable>(
        method: Method,
        path: String,
        queryItems: [URLQueryItem],
        httpBody: Data?
    ) async throws -> Response {

        var url = baseURL.appendingPathComponent(path)
        if !queryItems.isEmpty, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.queryItems = queryItems
            if let composedURL = components.url {
                url = composedURL
            }
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        if let httpBody {
            request.httpBody = httpBody
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.network(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.network(URLError(.badServerResponse))
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw mapError(statusCode: httpResponse.statusCode, data: data)
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    private func mapError(statusCode: Int, data: Data) -> APIError {
        let message = (try? decoder.decode(ErrorResponse.self, from: data))?.error ?? "エラーが発生しました"
        switch statusCode {
        case 400: return .badRequest(message)
        case 401: return .unauthorized
        case 403: return .forbidden(message)
        case 404: return .notFound(message)
        case 409: return .conflict(message)
        default: return .server(message)
        }
    }
}
