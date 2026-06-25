import SwiftUI
import AppKit
import UserNotifications

// MARK: - AppDelegate for Notifications
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Foundation.Notification) {
        UNUserNotificationCenter.current().delegate = self
    }
    
    // 允许在应用处于前台时展示通知弹窗
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }
}

// MARK: - App Entry
@main
struct CastPigeonMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = MainViewModel()

    init() {
        // 使用常规的独立窗口应用模式
        NSApplication.shared.setActivationPolicy(.regular)
        
        // 请求通知权限
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Notification permission granted")
            } else if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
    }
}

// MARK: - Sidebar Item
enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard = "仪表盘"
    case history = "历史记录"
    case devices = "设备管理"
    
    var id: String { self.rawValue }
    
    var icon: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.bottom.100percent"
        case .history: return "clock"
        case .devices: return "macbook.and.iphone"
        }
    }
}

// MARK: - Main View
struct ContentView: View {
    @EnvironmentObject var viewModel: MainViewModel
    @State private var selection: SidebarItem? = .dashboard
    
    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                NavigationLink(value: item) {
                    Label(item.rawValue, systemImage: item.icon)
                        .font(.system(size: 14, weight: .medium))
                        .padding(.vertical, 4)
                }
            }
            .navigationTitle("CastPigeon")
            .listStyle(.sidebar)
        } detail: {
            Group {
                switch selection {
                case .dashboard:
                    DashboardView()
                case .history:
                    HistoryView()
                case .devices:
                    DevicesView()
                case .none:
                    Text("请选择一个菜单")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(VisualEffectView(material: .contentBackground, blendingMode: .behindWindow))
        }
        .frame(minWidth: 800, minHeight: 500)
    }
}

// MARK: - Dashboard View
struct DashboardView: View {
    @EnvironmentObject var viewModel: MainViewModel
    
    var body: some View {
        VStack(spacing: 30) {
            Text("CastPigeon 工作台")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .padding(.top, 40)
            
            // Mode Selection
            HStack(spacing: 40) {
                ModeCard(
                    title: "作为接收端 (Mac)",
                    desc: "接收来自手机的推送通知和剪贴板。",
                    icon: "desktopcomputer",
                    isSelected: viewModel.role == .receiver,
                    action: { viewModel.role = .receiver }
                )
                .disabled(viewModel.workMode != .idle)
                
                ModeCard(
                    title: "作为发送端 (测试用)",
                    desc: "向其他设备广播并发送数据。",
                    icon: "antenna.radiowaves.left.and.right",
                    isSelected: viewModel.role == .sender,
                    action: { viewModel.role = .sender }
                )
                .disabled(viewModel.workMode != .idle)
            }
            .padding(.horizontal, 40)
            
            // Status and Control
            VStack(spacing: 16) {
                Text(viewModel.connectionStateName)
                    .font(.system(size: 18, weight: .semibold))
                
                Text(viewModel.connectionStateDescription)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                if viewModel.isAnimating {
                    ProgressView()
                        .scaleEffect(1.2)
                        .padding()
                }
                
                if viewModel.workMode == .idle {
                    Button(action: {
                        viewModel.start(mode: .working)
                    }) {
                        Text("启动工作")
                            .font(.system(size: 16, weight: .bold))
                            .frame(width: 200, height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                } else {
                    Button(action: {
                        viewModel.stopAll()
                    }) {
                        Text("停止并断开")
                            .font(.system(size: 16, weight: .bold))
                            .frame(width: 200, height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
            .cornerRadius(16)
            .padding(.horizontal, 40)
            
            // 实时调试日志
            DebugLogPanel()
            .padding(.horizontal, 40)
            .padding(.bottom, 20)
            
            Spacer()
        }
    }
}

struct DebugLogPanel: View {
    @EnvironmentObject var viewModel: MainViewModel
    @State private var copiedHintVisible = false

    private var logText: String {
        viewModel.debugLogs.joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("BLE 实时诊断日志：")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.secondary)
                Text("可选中复制")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                if copiedHintVisible {
                    Text("已复制")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.green)
                }
                Button("插入测试日志") {
                    viewModel.logDebug("这是一条手动插入的测试日志！")
                }
                .controlSize(.small)
                Button("复制全部") {
                    copyAllLogs()
                }
                .controlSize(.small)
                Button("清空") {
                    viewModel.debugLogs.removeAll()
                }
                .controlSize(.small)
            }

            TextEditor(text: .constant(logText.isEmpty ? "暂无日志" : logText))
                .font(.system(.body, design: .monospaced))
                .foregroundColor(logText.isEmpty ? .secondary : .primary)
                .scrollContentBackground(.hidden)
                .textSelection(.enabled)
                .padding(8)
                .frame(height: 170)
                .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                .cornerRadius(8)
                .contextMenu {
                    Button("复制全部日志") {
                        copyAllLogs()
                    }
                }
        }
    }

    private func copyAllLogs() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(logText, forType: .string)
        copiedHintVisible = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copiedHintVisible = false
        }
    }
}

