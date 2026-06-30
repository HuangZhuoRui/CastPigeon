import AppKit
import Combine
import CryptoKit
import FlutterMacOS
import UserNotifications

final class MacOSCastPigeonBridge: NSObject, FlutterStreamHandler, UNUserNotificationCenterDelegate {
  private let viewModel = MainViewModel()
  private let updateManager = FlutterMacUpdateManager()
  private var eventSink: FlutterEventSink?
  private var cancellables = Set<AnyCancellable>()
  private var latestUpdateState = FlutterMacUpdateSnapshot(currentVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")

  override init() {
    super.init()
    UNUserNotificationCenter.current().delegate = self
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    observeRuntime()
  }

  func register(with controller: FlutterViewController) {
    let methods = FlutterMethodChannel(
      name: "castpigeon.macos/methods",
      binaryMessenger: controller.engine.binaryMessenger
    )
    methods.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }

    let events = FlutterEventChannel(
      name: "castpigeon.macos/snapshots",
      binaryMessenger: controller.engine.binaryMessenger
    )
    events.setStreamHandler(self)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    emitSnapshot()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    completionHandler([.banner, .sound, .badge])
  }

  private func observeRuntime() {
    viewModel.objectWillChange
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        DispatchQueue.main.async { self?.emitSnapshot() }
      }
      .store(in: &cancellables)

