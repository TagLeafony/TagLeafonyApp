//
//  LoginView.swift
//  TagLeafony
//

import SwiftUI

// ============================================================================
//  未ログイン時のルート画面。ログインと新規登録の両方をここで行う。
// ============================================================================

struct LoginView: View {

    @ObservedObject private var auth = AuthManager.shared

    private enum Mode: String, CaseIterable {
        case login = "ログイン"
        case register = "新規登録"
    }

    @State private var mode: Mode = .login
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("モード", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .listRowBackground(Color.clear)
                    .onChange(of: mode) { _, _ in auth.errorMessage = nil }
                }

                Section {
                    TextField("メールアドレス", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("パスワード", text: $password)
                        .textContentType(mode == .login ? .password : .newPassword)
                }

                if let errorMessage = auth.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button(mode == .login ? "ログイン" : "登録する") {
                        submit()
                    }
                    .disabled(!canSubmit || auth.isLoading)
                }
            }
            .navigationTitle("TagLeafony")
            .overlay {
                if auth.isLoading {
                    ProgressView()
                }
            }
        }
    }

    private var canSubmit: Bool {
        !email.isEmpty && !password.isEmpty
    }

    private func submit() {
        Task {
            switch mode {
            case .login:
                await auth.login(email: email, password: password)
            case .register:
                await auth.register(email: email, password: password)
            }
        }
    }
}

#Preview {
    LoginView()
}
