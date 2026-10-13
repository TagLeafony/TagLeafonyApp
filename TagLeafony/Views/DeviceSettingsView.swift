//
//  DeviceSettingsView.swift
//  TagLeafony
//

import SwiftUI

// ============================================================================
//  設定タブの中に置く、デバイス管理画面。
//
//  device_id はQRコードではなく手入力のみ（タグ本体に印字されたIDを打つ想定）。
//  このアプリは1台のみを想定しているので、登録済みなら情報表示＋削除、
//  未登録なら登録フォームのどちらかだけを出す。
// ============================================================================

struct DeviceSettingsView: View {

    @ObservedObject private var deviceManager = DeviceManager.shared

    @State private var deviceId = ""
    @State private var deviceName = ""
    @State private var showDeleteConfirmation = false

    var body: some View {
        Form {
            if let device = deviceManager.device {
                Section("登録済みデバイス") {
                    LabeledContent("device_id", value: device.deviceId)
                    if let name = device.deviceName, !name.isEmpty {
                        LabeledContent("名前", value: name)
                    }
                    LabeledContent("保存されている画像数", value: "\(device.imageCount)")
                }

                Section {
                    Button("デバイスを削除", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                }
            } else {
                Section("デバイスを登録") {
                    TextField("device_id（タグに記載されたID）", text: $deviceId)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    TextField("名前（任意）", text: $deviceName)
                }

                Section {
                    Button("登録する") {
                        register()
                    }
                    .disabled(deviceId.isEmpty || deviceManager.isLoading)
                }
            }

            if let errorMessage = deviceManager.errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("デバイス")
        .overlay {
            if deviceManager.isLoading {
                ProgressView()
            }
        }
        .task {
            await deviceManager.loadDevices()
        }
        .confirmationDialog(
            "このデバイスを削除しますか？",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("削除する", role: .destructive) {
                Task { await deviceManager.deleteDevice() }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("保存されている画像もすべて削除されます。")
        }
    }

    private func register() {
        Task {
            await deviceManager.registerDevice(
                deviceId: deviceId,
                deviceName: deviceName.isEmpty ? nil : deviceName
            )
        }
    }
}

#Preview {
    NavigationStack {
        DeviceSettingsView()
    }
}