struct ModeCard: View {
    let title: String
    let desc: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 40))
                    .foregroundColor(isSelected ? .white : .blue)
                
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(isSelected ? .white : .primary)
                
                Text(desc)
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 200, height: 160)
            .padding()
            .background(isSelected ? Color.blue : Color(NSColor.controlBackgroundColor).opacity(0.6))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.blue : Color.gray.opacity(0.2), lineWidth: 2)
            )
            .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Devices View
struct DevicesView: View {
    @EnvironmentObject var viewModel: MainViewModel
    @State private var showPairingSheet = false
    @State private var showRenameSheet = false
    @State private var editingHash: String = ""
    @State private var editingName: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("设备管理")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Spacer()
                Button(action: {
                    showPairingSheet = true
                    viewModel.start(mode: .pairing)
                }) {
                    Label("配对新设备", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.workMode == .working)
            }
            .padding(.top, 40)
            .padding(.horizontal, 40)
            
            // Bound Device Section
            VStack(alignment: .leading, spacing: 12) {
                Text("已授权绑定的设备")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                
                if !viewModel.boundDeviceHashes.isEmpty {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(viewModel.boundDeviceHashes, id: \.self) { entry in
                                let parts = entry.components(separatedBy: "|")
                                let name = parts.count > 1 ? parts[0] : "绑定的设备"
                                let hash = parts.count > 1 ? parts[1] : entry
                                let isOnline = viewModel.connectedDeviceHashes.contains(hash)
                                
                                HStack {
                                    Image(systemName: "iphone")
                                        .font(.system(size: 24))
                                        .foregroundColor(.blue)
                                    VStack(alignment: .leading) {
                                        HStack {
                                            Text(name)
                                                .font(.system(size: 15, weight: .semibold))
                                            Circle()
                                                .fill(isOnline ? Color.green : Color.gray)
                                                .frame(width: 8, height: 8)
                                            Text(isOnline ? "在线" : "离线")
                                                .font(.system(size: 10))
                                                .foregroundColor(isOnline ? .green : .gray)
                                        }
                                        Text("Hash: \(hash)")
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Button("重命名") {
                                        editingHash = hash
                                        editingName = name
                                        showRenameSheet = true
                                    }
                                    .buttonStyle(.bordered)
                                    
                                    Button("解绑") {
                                        withAnimation { viewModel.unbindDevice(hash: hash) }
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.red)
                                }
                                .padding()
                                .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                                .cornerRadius(12)
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                } else {
                    Text("当前未绑定任何设备，请先配对。")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                        .cornerRadius(12)
                }
            }
            .padding(.horizontal, 40)

            VStack(alignment: .leading, spacing: 12) {
                Text("局域网在线设备")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)

                if let transfer = viewModel.fileTransferStatus {
                    VStack(alignment: .leading, spacing: 8) {
                        Text({
                            switch transfer.phase {
                            case .inProgress:
                                return transfer.direction == .sending ? "正在发送文件" : "正在接收文件"
                            case .success:
                                return transfer.direction == .sending ? "发送成功" : "接收成功"
                            case .failed:
                                return transfer.direction == .sending ? "发送失败" : "接收失败"
                            }
                        }())
                        .font(.system(size: 14, weight: .semibold))
                        Text(transfer.fileName)
                            .font(.system(size: 13))
                        Text(transfer.peerLabel)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        if transfer.phase == .inProgress {
                            if let progress = transfer.progressFraction {
                                ProgressView(value: progress)
                                Text("\(Int(progress * 100))%")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            } else {
                                ProgressView()
                            }
                        } else if let detail = transfer.detail, !detail.isEmpty {
                            Text(detail)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                    .cornerRadius(12)
                }

                if viewModel.udpDevices.isEmpty {
                    Text("暂无局域网设备。启动工作或配对模式后会自动发现。")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                        .cornerRadius(12)
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(viewModel.udpDevices, id: \.hash_) { device in
                                HStack {
                                    Image(systemName: device.deviceType == "Mac" ? "desktopcomputer" : "iphone")
                                        .font(.system(size: 24))
                                        .foregroundColor(.blue)
                                    VStack(alignment: .leading) {
                                        Text(device.deviceName)
                                            .font(.system(size: 15, weight: .semibold))
                                        Text("\(device.deviceType) · \(device.ip ?? "unknown") · 文件端口: \(device.filePort.map(String.init) ?? "不可用")")
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Button("发送文件") {
                                        let panel = NSOpenPanel()
                                        panel.canChooseFiles = true
                                        panel.canChooseDirectories = false
                                        panel.allowsMultipleSelection = false
                                        if panel.runModal() == .OK, let url = panel.url {
                                            LanFileTransferManager.shared.sendFile(fileURL: url, to: device) { success in
                                                viewModel.logDebug(success ? "文件已发送给 \(device.deviceName)" : "文件发送失败: \(device.deviceName)")
                                            }
                                        }
                                    }
                                    .disabled(device.filePort == nil || device.ip == nil)
                                }
                                .padding()
                                .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                                .cornerRadius(12)
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                }
            }
            .padding(.horizontal, 40)
            
            Spacer()
        }
        .sheet(isPresented: $showPairingSheet) {
            PairingSheetView()
                .environmentObject(viewModel)
        }
        .sheet(isPresented: $showRenameSheet) {
            VStack(spacing: 20) {
                Text("重命名设备")
                    .font(.system(size: 18, weight: .bold))
                TextField("设备名称", text: $editingName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 250)
                HStack(spacing: 20) {
                    Button("取消") { showRenameSheet = false }
                        .buttonStyle(.bordered)
                    Button("保存") {
                        if !editingName.isEmpty {
                            viewModel.renameDevice(hash: editingHash, newName: editingName)
                        }
                        showRenameSheet = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .frame(width: 300, height: 180)
        }
    }
}

// MARK: - Pairing Sheet
struct PairingSheetView: View {
    @EnvironmentObject var viewModel: MainViewModel
    @Environment(\.dismiss) var dismiss
    @State private var inputPin: String = ""
    
    var body: some View {
        VStack(spacing: 20) {
            if viewModel.showPinDisplay {
                Text("配对请求")
                    .font(.system(size: 18, weight: .bold))
                
                if let reqDevice = viewModel.requestingDevice {
                    Text("\(reqDevice.deviceName) 请求绑定。")
                }
                
                Text("请在对方设备上输入以下配对码：")
                    .padding(.top, 10)
                
                Text(viewModel.displayPin)
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .foregroundColor(.blue)
                    .padding()
                
                Button("取消") {
                    viewModel.stopAll()
                    dismiss()
                }
                .buttonStyle(.bordered)
            } else if viewModel.showPinInput {
                Text("输入配对码")
                    .font(.system(size: 18, weight: .bold))
                
                if let target = viewModel.inputTargetDevice {
                    Text("请输入 \(target.deviceName) 上显示的 4 位配对码：")
                }
                
                TextField("配对码", text: $inputPin)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                
                HStack(spacing: 20) {
                    Button("取消") {
                        viewModel.stopAll()
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("验证") {
                        if inputPin.count == 4 {
                            viewModel.verifyPin(pin: inputPin)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(inputPin.count != 4)
                }
            } else {
                Text(viewModel.role == .receiver ? "寻找附近的发送端..." : "正在广播，请在手机端点击绑定")
                    .font(.system(size: 18, weight: .bold))
                    .padding(.top, 20)
                
                if viewModel.role == .receiver {
                    if viewModel.udpDevices.isEmpty {
                        ProgressView()
                            .scaleEffect(1.2)
                            .padding()
                    } else {
                        ScrollView {
                            VStack(spacing: 12) {
                                ForEach(viewModel.udpDevices, id: \.hash_) { device in
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(device.deviceName)
                                                .font(.system(size: 14, weight: .bold))
                                            Text("Hash: \(device.hash_) | Role: \(device.role)")
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Button("绑定此设备") {
                                            viewModel.bindDevice(device: device)
                                        }
                                        .buttonStyle(.borderedProminent)
                                    }
                                    .padding()
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(10)
                                }
                            }
                            .padding(.horizontal)
                        }
                        .frame(height: 250)
                    }
                } else {
                    ProgressView()
                        .scaleEffect(1.2)
                        .padding()
                }
                
                Button("取消并关闭") {
                    viewModel.stopAll()
                    dismiss()
                }
                .buttonStyle(.bordered)
                .padding(.bottom, 20)
            }
        }
        .frame(width: 400, height: 350)
        .onChange(of: viewModel.boundDeviceHashes) { newValue in
            dismiss()
        }
    }
}

// MARK: - History View
struct HistoryView: View {
    @EnvironmentObject var viewModel: MainViewModel
    @State private var messages: [NotificationMessage] = []
    @State private var selectedDeviceHash: String = "All"
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("消息历史记录")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Spacer()
                
                Picker("设备:", selection: $selectedDeviceHash) {
                    Text("全部设备").tag("All")
                    ForEach(viewModel.boundDeviceHashes, id: \.self) { hash in
                        Text("Hash: \(hash)").tag(hash)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 200)
                .onChange(of: selectedDeviceHash) { _ in
                    loadMessages()
                }
                
                Button(action: {
                    loadMessages()
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)
            }
            .padding(.horizontal, 40)
            .padding(.top, 40)
            .padding(.bottom, 20)
            
            if messages.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    Text("暂无消息记录")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .padding(.top, 16)
                    Spacer()
                }
            } else {
                List(messages, id: \.id) { msg in
                    HistoryMessageRow(msg: msg)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 20)
                }
                .listStyle(.plain)
            }
        }
        .onAppear {
            loadMessages()
        }
    }
    
    private func loadMessages() {
        let hash: String? = selectedDeviceHash == "All" ? nil : selectedDeviceHash
        messages = DatabaseManager.shared.getMessages(for: hash)
    }
}

struct HistoryMessageRow: View {
    let msg: NotificationMessage
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Icon
            if let iconURL = DatabaseManager.shared.getIconURL(for: msg.appName),
               let nsImage = NSImage(contentsOf: iconURL) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                    .cornerRadius(8)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .frame(width: 48, height: 48)
                    Text(String(msg.appName.prefix(1)))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.secondary)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center) {
                    Text(msg.appName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.blue)
                    Spacer()
                    Text(formatTimestamp(msg.timestamp))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                if !msg.title.isEmpty {
                    Text(msg.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                }
                
                if !msg.content.isEmpty {
                    Text(msg.content)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .cornerRadius(12)
    }
    
    private func formatTimestamp(_ ms: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}

// MARK: - Visual Effect Wrapper
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
