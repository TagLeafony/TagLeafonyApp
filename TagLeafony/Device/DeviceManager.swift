//
//  DeviceManager.swift
//  TagLeafony
//

import Combine
import Foundation

// ============================================================================
//  登録済みデバイスを管理するシングルトン。
//
//  サーバーのAPIは1ユーザーが複数台のデバイスを持てる設計だが、
//  このアプリでは1台のみを想定する。ログイン後にAPI D（一覧）を呼び、
//  返ってきた一覧の先頭を「このアプリが管理するデバイス」として扱う。
// ============================================================================

@MainActor
final class DeviceManager: ObservableObject {

    static let shared = DeviceManager()

    @Published private(set) var device: DeviceDTO?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private init() {}

    /// ログイン後、またはデバイス管理画面を開いたときに呼ぶ。
    func loadDevices() async {
        guard let token = AuthManager.shared.currentToken() else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await APIClient.shared.listDevices(token: token)
            device = response.devices.first
        } catch {
            handle(error)
        }
    }

    func registerDevice(deviceId: String, deviceName: String?) async {
        guard let token = AuthManager.shared.currentToken() else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await APIClient.shared.registerDevice(
                deviceId: deviceId, deviceName: deviceName, token: token
            )
            device = DeviceDTO(
                deviceId: response.deviceId,
                deviceName: response.deviceName,
                ownerUserId: response.ownerUserId,
                createdAt: response.createdAt,
                imageCount: 0,
                activeImageId: nil
            )
        } catch {
            handle(error)
        }
    }

    func deleteDevice() async {
        guard let token = AuthManager.shared.currentToken(), let deviceId = device?.deviceId else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            _ = try await APIClient.shared.deleteDevice(deviceId: deviceId, token: token)
            device = nil
        } catch {
            handle(error)
        }
    }

    /// ログアウト時に呼ぶ。次に別アカウントでログインしたとき、前の情報が残らないようにする。
    func reset() {
        device = nil
        errorMessage = nil
    }

    private func handle(_ error: Error) {
        if let apiError = error as? APIError, case .unauthorized = apiError {
            AuthManager.shared.handleUnauthorized()
            return
        }
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
