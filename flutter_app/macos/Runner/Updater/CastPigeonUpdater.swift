import AppKit
import Foundation

private struct UpdaterArguments {
  let dmgPath: String
  let appPath: String
  let parentPid: pid_t
  let bundleIdentifier: String
}

private final class InstallerApp: NSObject, NSApplicationDelegate {
  private let arguments: UpdaterArguments
  private let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 440, height: 190),
    styleMask: [.titled, .closable],
    backing: .buffered,
    defer: false
  )
  private let titleLabel = NSTextField(labelWithString: "正在安装投鸽")
  private let detailLabel = NSTextField(labelWithString: "正在准备安装器...")
  private let progressIndicator = NSProgressIndicator()

  init(arguments: UpdaterArguments) {
    self.arguments = arguments
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    configureWindow()
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      self?.runInstallation()
    }
  }

  private func configureWindow() {
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isMovableByWindowBackground = true
    window.isReleasedWhenClosed = false
    window.standardWindowButton(.closeButton)?.isHidden = true
    window.standardWindowButton(.miniaturizeButton)?.isHidden = true
    window.standardWindowButton(.zoomButton)?.isHidden = true

    let content = NSView(frame: window.contentView?.bounds ?? .zero)
    content.wantsLayer = true
    content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    window.contentView = content

    titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
    titleLabel.alignment = .center
    titleLabel.translatesAutoresizingMaskIntoConstraints = false

    detailLabel.font = .systemFont(ofSize: 13, weight: .medium)
    detailLabel.textColor = .secondaryLabelColor
    detailLabel.alignment = .center
    detailLabel.lineBreakMode = .byTruncatingMiddle
    detailLabel.translatesAutoresizingMaskIntoConstraints = false

    progressIndicator.minValue = 0
    progressIndicator.maxValue = 1
    progressIndicator.doubleValue = 0
    progressIndicator.isIndeterminate = false
    progressIndicator.style = .bar
    progressIndicator.controlSize = .large
    progressIndicator.translatesAutoresizingMaskIntoConstraints = false

    content.addSubview(titleLabel)
    content.addSubview(detailLabel)
    content.addSubview(progressIndicator)

    NSLayoutConstraint.activate([
      titleLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
      titleLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
      titleLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 38),
      detailLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 32),
      detailLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -32),
      detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 14),
      progressIndicator.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 44),
      progressIndicator.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -44),
      progressIndicator.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 26),
    ])
  }

  private func runInstallation() {
    var mountedVolume: URL?
    do {
      updateProgress(0.08, "正在等待旧版本退出...")
      waitForParentExit()

      let dmgURL = URL(fileURLWithPath: arguments.dmgPath)
      let destinationURL = try resolvedDestinationURL(URL(fileURLWithPath: arguments.appPath))
      guard dmgURL.pathExtension.lowercased() == "dmg" else {
        throw InstallerError("安装包格式不是 DMG。")
      }
      guard destinationURL.pathExtension.lowercased() == "app" else {
        throw InstallerError("目标路径不是 macOS 应用。")
      }

      updateProgress(0.22, "正在挂载安装包...")
      mountedVolume = try mountDiskImage(dmgURL)

      updateProgress(0.38, "正在定位新版本应用...")
      guard let sourceApp = findApplication(in: mountedVolume!) else {
        throw InstallerError("安装包中没有找到投鸽应用。")
      }

      updateProgress(0.52, "正在复制新版本...")
      try replaceApplication(source: sourceApp, destination: destinationURL)

      updateProgress(0.86, "正在清理临时文件...")
      if let mountedVolume {
        try? detachDiskImage(mountedVolume)
      }
      mountedVolume = nil
      try? FileManager.default.removeItem(at: dmgURL)

      updateProgress(1.0, "安装完成，正在打开新版本...")
      try launchApplication(destinationURL)
      Thread.sleep(forTimeInterval: 0.9)
      DispatchQueue.main.async { NSApp.terminate(nil) }
    } catch {
      if let mountedVolume {
        try? detachDiskImage(mountedVolume)
      }
      showFailure(error.localizedDescription)
    }
  }

  private func waitForParentExit() {
    while kill(arguments.parentPid, 0) == 0 {
      Thread.sleep(forTimeInterval: 0.18)
    }
  }

  private func mountDiskImage(_ dmgURL: URL) throws -> URL {
    let data = try runAndCapture(
      executable: "/usr/bin/hdiutil",
      arguments: ["attach", dmgURL.path, "-nobrowse", "-readonly", "-plist"]
    )
    let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    guard let dictionary = plist as? [String: Any],
          let entities = dictionary["system-entities"] as? [[String: Any]] else {
      throw InstallerError("无法读取 DMG 挂载信息。")
    }
    let mountPath = entities.compactMap { $0["mount-point"] as? String }.last
    guard let mountPath, !mountPath.isEmpty else {
      throw InstallerError("DMG 没有成功挂载。")
    }
    return URL(fileURLWithPath: mountPath, isDirectory: true)
  }

  private func detachDiskImage(_ mountedVolume: URL) throws {
    _ = try runAndCapture(
      executable: "/usr/bin/hdiutil",
      arguments: ["detach", mountedVolume.path, "-quiet"]
    )
  }

  private func findApplication(in mountedVolume: URL) -> URL? {
    let fileManager = FileManager.default
    let directChildren = (try? fileManager.contentsOfDirectory(
      at: mountedVolume,
      includingPropertiesForKeys: nil
    )) ?? []
    let appCandidates = directChildren.filter { $0.pathExtension.lowercased() == "app" }
    if let matching = appCandidates.first(where: { Bundle(url: $0)?.bundleIdentifier == arguments.bundleIdentifier }) {
      return matching
    }
    return appCandidates.first
  }

  private func replaceApplication(source: URL, destination: URL) throws {
    let parent = destination.deletingLastPathComponent()
    let temporary = parent.appendingPathComponent(".\(destination.lastPathComponent).installing-\(UUID().uuidString)")
    let script = """
    set -e
    /bin/rm -rf \(temporary.path.shellQuoted)
    /usr/bin/ditto \(source.path.shellQuoted) \(temporary.path.shellQuoted)
    /bin/rm -rf \(destination.path.shellQuoted)
    /bin/mv \(temporary.path.shellQuoted) \(destination.path.shellQuoted)
    /usr/bin/xattr -dr com.apple.quarantine \(destination.path.shellQuoted) >/dev/null 2>&1 || true
    """

    do {
      _ = try runAndCapture(executable: "/bin/bash", arguments: ["-c", script])
    } catch {
      updateProgress(0.66, "需要管理员权限来替换应用...")
      let appleScript = "do shell script \(script.appleScriptQuoted) with administrator privileges"
      _ = try runAndCapture(executable: "/usr/bin/osascript", arguments: ["-e", appleScript])
    }
  }

  private func resolvedDestinationURL(_ originalURL: URL) throws -> URL {
    let path = originalURL.path
    if path.contains("/AppTranslocation/") || path.hasPrefix("/Volumes/") {
      return try chooseDestinationURL(for: originalURL)
    }
    return originalURL
  }

  private func chooseDestinationURL(for originalURL: URL) throws -> URL {
    var selectedURL: URL?
    var cancelled = false
    let semaphore = DispatchSemaphore(value: 0)

    DispatchQueue.main.async { [weak self] in
      guard let self else {
        cancelled = true
        semaphore.signal()
        return
      }

      detailLabel.stringValue = "请选择新版投鸽的安装位置..."
      let panel = NSOpenPanel()
      panel.title = "选择投鸽安装位置"
      panel.message = "当前运行位置无法可靠原地更新。请选择要安装新版投鸽的文件夹。"
      panel.prompt = "安装到这里"
      panel.canChooseFiles = false
      panel.canChooseDirectories = true
      panel.allowsMultipleSelection = false
      panel.canCreateDirectories = true
      panel.directoryURL = preferredInstallDirectory()

      let response = panel.runModal()
      if response == .OK, let folderURL = panel.url {
        selectedURL = folderURL.appendingPathComponent(originalURL.lastPathComponent)
      } else {
        cancelled = true
      }
      semaphore.signal()
    }

    semaphore.wait()
    if let selectedURL {
      return selectedURL
    }
    if cancelled {
      throw InstallerError("已取消安装。")
    }
    throw InstallerError("没有选择安装位置。")
  }

  private func preferredInstallDirectory() -> URL {
    let applicationsURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
    if FileManager.default.fileExists(atPath: applicationsURL.path) {
      return applicationsURL
    }
    return FileManager.default.homeDirectoryForCurrentUser
  }

  private func launchApplication(_ appURL: URL) throws {
    _ = try runAndCapture(executable: "/usr/bin/open", arguments: [appURL.path])
  }

  private func runAndCapture(executable: String, arguments: [String]) throws -> Data {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let output = Pipe()
    let error = Pipe()
    process.standardOutput = output
    process.standardError = error
    try process.run()
    process.waitUntilExit()

    let outputData = output.fileHandleForReading.readDataToEndOfFile()
    if process.terminationStatus == 0 {
      return outputData
    }
    let errorData = error.fileHandleForReading.readDataToEndOfFile()
    let outputText = String(data: outputData, encoding: .utf8) ?? ""
    let errorText = String(data: errorData, encoding: .utf8) ?? ""
    let detail = [outputText, errorText].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: "\n")
    throw InstallerError(detail.isEmpty ? "命令执行失败：\(executable)" : detail)
  }

  private func updateProgress(_ value: Double, _ detail: String) {
    DispatchQueue.main.async { [weak self] in
      self?.progressIndicator.doubleValue = value
      self?.detailLabel.stringValue = detail
    }
  }

  private func showFailure(_ message: String) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      progressIndicator.isHidden = true
      titleLabel.stringValue = "安装失败"
      detailLabel.stringValue = message
      window.standardWindowButton(.closeButton)?.isHidden = false
    }
  }
}