    LanFileTransferManager.shared.$transferStatus
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in self?.emitSnapshot() }
      .store(in: &cancellables)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "snapshot":
      result(snapshotJson())
    case "refresh":
      emitSnapshot()
      result(true)
    case "startPairing":
      viewModel.start(mode: .pairing)
      emitSnapshot()
      result(true)
    case "startWorking":
      viewModel.start(mode: .working)
      emitSnapshot()
      result(true)
    case "stop":
      viewModel.stopAll()
      emitSnapshot()
      result(true)
    case "setRole":
      viewModel.role = (arguments["role"] as? Int) == 1 ? .receiver : .sender
      emitSnapshot()
      result(true)
    case "requestBinding":
      if let device = castDevice(from: arguments) {
        viewModel.bindDevice(device: device)
        emitSnapshot()
        result(true)
      } else {
        result(false)
      }
    case "verifyBinding":
      if let device = castDevice(from: arguments) {
        viewModel.verifyPin(pin: arguments["pin"] as? String ?? "", target: device)
      } else {
        viewModel.verifyPin(pin: arguments["pin"] as? String ?? "")
      }
      emitSnapshot()
      result(true)
    case "cancelPairingPrompt":
      viewModel.showPinDisplay = false
      viewModel.showPinInput = false
      viewModel.stopAll()
      emitSnapshot()
      result(true)
    case "removeBoundDevice":
      viewModel.unbindDevice(hash: arguments["hash"] as? String ?? "")
      emitSnapshot()
      result(true)
    case "renameBoundDevice":
      let hash = arguments["hash"] as? String ?? ""
      let name = arguments["name"] as? String ?? ""
      if !hash.isEmpty && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        viewModel.renameDevice(hash: hash, newName: name)
        emitSnapshot()
        result(true)
      } else {
        result(false)
      }
    case "setNotificationSharing":
      viewModel.setNotificationSharing(
        hash: arguments["hash"] as? String ?? "",
        enabled: arguments["enabled"] as? Bool ?? true
      )
      emitSnapshot()
      result(true)
    case "sendFile":
      guard let device = castDevice(from: arguments) else {
        result(false)
        return
      }
      let panel = NSOpenPanel()
      panel.canChooseFiles = true
      panel.canChooseDirectories = false
      panel.allowsMultipleSelection = false
      if panel.runModal() == .OK, let url = panel.url {
        LanFileTransferManager.shared.sendFile(fileURL: url, to: device) { [weak self] success in
          self?.emitSnapshot()
          result(success)
        }
      } else {
        result(false)
      }
    case "copyClipboardHistory":
      let content = arguments["content"] as? String ?? ""
      result(viewModel.copyClipboardHistory(content))
    case "historyIconBase64":
      let appName = arguments["appName"] as? String ?? ""
      if let url = DatabaseManager.shared.getIconURL(for: appName),
         let data = try? Data(contentsOf: url) {
        result(data.base64EncodedString())
      } else {
        result(nil)
      }
    case "checkUpdate":
      updateManager.checkForUpdates(showNoUpdateMessage: true) { [weak self] snapshot in
        self?.latestUpdateState = snapshot
        self?.emitSnapshot()
      }
      result(true)
    case "refreshUpdateHistory":
      updateManager.loadHistory { [weak self] snapshot in
        self?.latestUpdateState = snapshot
        self?.emitSnapshot()
      }
      result(true)
    case "downloadRelease":
      updateManager.download(tagName: arguments["tagName"] as? String ?? "") { [weak self] snapshot in
        self?.latestUpdateState = snapshot
        self?.emitSnapshot()
      }
      result(true)
    case "installRelease":
      let started = updateManager.install(tagName: arguments["tagName"] as? String ?? "") { [weak self] snapshot in
        self?.latestUpdateState = snapshot
        self?.emitSnapshot()
      }
      result(started)
    case "openBluetoothPrivacySettings":
      viewModel.openBluetoothPrivacySettings()
      result(true)
    case "insertDebugLog":
      viewModel.logDebug(arguments["message"] as? String ?? "")
      emitSnapshot()
      result(true)
    case "clearDebugLogs":
      viewModel.debugLogs.removeAll()
      emitSnapshot()
      result(true)
    case "themePreference":
      result(UserDefaults.standard.string(forKey: "themePreference") ?? "system")
    case "setThemePreference":
      UserDefaults.standard.set(arguments["preference"] as? String ?? "system", forKey: "themePreference")
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func snapshotJson() -> String {
    do {
      let data = try JSONSerialization.data(withJSONObject: snapshotDictionary(), options: [])
      return String(data: data, encoding: .utf8) ?? "{}"
    } catch {
      NSLog("CastPigeon Flutter snapshot serialization failed: \(error.localizedDescription)")
      let logs = (["Flutter 快照序列化失败: \(error.localizedDescription)"] + viewModel.debugLogs).prefix(200)
      let fallback: [String: Any] = [
        "connectionStateCode": 1,
        "roleCode": viewModel.role == .receiver ? 1 : 0,
        "workModeCode": workModeCode(viewModel.workMode),
        "connectionStateLabel": viewModel.connectionStateName,
        "connectionStateDescription": "状态同步暂时失败，底层服务仍在运行。",
        "roleLabel": viewModel.role.rawValue,
        "workModeLabel": workModeLabel(viewModel.workMode),
        "isAnimating": viewModel.isAnimating,
        "bluetoothPermissionDenied": viewModel.bluetoothPermissionDenied,
        "pairingDeviceName": NSNull(),
        "connectedDeviceName": viewModel.connectedDeviceHashes.sorted().joined(separator: ", "),
        "connectedDeviceHashes": viewModel.connectedDeviceHashes.sorted(),
        "localDeviceName": Host.current().localizedName ?? "Mac",
        "localDeviceHash": viewModel.myHash,
        "onlineDevices": [],
        "boundDevices": [],
        "transferStatus": NSNull(),
        "latestReceivedMessage": NSNull(),
        "pinDisplay": NSNull(),
        "pinInputDevice": NSNull(),
        "historyMessages": [],
        "clipboardItems": [],
        "installedApps": [],
        "showSystemApps": false,
        "privilege": [
          "isPrivileged": false,
          "mode": "macOS",
          "activeBackend": "NSPasteboard",
          "bindStatus": "Ready"
        ],
        "update": FlutterMacUpdateSnapshot(currentVersion: latestUpdateState.currentVersion).dictionary(),
        "debugLogs": Array(logs)
      ]
      guard let fallbackData = try? JSONSerialization.data(withJSONObject: fallback, options: []),
            let fallbackJson = String(data: fallbackData, encoding: .utf8) else {
        return "{}"
      }
      return fallbackJson
    }
  }

  private func emitSnapshot() {
    let payload = snapshotJson()
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?(payload)
    }
  }

  private func snapshotDictionary() -> [String: Any] {
    let phase = connectionPhaseCode(viewModel.connectionStateName)
    let update = latestUpdateState.dictionary()
    return [
      "connectionStateCode": phase,
      "roleCode": viewModel.role == .receiver ? 1 : 0,
      "workModeCode": workModeCode(viewModel.workMode),
      "connectionStateLabel": viewModel.connectionStateName,
      "connectionStateDescription": viewModel.connectionStateDescription,
      "roleLabel": viewModel.role.rawValue,
      "workModeLabel": workModeLabel(viewModel.workMode),
      "isAnimating": viewModel.isAnimating,
      "bluetoothPermissionDenied": viewModel.bluetoothPermissionDenied,
      "pairingDeviceName": NSNull(),
      "connectedDeviceName": viewModel.connectedDeviceHashes.sorted().joined(separator: ", "),
      "connectedDeviceHashes": viewModel.connectedDeviceHashes.sorted(),
      "localDeviceName": Host.current().localizedName ?? "Mac",
      "localDeviceHash": viewModel.myHash,
      "onlineDevices": viewModel.udpDevices.map(deviceDictionary),
      "boundDevices": viewModel.boundDeviceHashes.map(boundDeviceDictionary),
      "transferStatus": jsonValue(transferDictionary(LanFileTransferManager.shared.transferStatus)),
      "latestReceivedMessage": jsonValue(viewModel.receivedMessage),
      "pinDisplay": jsonValue(pinDisplayDictionary()),
      "pinInputDevice": jsonValue(pinInputDictionary()),
      "historyMessages": DatabaseManager.shared.getMessages().map(historyDictionary),
      "clipboardItems": DatabaseManager.shared.getClipboardHistory().map(clipboardDictionary),
      "installedApps": [],
      "showSystemApps": false,
      "privilege": [
        "isPrivileged": false,
        "mode": "macOS",
        "activeBackend": "NSPasteboard",
        "bindStatus": "Ready"
      ],
      "update": update,
      "debugLogs": viewModel.debugLogs
    ]
  }

  private func castDevice(from arguments: [String: Any]) -> UdpDevice? {
    guard let hash = arguments["hash"] as? String, !hash.isEmpty else { return nil }
    return UdpDevice(
      deviceName: arguments["deviceName"] as? String ?? "Unknown",
      role: arguments["role"] as? String ?? "Peer",
      hash_: hash,
      ip: arguments["ipAddress"] as? String,
      filePort: arguments["filePort"] as? Int,
      deviceType: arguments["deviceType"] as? String ?? "Unknown",
      lanReachable: arguments["lanReachable"] as? Bool ?? false
    )
  }

  private func deviceDictionary(_ device: UdpDevice) -> [String: Any] {
    [
      "deviceName": device.deviceName,
      "role": device.role,
      "hash": device.hash_,
      "ipAddress": device.ip ?? "",
      "filePort": jsonValue(device.filePort),
      "deviceType": device.deviceType,
      "lanReachable": device.lanReachable
    ]
  }

  private func boundDeviceDictionary(_ entry: String) -> [String: Any] {
    let parts = entry.components(separatedBy: "|")
    let name = parts.count > 1 ? parts[0] : "绑定的设备"
    let hash = parts.count > 1 ? parts[1] : entry
    let deviceType = parts.count > 2 ? parts[2] : "Unknown"
    let lastIp = parts.count > 3 && !parts[3].isEmpty ? parts[3] : nil
    let filePort = parts.count > 4 ? Int(parts[4]) : nil
    return [
      "name": name,
      "hash": hash,
      "deviceType": deviceType,
      "lastIp": jsonValue(lastIp),
      "filePort": jsonValue(filePort),
      "notificationSharingEnabled": viewModel.isNotificationSharingEnabled(hash: hash, defaultEnabled: true)
    ]
  }

  private func transferDictionary(_ status: LanFileTransferManager.TransferStatus?) -> [String: Any]? {
    guard let status else { return nil }
    return [
      "fileName": status.fileName,
      "peerLabel": status.peerLabel,
      "direction": status.direction == .sending ? "Sending" : "Receiving",
      "phase": transferPhaseName(status.phase),
      "bytesTransferred": status.bytesTransferred,
      "totalBytes": jsonValue(status.totalBytes),
      "detail": jsonValue(status.detail)
    ]
  }

  private func historyDictionary(_ message: NotificationMessage) -> [String: Any] {
    [
      "id": message.id,
      "deviceHash": message.deviceHash,
      "appName": message.appName,
      "title": message.title,
      "content": message.content,
      "timestamp": message.timestamp
    ]
  }

  private func clipboardDictionary(_ item: ClipboardHistoryItem) -> [String: Any] {
    [
      "id": item.id,
      "content": item.content,
      "direction": item.direction,
      "timestamp": item.timestamp
    ]
  }

  private func pinDisplayDictionary() -> [String: Any]? {
    guard viewModel.showPinDisplay, let device = viewModel.requestingDevice else { return nil }
    return [
      "pin": viewModel.displayPin,
      "requestingDevice": deviceDictionary(device)
    ]
  }

  private func pinInputDictionary() -> [String: Any]? {
    guard viewModel.showPinInput, let device = viewModel.inputTargetDevice else { return nil }
    return deviceDictionary(device)
  }

  private func workModeCode(_ mode: WorkMode) -> Int {
    switch mode {
    case .idle: return 0
    case .pairing: return 1
    case .working: return 2
    }
  }

  private func workModeLabel(_ mode: WorkMode) -> String {
    switch mode {
    case .idle: return "未启动"
    case .pairing: return "配对模式"
    case .working: return "工作模式"
    }
  }

  private func connectionPhaseCode(_ name: String) -> Int {
    switch name {
    case "Idle": return 0
    case "Connecting", "Handshake": return 2
    case "Transferring": return 4
    default: return 1
    }
  }

  private func transferPhaseName(_ phase: LanFileTransferManager.TransferPhase) -> String {
    switch phase {
    case .inProgress: return "InProgress"
    case .success: return "Success"
    case .failed: return "Failed"
    }
  }
}

