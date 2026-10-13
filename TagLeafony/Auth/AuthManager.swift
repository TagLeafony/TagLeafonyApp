//
//  AuthManager.swift
//  TagLeafony
//

import Combine
import Foundation

// ============================================================================
//  ログイン状態を管理するシングルトン。
//
//  トークンはKeychainに保存し、他のManager（DeviceManager・ContentStoreなど）が
//  APIを呼ぶときに currentToken() で取り出して使う。
//
//  JWTの期限切れはサーバーにしか分からないため、起動時はKeychainに
//  トークンが残っていれば楽観的にログイン済みとして扱う。期限切れの場合は
//  後続のAPI呼び出しが401を返すので、そのとき呼び出し側が handleUnauthorized() を呼ぶ。
// ============================================================================

@MainActor
final class AuthManager: ObservableObject {

    static let shared = AuthManager()

    @Published private(set) var isLoggedIn: Bool
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    @Published private(set) var userId: String?
    @Published private(set) var email: String?

    private let tokenKey = "auth_token"
    private var token: String?

    private init() {
        token = KeychainStore.get(tokenKey)
        isLoggedIn = token != nil
    }

    /// 他のManagerがAPIを呼ぶときに使う。
    func currentToken() -> String? { token }

    // MARK: - ログイン・登録・ログアウト

    func login(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await APIClient.shared.login(email: email, password: password)
            applySession(token: response.token, userId: response.userId, email: response.email)
        } catch {
            errorMessage = message(for: error)
        }
    }

    /// register はトークンを返さないので、成功後に内部で login を呼ぶ。
    func register(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            _ = try await APIClient.shared.register(email: email, password: password)
            let response = try await APIClient.shared.login(email: email, password: password)
            applySession(token: response.token, userId: response.userId, email: response.email)
        } catch {
            errorMessage = message(for: error)
        }
    }

    func logout() {
        token = nil
        userId = nil
        email = nil
        KeychainStore.delete(tokenKey)
        isLoggedIn = false
    }

    /// 401（トークン無効・期限切れ）を受け取った他のManagerから呼ばれる。
    func handleUnauthorized() {
        logout()
    }

    // MARK: - 内部

    private func applySession(token: String, userId: String, email: String) {
        self.token = token
        self.userId = userId
        self.email = email
        KeychainStore.set(token, for: tokenKey)
        isLoggedIn = true
    }

    private func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