private struct InstallerError: LocalizedError {
  let message: String

  init(_ message: String) {
    self.message = message
  }

  var errorDescription: String? {
    message
  }
}

private extension String {
  var shellQuoted: String {
    "'\(replacingOccurrences(of: "'", with: "'\\''"))'"
  }

  var appleScriptQuoted: String {
    "\"\(replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
  }
}

private func parseArguments() -> UpdaterArguments? {
  let arguments = CommandLine.arguments.dropFirst()
  var values: [String: String] = [:]
  var iterator = arguments.makeIterator()
  while let key = iterator.next() {
    guard key.hasPrefix("--"), let value = iterator.next() else { return nil }
    values[String(key.dropFirst(2))] = value
  }

  guard let dmgPath = values["dmg"],
        let appPath = values["app"],
        let pidString = values["pid"],
        let parentPid = Int32(pidString),
        let bundleIdentifier = values["bundle-id"] else {
    return nil
  }
  return UpdaterArguments(
    dmgPath: dmgPath,
    appPath: appPath,
    parentPid: parentPid,
    bundleIdentifier: bundleIdentifier
  )
}

guard let arguments = parseArguments() else {
  fatalError("Invalid updater arguments.")
}

private let app = NSApplication.shared
private let delegate = InstallerApp(arguments: arguments)
app.setActivationPolicy(.accessory)
app.delegate = delegate
app.run()