private struct FlutterMacUpdateSnapshot {
  var currentVersion: String
  var message: String = ""
  var latestRelease: FlutterMacRelease?
  var historyReleases: [FlutterMacRelease] = []
  var downloadStates: [String: FlutterMacDownloadState] = [:]

  func dictionary() -> [String: Any] {
    [
      "currentVersion": currentVersion,
      "message": message,
      "latestRelease": jsonValue(latestRelease?.dictionary(download: downloadStates[latestRelease?.tagName ?? ""])),
      "historyReleases": historyReleases.map { release in
        release.dictionary(download: downloadStates[release.tagName])
      }
    ]
  }
}

private struct FlutterMacRelease {
  let version: String
  let tagName: String
  let title: String
  let body: String
  let assetName: String
  let downloadURL: String
  let checksumURL: String?
  let digest: String?

  func dictionary(download: FlutterMacDownloadState?) -> [String: Any] {
    [
      "tagName": tagName,
      "versionName": version,
      "title": title,
      "body": body,
      "assetName": assetName,
      "download": jsonValue(download?.dictionary())
    ]
  }
}

private struct FlutterMacDownloadState {
  let progress: Int
  let isVerifying: Bool
  let isVerified: Bool
  let isInstalling: Bool
  let message: String?
  let localFilePath: String?

