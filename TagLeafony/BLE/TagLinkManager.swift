//
//  TagLinkManager.swift
//  TagLeafony
//
//  Created by nomushun on 2026/09/07.
//

import Combine  // ObservableObject と @Published 用
import CoreBluetooth    // BLE用
import Foundation   // Date / TimeInterval / Data / Timer / RunLoop 用

// ============================================================
// タグ（Leafony AP02）が近くにあるかどうかをBLEを用いて監視・判定するクラス
// ------------------------------------------------------------
// 常にスキャンし、アドバタイズを受け取るたび（didDiscover）に記録し
// 最後に見えてからの経過時間が閾値（30秒）を超えたら「離れた」と判定する
// ============================================================

final class TagLinkManager: NSObject, ObservableObject {
    
    static let shared = TagLinkManager()
    
    // MARK: - UUIDと識別子
    // タグを識別するためのサービスUUID
    private let serviceUUID = CBUUID(string: "4FAFC201-1FB5-459E-8FCC-C5C9C331914B")
    
    // 疎通確認用のキャラクタリスティックUUID
    private let checkUUID = CBUUID(string: "4FAFC202-1FB5-459E-8FCC-C5C9C331914B")
    
    // 復元用の識別子
    private let restoreIdentifier = "jp.tagleafony.app.central"
    
    
    // MARK: - 調整用パラメータ
    // 離れたと判断する閾値
    private let awayThreshold: TimeInterval = 30
    
    // タグへの疎通確認の間隔
    private let checkInterval: TimeInterval = 10
    
    // 接続後の後始末までの猶予
    private let connectTimeout: TimeInterval = 12
    
    // 発見ログを出す最小間隔
    private let discoverLogGap: TimeInterval = 2
    
    
    // MARK: - 画面に出す状態
    // 見張りが走っているかの確認,開始・停止ボタンの表示切り替えに使う
    @Published private(set) var isRunning = false
    
    // タグがどう見えているか
    enum Presence {
        case unknown   // まだ一度も見つけていない
        case present   // 見えている
        case away      // 閾値を超えて見えなくなった
    }
    
    @Published private(set) var presence: Presence = .unknown
    
    // 最後にタグを確認できた時刻,nilなら一度も確認できていない
    @Published private(set) var lastSeenAt: Date?
    
    // 最後に確認できてからの経過秒数,uiTimerが毎秒更新
    @Published private(set) var elapsed: TimeInterval = 0
    
    // 起動してから何回アドバタイズを受け取ったか
    @Published private(set) var discoverCount = 0
    
    // 画面に出すログ
    @Published private(set) var logs: [String] = []
    
    // 検証用の細かいログの切り替え
    @Published var verboseLogging = false
    
    
    // MARK: - 内部の状態
    // BLEの司令塔,initで作り以後ずっと使い回す
    private var central: CBCentralManager!
    
    // いま接続処理中のタグ
    //
    // 重要1 必ずプロパティで強参照を持つこと
    // didDiscoverで受け取ったCBPeripheralをローカル変数のままにすると
    // メソッドを抜けた時点で解放され,connectが何のエラーも出さずに失敗する
    //
    // 重要2 これがnilかどうかが「いま接続処理中か」の目印になる
    // スキャンを止めないので,接続している最中にもdidDiscoverが飛んでくる
    // nilでないあいだは新しい接続を始めない
    private var tag: CBPeripheral?
    
    // 最後にチェックを試みた時刻,checkIntervalの判定に用いる
    private var lastCheckAt: Date?
    
    // 最後に発見ログを出した時刻,discoverLogGapの判定に用いる
    private var lastDiscoverLogAt: Date?
    
    // 見張りを開始した時刻
    private var startedAt: Date?
    
    // 「見えていません」のログを最後に出した時刻
    // 沈黙が続いていることを一定間隔で知らせ,タイマーが生きていることも示す
    private var lastSilenceLogAt: Date?
    
    // 一度でもstart()されたか,初回だけ自動開始するために使う
    private var hasAutoStarted = false
    
    // 後始末のasyncAfterが,古い接続に対して発火しないよう照合
    private var connectAttempt = 0
    
