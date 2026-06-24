<div align="center">

# 🕊️ CastPigeon (投鸽)

**新一代跨平台跨端高速文件流转与设备协作引擎**

[![Kotlin Multiplatform](https://img.shields.io/badge/Kotlin-Multiplatform-7F52FF?logo=kotlin&style=for-the-badge)](#)
[![Compose Multiplatform](https://img.shields.io/badge/Compose-Multiplatform-4285F4?logo=jetpackcompose&style=for-the-badge)](#)
[![macOS](https://img.shields.io/badge/macOS-Native-000000?logo=apple&style=for-the-badge)](#)
[![Android](https://img.shields.io/badge/Android-15.0+-3DDC84?logo=android&style=for-the-badge)](#)

</div>

## 📖 项目简介

**CastPigeon (投鸽)** 是一款旨在打破设备壁垒的跨平台局域网与蓝牙近场通信应用。通过在 Android 与 macOS 之间构建极低延迟、高安全性的传输信道，CastPigeon 能够在无外部网络的弱网环境下，实现设备的无缝握手、自动绑定以及高速数据传递。

同时，在视觉交互层，我们探索并实现了基于物理光学原理的 **液态玻璃 (Liquid Glass)** 渲染技术，带来了无与伦比的极客美学体验。

---

## 🛠️ 核心架构体系

本项目严格遵循 **Kotlin Multiplatform (KMP)** 的模块化设计哲学，将工程拆分为以下四大核心模块：

- **`sharedLogic` (通用业务逻辑层)**：跨平台共享的底层核心大脑。包含了自定义的设备状态机 (`ConnectionStateMachine`)、网络与 UDP 嗅探引擎、数据加解密服务 (`Crypto`) 以及抽象的低功耗蓝牙 (`BlePeripheral` & `BleCentral`) 接口集。
- **`sharedUI` (通用 UI 资源层)**：承载 Compose Multiplatform 所需的跨平台资源（主题、颜色令牌、多语言资源、通用基础组件）。
- **`androidApp` (Android 宿主)**：基于 Jetpack Compose 构建的纯原生 Android 客户端。深度融合了 Android 15.0+ 的权限流、前台服务流，并实现了极为惊艳的自定义底部导航栏渲染。
- **`macosApp` (macOS 宿主)**：基于 `SwiftUI` 搭配 `sharedLogic` KCF 产物构建的原生桌面端应用，无缝桥接了 CoreBluetooth 框架。

---

## 🚀 高级技术点剖析

### 1. 基于光学折射算法的“液态玻璃”渲染 (Liquid Glass UI)

Android 端的底部导航栏（`FloatingBottomBar`）并未采用传统的静态切图或简单的透明度堆叠，而是实现了一套**物理级别的实时光学折射引擎**：
- **实时底层截屏采集 (`LayerBackdrop`)**：利用底层的 `Modifier.layerBackdrop()` 技术，实时捕获被 UI 遮挡区域的底层 Canvas 像素。
- **高阶模糊与散景合成 (`Haze`)**：通过集成 `dev.chrisbanes.haze`，实时进行高斯模糊（Gaussian Blur）和噪点（Noise）混合，生成真实的磨砂玻璃质感。
- **动态物理透镜 (`Lens`)**：在拖拽交互时，内部使用矩阵变换计算像素点的拉伸率，呈现出具备**表面张力**和**物理阻尼感**的果冻弹射与畸变效果。彻底解决了传统透明组件常见的边缘穿模或黑边溢出问题。

### 2. 多重链路混合发现与握手协议 (Hybrid Handshake Protocol)

为了确保双端能在复杂的网络环境下发现彼此，项目设计了基于双轨道的通讯发现机制：
- **低功耗蓝牙 (BLE) 广播与扫描**：利用设备生成的 `DeviceHash`，通过 BLE Advertising 将短载荷特征码在近场进行广播，实现无感知的设备发现。
- **UDP 局域网探针 (`UdpDiscovery`)**：一旦 BLE 触发配对握手，系统会回退至 UDP 局域网组播来传输需要强校验的配对 PIN 码（避免了 BLE 弱抗干扰带来的丢包问题）。
- **设备信任链条持久化**：所有的 `BoundMacs` 绑定记录与会话密钥均通过安全的持久化机制下沉保存，一次绑定，终生无感握手。

### 3. 反应式状态机架构 (Reactive State Machine)

项目的连接会话全权交由 `ConnectionStateMachine` 驱动。
通过 Kotlin `StateFlow` 的强响应式特性，将设备的网络状态严格限制在有限状态自动机（FSM）中流转：
`AdvertisingOrScanning` ⇌ `PairingRequest` ➞ `Transferring` ➞ `Idle`。
避免了复杂的异步回调地狱（Callback Hell），让跨平台端（Android/Swift）只需要观测状态节点，UI 就能自动做出最正确的视图响应。

---

## 💻 技术栈矩阵 (Tech Stack)

### 核心语言与框架
- **语言**: Kotlin 2.4.0, Swift 6
- **核心框架**: Kotlin Multiplatform, Compose Multiplatform (1.11.1)

### 构建与编译系统
- **Gradle Version Catalogs** (`libs.versions.toml`) 依赖统一管理。
- **Android Gradle Plugin (AGP)** 9.0.1 (Targeting Android SDK 37)

### UI 组件与图形学
- **Jetpack Compose** / **Material 3** (Android & Shared UI)
- **Haze (1.7.2)**: 针对 Compose 的底层实时高斯模糊引擎。
- **Miuix-Blur / Miuix-UI**: 提供物理弹簧动画 (Spring Animation) 与高阶模糊修饰。
- **SwiftUI**: macOS 原生视图框架。

### 异步与网络通信
- **Kotlinx Coroutines (1.9.0)**: 全局高并发协程调度引擎。
- **Ktor Network (2.3.9)**: 底层 TCP/UDP Socket 通信模块。
- **Kotlinx Serialization (1.7.3)**: 全局数据通信与 JSON 持久化序列化工具。

---

## ⚙️ 环境配置与运行指南

### Android 端
1. 确保安装了 **Android Studio Koala Feature Drop** 或更高版本。
2. 确保 JDK 版本为 **17 或 21**。
3. 执行 Gradle 同步后，选择 `androidApp` 配置，连接 Android 13+ (API 33+) 的实体真机（蓝牙与 UDP 调试不支持在模拟器中运行）。
4. 运行应用，并**务必授予“附近设备”、“位置信息”以及“通知”权限**。

### macOS 端
1. 确保系统为 **macOS 14+**，并安装了 **Xcode 16+**。
2. 在项目根目录，Gradle 会自动处理 KMP 共享模块到 `Apple Framework` 的编译。
3. 打开 `macosApp/CastPigeonMac.xcodeproj`，配置好你的 Apple Developer 证书。
4. 编译并运行，确保在“系统偏好设置”中授予了应用**蓝牙权限**与**本地网络权限**。

---

<div align="center">
  <p><i>"超越屏幕边界，让数据像信鸽一样自由翱翔。"</i></p>
  <p><b>CastPigeon Team @ 2026</b></p>
</div>