  init(
    progress: Int,
    isVerifying: Bool = false,
    isVerified: Bool = false,
    isInstalling: Bool = false,
    message: String? = nil,
    localFilePath: String? = nil
  ) {
    self.progress = progress
    self.isVerifying = isVerifying
    self.isVerified = isVerified
    self.isInstalling = isInstalling
    self.message = message
    self.localFilePath = localFilePath
  }

  func dictionary() -> [String: Any] {
    [
      "progress": progress,
      "isVerifying": isVerifying,
      "isVerified": isVerified,
      "isInstalling": isInstalling,
      "message": jsonValue(message),
      "localFilePath": jsonValue(localFilePath)
    ]
  }

  var isBusy: Bool {
    isInstalling || isVerifying || (progress >= 0 && progress < 100)
  }
}

private func jsonValue<T>(_ value: T?) -> Any {
  guard let value else { return NSNull() }
  return value
}

private final class FlutterMacUpdateManager: NSObject, URLSessionDownloadDelegate {
  private struct DownloadContext {
    let release: FlutterMacRelease
    let destination: URL
    let completion: (FlutterMacUpdateSnapshot) -> Void
  }

  private let repository = Bundle.main.infoDictionary?["CastPigeonGitHubRepository"] as? String ?? "suse-edu-cn/CastPigeon"
  private let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
  private var snapshot: FlutterMacUpdateSnapshot
  private var downloadContexts: [Int: DownloadContext] = [:]
  private lazy var downloadSession = URLSession(configuration: .default, delegate: self, delegateQueue: .main)

