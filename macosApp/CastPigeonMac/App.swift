import SwiftUI
import AppKit
// MARK: - App Entry
@main
struct CastPigeonMacApp: App {
    @StateObject private var viewModel = MainViewModel()

    init() {
        // 恢复为常规带 Dock 栏的窗口应用，方便测试与截图
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
    }
}

struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}


// MARK: - Main View
struct ContentView: View {
    @EnvironmentObject var viewModel: MainViewModel

    var body: some View {
        ZStack {
            VisualEffectView().ignoresSafeArea()

            VStack(spacing: 20) {
                // Header
                HStack {
                    Image(systemName: "paperplane.circle.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(statusColor)
                        .scaleEffect(viewModel.isAnimating ? 1.1 : 1.0)
                        .animation(.spring(response: 0.4, dampingFraction: 0.5), value: viewModel.isAnimating)
                    
                    Text("CastPigeon")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Button(action: { NSApplication.shared.terminate(nil) }) {
                        Image(systemName: "power")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.secondary)
                    }.buttonStyle(.plain).padding(.leading, 8)
                }.padding(.top, 16).padding(.horizontal, 20)

                Divider().background(Color.secondary.opacity(0.3))

                // Role Selection
                if viewModel.workMode == .idle {
                    Picker("角色", selection: $viewModel.role) {
                        ForEach(DeviceRole.allCases, id: \.self) { role in
                            Text(role.rawValue).tag(role)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal, 20)
                }

                // Status Area
                VStack(spacing: 8) {
                    Text(viewModel.connectionStateName)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text(viewModel.connectionStateDescription)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }.padding(.vertical, 8)

                if viewModel.workMode == .idle {
                    HStack {
                        Button("配对新设备") {
                            withAnimation { viewModel.start(mode: .pairing) }
                        }.buttonStyle(.bordered)
                        
                        Button("启动工作") {
                            withAnimation { viewModel.start(mode: .working) }
                        }.buttonStyle(.borderedProminent)
                    }.padding(.bottom, 20)
                    
                    // Binding Management
                    if let bound = viewModel.boundDeviceHash {
                        HStack {
                            Text("已绑定: \(bound)").font(.system(size: 12))
                            Spacer()
                            Button("解绑") { viewModel.unbindDevice() }.controlSize(.mini)
                        }.padding(.horizontal, 20).padding(.bottom, 10)
                    }
                } else {
                    Button("停止并断开") {
                        withAnimation { viewModel.stopAll() }
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .padding(.bottom, 10)
                    
                    if viewModel.connectionStateName == "Transferring" {
                        VStack {
                            if viewModel.role == .sender {
                                Button("发送模拟消息") {
                                    viewModel.sendMockMessage("Hello from Mac: \(Date())")
                                }
                            } else {
                                Text("最新收到消息：")
                                    .font(.system(size: 12, weight: .bold))
                                Text(viewModel.receivedMessage ?? "暂无消息")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }.padding(.bottom, 10)
                    }
                    
                    // Show Discovered Devices in Pairing Mode for Receiver
                    if viewModel.workMode == .pairing && viewModel.role == .receiver && !viewModel.udpDevices.isEmpty {
                        Text("局域网发现的设备：")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.top, 10)
                        
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(viewModel.udpDevices, id: \.hash_) { device in
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(device.deviceName).font(.system(size: 14, weight: .bold))
                                            Text("Role: \(device.role) | Hash: \(device.hash_)").font(.system(size: 11))
                                        }
                                        Spacer()
                                        Button("绑定") { 
                                            viewModel.bindDevice(device: device) 
                                            viewModel.stopAll()
                                        }.controlSize(.mini)
                                    }
                                    .padding(8)
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(6)
                                }
                            }
                        }
                        .frame(maxHeight: 250)
                        .padding(.horizontal, 20)
                    } else if viewModel.workMode == .pairing && viewModel.role == .receiver {
                        Text("请确保对方设备已在同一 Wi-Fi 下启动配对...")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(.top, 10)
                    }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 600)
    }

    private var statusColor: Color {
        switch viewModel.connectionStateName {
        case "Idle": return Color.gray
        case "Scanning", "Advertising": return Color.blue
        case "Connecting": return Color.orange
        case "Transferring": return Color.green
        case "Disconnecting": return Color.red
        default: return Color.gray
        }
    }
}