    // 前面で経過時間を更新するためのタイマー
    // 背面での告知は markSeen() が予約するローカル通知が担う
    private var uiTimer: Timer?
    
    
    // MARK: - 初期化
    private override init() {
        super.init()
        
        // CBCentralManagerを作ると少し遅れてcentralManagerDidUpdateStateが呼ばれる
        // 作った直後のstateは.unknownなので,ここで即座にスキャンを始めることはしない
        //
        // CBCentralManagerOptionRestoreIdentifierKeyを渡すと
        // アプリが終了させられた後でもBLEイベントで起こしてもらえるようになる
        // (Info.plistのUIBackgroundModesにbluetooth-centralが入ってる前提)
        central = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionRestoreIdentifierKey: restoreIdentifier]
        )
        
        // BLEの起動ログ
        log("起動")
    }
    
    
    // MARK: - 前面／背面の記録（計測用）
    // ログの空白が「背面だったから」なのか「電波が途切れたから」なのかを区別するための目印
    // 呼び出し元はTagLeafonyAppのscenePhase

    func enterBackground() { log("▼ バックグラウンドへ") }
    func enterForeground() { log("▲ フォアグラウンドへ") }
    
    
    // MARK: - 開始・停止（画面のボタンから呼ぶ）
    // 見張り開始
    func start() {
        guard !isRunning else { return }   // 二重起動よけ

        isRunning = true
        presence = .unknown
        startedAt = Date()
        lastSilenceLogAt = nil
        log("開始（\(Int(awayThreshold))秒見えなければ離れたと判定 / チェック間隔\(Int(checkInterval))秒 = タグ側閾値の1/3）")
        
        // 通知の許可を求める
        AlertScheduler.shared.requestAuthorization { [weak self] granted in
            self?.log(granted ? "通知の許可あり" : "通知が許可されていません（背面で気づけません）")
        }

        startScan()
        startUITimer()
    }
    
    // 見張り停止
    func stop() {
        isRunning = false
        // 見張っていないので「分からない」に戻す
        // 戻さないと,停止後も「近くにあります」と表示され続ける
        presence = .unknown

        central.stopScan()
        cleanUpConnection()

        uiTimer?.invalidate()
        uiTimer = nil
        
        // 予約を取り消す忘れると、止めたあとも30秒後に通知が鳴る
        AlertScheduler.shared.cancel()

        log("停止")
    }
    
    
    // MARK: - スキャン
    // スキャンを開始する,一度呼んだら止めない
    // 呼ばれる場所は3つ:
    //   1. start()（ユーザーが開始ボタンを押した）
    //   2. Bluetooth が使えるようになったとき
    //   3. 復元されたとき
    private func startScan() {
        guard isRunning, central.state == .poweredOn else { return }
        
        central.scanForPeripherals(
            withServices: [serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        
        log("スキャン開始（止めずに回し続ける）")
    }
    
    
    // MARK: - 在の記録
    // タグを確認できたことを記録
    // アドバタイズを受け取ったときorチェックが通ったときに呼ぶ
    private func markSeen() {
        let now = Date()
        lastSeenAt = now
        elapsed = 0
        lastSilenceLogAt = nil

        switch presence {
        case .away:
            log("★ 戻ってきた")
        case .unknown:
            log("★ 最初の発見")
        case .present:
            break   // 見え続けているだけログは出さない
        }
        presence = .present
        
        // 背面での判定
        // 「30秒後に鳴る通知」を予約し直す
        if AlertScheduler.shared.rearm(after: awayThreshold, lastSeenAt: now) {
            log("通知を予約し直した（\(Int(awayThreshold))秒後）", verbose: true)
        }
    }
    
    
    // MARK: - 不在の判定（前面の表示用）
    // 経過時間を毎秒更新し,閾値を超えたら画面の表示を「離れた」に変更
    // 背面ではこれが動かないので,ユーザーへの告知はmarkSeen()で予約しているローカル通知が担う
    
    private func startUITimer() {
        uiTimer?.invalidate()
        
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        
        RunLoop.main.add(timer, forMode: .common)
        uiTimer = timer
    }
    
    // 1秒ごとの判定
    private func tick() {
        guard isRunning else { return }

        // 経過時間の起点
        // まだ一度も見つけていなければ,開始時刻から測る
        guard let reference = lastSeenAt ?? startedAt else { return }

        elapsed = Date().timeIntervalSince(reference)

        // 閾値を超えたら離れた判定
        // まだ一度も見つけていない場合（.unknown）も,ここで.awayに落とす
        if elapsed > awayThreshold, presence != .away {
            presence = .away
            log("★ 離れたと判定（\(Int(elapsed))秒 見えず）")
        }

        // 沈黙が続いていることを10秒ごとに記録
        // タイマーが生きていることの確認も兼ねる
        if elapsed >= 10 {
            let shouldLog = (lastSilenceLogAt == nil)
                || Date().timeIntervalSince(lastSilenceLogAt!) >= 10
            if shouldLog {
                log("見えていません（\(Int(elapsed))秒）", verbose: true)
                lastSilenceLogAt = Date()
            }
        }
    }
    
    
    // MARK: - 接続の後始末
    // 接続を切り,次の発見を受け付けられる状態に戻す
    private func cleanUpConnection() {
        if let tag, tag.state != .disconnected {
            central.cancelPeripheralConnection(tag)
        }
        // nilに戻すことで,次のdidDiscoverが接続を始められるようにする
        tag = nil
    }
    
    
    // MARK: - ログ
    // 画面とコンソールの両方にログを出す
    //
    // - Parameter verbose: 検証用の細かいログならtrue
    //   `verboseLogging` がoffのあいだは記録しない
    //
    // 普段は「状態が変わったこと」と「エラー」だけを残し,
    // 受信のたびの記録や接続の途中経過はverbose側へ回す
    // そうしないと,2秒ごとの発見ログに肝心のイベントが埋もれる
    private func log(_ message: String, verbose: Bool = false) {
        if verbose && !verboseLogging { return }
        appendLog(message)
    }

    private func appendLog(_ message: String) {
        let stamp = Date().formatted(date: .omitted, time: .standard)
        logs.append("[\(stamp)] \(message)")

        // 際限なく溜めるとメモリを食うので、古いものから捨てる
        if logs.count > 300 {
            logs.removeFirst(logs.count - 300)
        }

        print(message)   // Xcode のコンソール用手元でデバッグするとき用
    }
}
    

// ============================================================
//  MARK: - CBCentralManagerDelegate
//  Central（探す側）としてのイベントを受け取る
// ============================================================
extension TagLinkManager: CBCentralManagerDelegate {
    
    // アプリが終了させられた後,BLEイベントで起こされたときに最初に呼ばれる
    //  呼ばれる条件:
    //   - initでCBCentralManagerOptionRestoreIdentifierKeyを渡している
    //   - Info.plistのUIBackgroundModesにbluetooth-centralが入っている
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        log("復元されました")

        // 復元された＝以前スキャンしていたということなので,見張りを再開
        // startedAt も入れる入れないと lastSeenAt も startedAt も nil のままで
        // tick() が起点を持てず,タグが居ない場合に判定が永遠に始まらない
        isRunning = true
        startedAt = Date()

        // 復元されたペリフェラルを引き取る
        // ここで強参照を作り直さないと,復帰後に何も起きない
        if let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            for peripheral in restored {
                log("復元: \(peripheral.identifier.uuidString.prefix(8))… state=\(peripheral.state.rawValue)")

                peripheral.delegate = self

                if peripheral.state == .connected {
                    // 接続は生きていても,CBService/CBCharacteristicへの
                    // 参照は失われているので探索をやり直す必要がある
                    tag = peripheral
                    peripheral.discoverServices([serviceUUID])
                }
            }
        }

        // スキャンの再開はcentralManagerDidUpdateState(.poweredOn) に任せる
        // この時点ではまだstateが確定していない可能性があるため
    }
    
    // Bluetoothの状態が変わったときに呼ばれる
    // CBCentralManagerを作った直後にも必ず1回呼ばれる（これが実質の初期化完了通知）
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            // ここではじめてスキャンできるようになる
            log("Bluetooth: 使用可能")

            // 復元された場合やユーザーがBluetoothをオフからオンにした場合
            // 見張り中ならスキャンを張り直す
            if isRunning {
                startScan()
                startUITimer()
            } else if !hasAutoStarted {
                // 初回だけ自動で開始
                // 検証用アプリなので,開いた時点で動き始めるほうが確実
                // 「開始を押し忘れて何も起きない」を防ぐ
                hasAutoStarted = true
                log("自動で開始します")
                start()
            }

        case .poweredOff:
            // ユーザーがコントロールセンターなどでオフにしたらスキャンは自動的に止まる
            // オンに戻れば上の分岐で再開
            log("Bluetooth: オフ")

        case .unauthorized:
            // アプリにBluetoothの使用を許可していない
            // Info.plistのNSBluetoothAlwaysUsageDescriptionが無いと
            // そもそもダイアログが出ずにクラッシュする
            log("Bluetooth: 未許可")

        case .unsupported:
            // シミュレータは必ずここに来る,Core Bluetoothは実機でしか動かない
            log("Bluetooth: 非対応（シミュレータでは動きません）")

        default:
            // .unknown（起動直後）と.resetting（システム側の再起動中）
            log("Bluetooth: 不明な状態")
        }
    }

    // スキャン中に,条件に合うペリフェラルのアドバタイズを受信したときに呼ばれる
    // スキャンを止めていないので,前面では1秒に何度も呼ばれる
    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData _: [String: Any],
                        rssi RSSI: NSNumber) {

        guard isRunning else { return }

        discoverCount += 1

        // 前回の発見からの間隔,ログに出す
        let gap = lastSeenAt.map { Date().timeIntervalSince($0) }

        // 在の記録,接続の成否とは関係なく見えた時点で更新する
        markSeen()

        // ログは間引く,前面では毎秒何度も呼ばれて読めなくなるため
        // 逆に背面では間隔が空くので,ほぼ毎回残る
        let shouldLog = (lastDiscoverLogAt == nil)
            || Date().timeIntervalSince(lastDiscoverLogAt!) >= discoverLogGap
        if shouldLog {
            let gapText = gap.map { String(format: "前回から%.1f秒 ", $0) } ?? ""
            log("発見 \(gapText)RSSI=\(RSSI) 累計\(discoverCount)回", verbose: true)
            lastDiscoverLogAt = Date()
        }

        // ここから先はチェック（所在の申告）のための接続
        // すでに接続処理中なら何もしない
        guard tag == nil else { return }

        // まだチェックの時間でなければ何もしない
        if let lastCheckAt, Date().timeIntervalSince(lastCheckAt) < checkInterval { return }

        lastCheckAt = Date()

        // ここで強参照を作る
        // これを忘れると connect が黙って失敗する
        tag = peripheral

        // 接続後のイベント（サービス探索の結果など）を受け取るためにdelegateを自分に向けておく
        peripheral.delegate = self

        log("チェックのため接続します", verbose: true)
        central.connect(peripheral, options: nil)

        // 接続が固まったときの後始末
        connectAttempt += 1
        let attempt = connectAttempt
        DispatchQueue.main.asyncAfter(deadline: .now() + connectTimeout) { [weak self] in
            guard let self, self.connectAttempt == attempt, self.tag != nil else { return }
            self.log("接続がタイムアウトしました")
            self.cleanUpConnection()
        }
    }
    
    // 接続が成立したときに呼ばれる
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log("接続成功", verbose: true)
        peripheral.discoverServices([serviceUUID])
    }

    // 接続に失敗したときに呼ばれる
    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        log("接続失敗: \(error?.localizedDescription ?? "不明")")
        cleanUpConnection()
    }

    // 切断されたときに呼ばれる
    // error の有無で意味が変わる:
    //  - error == nil … こちらが cancelPeripheralConnection で切った（正常）
    //  - error != nil … 圏外・相手の電源断など、意図しない切断
    //
    // どちらにせよ tag を nil に戻して、次の発見を受け付けられるようにする
    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        if let error {
            log("切断（異常）: \(error.localizedDescription)")
        }
        tag = nil
    }
}