  override
  init() {
    snapshot = FlutterMacUpdateSnapshot(currentVersion: currentVersion)
    super.init()
  }

  func checkForUpdates(showNoUpdateMessage: Bool, completion: @escaping (FlutterMacUpdateSnapshot) -> Void) {
    fetchPlatformReleases { [weak self] result in
      guard let self else { return }
      switch result {
      case .success(let releases):
        let newer = releases.filter { self.compareVersions($0.version, self.currentVersion) > 0 }
        self.snapshot.latestRelease = newer.first
        self.snapshot.message = newer.isEmpty && showNoUpdateMessage ? "当前已是最新版本。" : ""
      case .failure(let error):
        self.snapshot.message = "检查更新失败：\(error.localizedDescription)"
      }
      DispatchQueue.main.async { completion(self.snapshot) }
    }
  }

  func loadHistory(completion: @escaping (FlutterMacUpdateSnapshot) -> Void) {
    fetchPlatformReleases { [weak self] result in
      guard let self else { return }
      switch result {
      case .success(let releases):
        self.snapshot.historyReleases = releases
        self.snapshot.message = releases.isEmpty ? "暂无历史版本。" : self.snapshot.message
      case .failure(let error):
        self.snapshot.message = "获取历史更新失败：\(error.localizedDescription)"
      }
      DispatchQueue.main.async { completion(self.snapshot) }
    }
  }

  func download(tagName: String, completion: @escaping (FlutterMacUpdateSnapshot) -> Void) {
    guard let release = ([snapshot.latestRelease].compactMap { $0 } + snapshot.historyReleases).first(where: { $0.tagName == tagName }),
          let url = URL(string: release.downloadURL) else {
      snapshot.message = "下载链接无效。"
      completion(snapshot)
      return
    }
    guard !snapshot.downloadStates.values.contains(where: { $0.isBusy }) else {
      snapshot.downloadStates[tagName] = FlutterMacDownloadState(progress: -1, message: "已有更新任务正在进行。")
      completion(snapshot)
      return
    }
    let destination = updateDirectory().appendingPathComponent(release.assetName)
    do {
      try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
      try? FileManager.default.removeItem(at: destination)
    } catch {
      snapshot.downloadStates[tagName] = FlutterMacDownloadState(progress: -1, message: "无法准备下载目录：\(error.localizedDescription)")
      completion(snapshot)
      return
    }
    snapshot.downloadStates[tagName] = FlutterMacDownloadState(progress: 0, message: "准备下载...")
    completion(snapshot)

    let task = downloadSession.downloadTask(with: url)
    downloadContexts[task.taskIdentifier] = DownloadContext(
      release: release,
      destination: destination,
      completion: completion
    )
    task.resume()
  }

  func install(tagName: String, completion: @escaping (FlutterMacUpdateSnapshot) -> Void) -> Bool {
    guard let release = ([snapshot.latestRelease].compactMap { $0 } + snapshot.historyReleases).first(where: { $0.tagName == tagName }) else {
      snapshot.message = "没有找到要安装的版本。"
      completion(snapshot)
      return false
    }
    guard let state = snapshot.downloadStates[tagName],
          state.isVerified,
          let localFilePath = state.localFilePath,
          FileManager.default.fileExists(atPath: localFilePath) else {
      snapshot.downloadStates[tagName] = FlutterMacDownloadState(progress: -1, message: "请先下载并校验安装包。")
      completion(snapshot)
      return false
    }
    let helperURL = Bundle.main.bundleURL
      .appendingPathComponent("Contents")
      .appendingPathComponent("Helpers")
      .appendingPathComponent("CastPigeonUpdater")
    guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
      snapshot.downloadStates[tagName] = FlutterMacDownloadState(
        progress: 100,
        isVerified: true,
        message: "没有找到自动安装器，请重新构建应用。",
        localFilePath: localFilePath
      )
      completion(snapshot)
      return false
    }

    let process = Process()
    process.executableURL = helperURL
    process.arguments = [
      "--dmg", localFilePath,
      "--app", Bundle.main.bundleURL.path,
      "--pid", "\(ProcessInfo.processInfo.processIdentifier)",
      "--bundle-id", Bundle.main.bundleIdentifier ?? "com.suseoaa.castpigeon"
    ]
    do {
      try process.run()
      snapshot.downloadStates[tagName] = FlutterMacDownloadState(
        progress: 100,
        isVerified: true,
        isInstalling: true,
        message: "正在启动安装器，投鸽即将自动重启到 \(release.version) 版本...",
        localFilePath: localFilePath
      )
      completion(snapshot)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
        NSApp.terminate(nil)
      }
      return true
    } catch {
      snapshot.downloadStates[tagName] = FlutterMacDownloadState(
        progress: 100,
        isVerified: true,
        message: "启动安装器失败：\(error.localizedDescription)",
        localFilePath: localFilePath
      )
      completion(snapshot)
      return false
    }
  }

  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
    guard let context = downloadContexts[downloadTask.taskIdentifier] else { return }
    let progress = totalBytesExpectedToWrite > 0
      ? Int((Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) * 100).rounded(.down))
      : 0
    snapshot.downloadStates[context.release.tagName] = FlutterMacDownloadState(
      progress: min(99, max(0, progress)),
      message: "正在下载 \(context.release.assetName)..."
    )
    context.completion(snapshot)
  }

  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
    guard let context = downloadContexts[downloadTask.taskIdentifier] else { return }
    do {
      try? FileManager.default.removeItem(at: context.destination)
      try FileManager.default.moveItem(at: location, to: context.destination)
      snapshot.downloadStates[context.release.tagName] = FlutterMacDownloadState(
        progress: 100,
        isVerifying: true,
        message: "正在校验安装包...",
        localFilePath: context.destination.path
      )
      context.completion(snapshot)
      verifyDownloadedRelease(context)
    } catch {
      snapshot.downloadStates[context.release.tagName] = FlutterMacDownloadState(
        progress: -1,
        message: "保存失败：\(error.localizedDescription)"
      )
      context.completion(snapshot)
      downloadContexts.removeValue(forKey: downloadTask.taskIdentifier)
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard let error,
          let context = downloadContexts.removeValue(forKey: task.taskIdentifier) else {
      return
    }
    snapshot.downloadStates[context.release.tagName] = FlutterMacDownloadState(
      progress: -1,
      message: "下载失败：\(error.localizedDescription)"
    )
    context.completion(snapshot)
  }

  private func verifyDownloadedRelease(_ context: DownloadContext) {
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let result = self?.verifyFile(at: context.destination, release: context.release) ?? .failure(UpdateError("校验器已释放。"))
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        switch result {
        case .success(let message):
          self.snapshot.downloadStates[context.release.tagName] = FlutterMacDownloadState(
            progress: 100,
            isVerified: true,
            message: message,
            localFilePath: context.destination.path
          )
        case .failure(let error):
          self.snapshot.downloadStates[context.release.tagName] = FlutterMacDownloadState(
            progress: -1,
            message: "安装包校验失败：\(error.localizedDescription)"
          )
        }
        self.downloadContexts = self.downloadContexts.filter { $0.value.release.tagName != context.release.tagName }
        context.completion(self.snapshot)
      }
    }
  }

  private func fetchPlatformReleases(completion: @escaping (Result<[FlutterMacRelease], Error>) -> Void) {
    guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases") else {
      completion(.success([]))
      return
    }
    var request = URLRequest(url: url)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("CastPigeon-macOS", forHTTPHeaderField: "User-Agent")
    URLSession.shared.dataTask(with: request) { data, _, error in
      if let error {
        completion(.failure(error))
        return
      }
      guard let data else {
        completion(.success([]))
        return
      }
      do {
        let releases = try JSONDecoder().decode([GitHubReleaseResponse].self, from: data)
        let parsed = releases
          .filter { !$0.draft && !$0.prerelease }
          .compactMap { self.toMacRelease($0) }
          .sorted { self.compareVersions($0.version, $1.version) > 0 }
        completion(.success(parsed))
      } catch {
        completion(.failure(error))
      }
    }.resume()
  }

  private func toMacRelease(_ release: GitHubReleaseResponse) -> FlutterMacRelease? {
    let tagVersion = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    let prefix = "CastPigeon-macOS-v"
    for asset in release.assets where asset.name.hasPrefix(prefix) && asset.name.hasSuffix(".dmg") {
      let version = asset.name
        .dropFirst(prefix.count)
        .dropLast(4)
      guard String(version) == tagVersion else { continue }
      let checksumAsset = release.assets.first { $0.name == "\(asset.name).sha256" }
      return FlutterMacRelease(
        version: String(version),
        tagName: release.tagName,
        title: releaseDisplayName(release),
        body: release.body ?? "",
        assetName: asset.name,
        downloadURL: asset.browserDownloadURL,
        checksumURL: checksumAsset?.browserDownloadURL,
        digest: asset.digest
      )
    }
    return nil
  }

  private func compareVersions(_ left: String, _ right: String) -> Int {
    let a = versionParts(left)
    let b = versionParts(right)
    for index in 0..<max(a.count, b.count) {
      let lhs = index < a.count ? a[index] : 0
      let rhs = index < b.count ? b[index] : 0
      if lhs != rhs { return lhs - rhs }
    }
    return 0
  }

  private func versionParts(_ value: String) -> [Int] {
    value.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
      .split(whereSeparator: { ".-_".contains($0) })
      .map { Int($0.prefix(while: { $0.isNumber })) ?? 0 }
  }

  private func updateDirectory() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("CastPigeonUpdates", isDirectory: true)
  }

  private func verifyFile(at fileURL: URL, release: FlutterMacRelease) -> Result<String, Error> {
    do {
      guard let expectedDigest = try expectedDigest(for: release) else {
        return .success("下载完成，可以安装。")
      }
      let actualDigest = try sha256(fileURL)
      guard actualDigest == expectedDigest else {
        return .failure(UpdateError("SHA256 不匹配。"))
      }
      return .success("下载完成，校验通过，可以自动安装。")
    } catch {
      return .failure(error)
    }
  }

  private func expectedDigest(for release: FlutterMacRelease) throws -> String? {
    if let digest = normalizedDigest(release.digest) {
      return digest
    }
    guard let checksumURL = release.checksumURL,
          let url = URL(string: checksumURL) else {
      return nil
    }
    let content = try String(contentsOf: url, encoding: .utf8)
    return normalizedDigest(content)
  }

  private func normalizedDigest(_ value: String?) -> String? {
    guard let value else { return nil }
    let candidates = value
      .replacingOccurrences(of: "sha256:", with: "", options: .caseInsensitive)
      .split(whereSeparator: { $0.isWhitespace || $0 == "*" })
      .map(String.init)
    return candidates.first { candidate in
      candidate.count == 64 && candidate.allSatisfy { $0.isHexDigit }
    }?.lowercased()
  }

  private func sha256(_ fileURL: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: fileURL)
    defer { try? handle.close() }
    var hasher = SHA256()
    while true {
      let data = try handle.read(upToCount: 1024 * 1024)
      guard let data, !data.isEmpty else { break }
      hasher.update(data: data)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }

  private func releaseDisplayName(_ release: GitHubReleaseResponse) -> String {
    guard let name = release.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
      return release.tagName
    }
    return name
  }
}

private struct UpdateError: LocalizedError {
  let message: String

  init(_ message: String) {
    self.message = message
  }

  var errorDescription: String? {
    message
  }
}

private struct GitHubReleaseResponse: Decodable {
  let tagName: String
  let name: String?
  let body: String?
  let draft: Bool
  let prerelease: Bool
  let assets: [GitHubReleaseAssetResponse]

  enum CodingKeys: String, CodingKey {
    case tagName = "tag_name"
    case name
    case body
    case draft
    case prerelease
    case assets
  }
}

private struct GitHubReleaseAssetResponse: Decodable {
  let name: String
  let browserDownloadURL: String
  let digest: String?

  enum CodingKeys: String, CodingKey {
    case name
    case browserDownloadURL = "browser_download_url"
    case digest
  }
}