// ============================================================
//  MARK: - CBPeripheralDelegate
//  接続した相手（タグ）に対する操作の結果を受け取る
// ============================================================


extension TagLinkManager: CBPeripheralDelegate {

    // discoverServices の結果
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {

        guard error == nil else {
            log("サービス探索に失敗: \(error!.localizedDescription)")
            cleanUpConnection()
            return
        }

        // 目的のサービスがあるか確かめる
        // 無い場合＝別のアプリ／別の機器だった,あるいはLeafony側でservice.start() を呼び忘れている
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
            log("サービスが見つからない")
            cleanUpConnection()
            return
        }

        // サービスの中にあるキャラクタリスティック（実際の読み書きの窓口）を探す
        peripheral.discoverCharacteristics([checkUUID], for: service)
    }

    // discoverCharacteristics の結果
    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {

        // 探索の失敗を成功扱いにしないよう,先にエラーを見る
        guard error == nil else {
            log("キャラクタリスティック探索に失敗: \(error!.localizedDescription)")
            cleanUpConnection()
            return
        }

        guard let ch = service.characteristics?.first(where: { $0.uuid == checkUUID }) else {
            log("チェック用キャラクタリスティックなし（接続のみ成功）")
            markSeen()
            cleanUpConnection()
            return
        }

        // 1バイト書く,中身に意味は無く「届いたかどうか」だけを見る
        //
        // .withResponse を選ぶ理由:
        //   相手が受け取ったという応答が返り、didWriteValueFor が呼ばれる
        //   .withoutResponse だと投げっぱなしで、届いたか分からない
        peripheral.writeValue(Data([1]), for: ch, type: .withResponse)
        log("チェック送信", verbose: true)
    }

    // writeValue(.withResponse) の結果
    // errorがnilなら,書き込みがタグに届いたことが確定する
    func peripheral(_ peripheral: CBPeripheral,
                    didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error {
            log("チェック失敗: \(error.localizedDescription)")
        } else {
            log("チェック到達", verbose: true)
            markSeen()
        }

        // 用が済んだら切る
        cleanUpConnection()
    }
}
