import 'dart:async';

enum ConnectionPhase {
  idle(0),
  advertisingOrScanning(1),
  connecting(2),
  pairingRequest(3),
  transferring(4),
  disconnecting(5);

  const ConnectionPhase(this.code);

  final int code;

  static ConnectionPhase fromCode(int code) {
    return values.firstWhere((phase) => phase.code == code, orElse: () => idle);
  }
}

enum DeviceRole {
  sender(0),
  receiver(1);

  const DeviceRole(this.code);

  final int code;

  static DeviceRole fromCode(int code) {
    return values.firstWhere((role) => role.code == code, orElse: () => sender);
  }
}

enum WorkMode {
  idle(0),
  pairing(1),
  working(2);

  const WorkMode(this.code);

  final int code;

  static WorkMode fromCode(int code) {
    return values.firstWhere((mode) => mode.code == code, orElse: () => idle);
  }
}

class CastPigeonSnapshot {
  const CastPigeonSnapshot({
    required this.connectionStateCode,
    required this.roleCode,
    required this.workModeCode,
    required this.connectionStateLabel,
    required this.connectionStateDescription,
    required this.roleLabel,
    required this.workModeLabel,
    required this.isAnimating,
    required this.bluetoothPermissionDenied,
    required this.pairingDeviceName,
    required this.connectedDeviceName,
    required this.connectedDeviceHashes,
    required this.localDeviceName,
    required this.localDeviceHash,
    required this.onlineDevices,
    required this.boundDevices,
    required this.transferStatus,
    required this.latestReceivedMessage,
    required this.pinDisplay,
    required this.pinInputDevice,
    required this.historyMessages,
    required this.clipboardItems,
    required this.installedApps,
    required this.showSystemApps,
    required this.privilege,
    required this.update,
    required this.debugLogs,
  });

  factory CastPigeonSnapshot.fromJson(Map<String, Object?> json) {
    return CastPigeonSnapshot(
      connectionStateCode: json['connectionStateCode'] as int? ?? 0,
      roleCode: json['roleCode'] as int? ?? 0,
      workModeCode: json['workModeCode'] as int? ?? 0,
      connectionStateLabel: json['connectionStateLabel'] as String? ?? '系统待机中',
      connectionStateDescription:
          json['connectionStateDescription'] as String? ?? '静默期，无硬件能耗。',
      roleLabel: json['roleLabel'] as String? ?? '发送端',
      workModeLabel: json['workModeLabel'] as String? ?? '未启动',
      isAnimating: json['isAnimating'] as bool? ?? false,
      bluetoothPermissionDenied:
          json['bluetoothPermissionDenied'] as bool? ?? false,
      pairingDeviceName: json['pairingDeviceName'] as String?,
      connectedDeviceName: json['connectedDeviceName'] as String?,
      connectedDeviceHashes: _stringList(json['connectedDeviceHashes']),
      localDeviceName: json['localDeviceName'] as String? ?? '投鸽',
      localDeviceHash: json['localDeviceHash'] as String? ?? '',
      onlineDevices: _list(
        json['onlineDevices'],
      ).map(CastDevice.fromJson).toList(),
      boundDevices: _list(
        json['boundDevices'],
      ).map(BoundDevice.fromJson).toList(),
      transferStatus: _object(json['transferStatus'], TransferStatus.fromJson),
      latestReceivedMessage: json['latestReceivedMessage'] as String?,
      pinDisplay: _object(json['pinDisplay'], PinDisplay.fromJson),
      pinInputDevice: _object(json['pinInputDevice'], CastDevice.fromJson),
      historyMessages: _list(
        json['historyMessages'],
      ).map(HistoryMessage.fromJson).toList(),
      clipboardItems: _list(
        json['clipboardItems'],
      ).map(ClipboardHistoryItem.fromJson).toList(),
      installedApps: _list(
        json['installedApps'],
      ).map(AppSyncInfo.fromJson).toList(),
      showSystemApps: json['showSystemApps'] as bool? ?? false,
      privilege: PrivilegeState.fromJson(_map(json['privilege'])),
      update: UpdateState.fromJson(_map(json['update'])),
      debugLogs: _stringList(json['debugLogs']),
    );
  }

  static const empty = CastPigeonSnapshot(
    connectionStateCode: 0,
    roleCode: 0,
    workModeCode: 0,
    connectionStateLabel: '系统待机中',
    connectionStateDescription: '静默期，无硬件能耗。',
    roleLabel: '发送端',
    workModeLabel: '未启动',
    isAnimating: false,
    bluetoothPermissionDenied: false,
    pairingDeviceName: null,
    connectedDeviceName: null,
    connectedDeviceHashes: [],
    localDeviceName: '投鸽',
    localDeviceHash: '',
    onlineDevices: [],
    boundDevices: [],
    transferStatus: null,
    latestReceivedMessage: null,
    pinDisplay: null,
    pinInputDevice: null,
    historyMessages: [],
    clipboardItems: [],
    installedApps: [],
    showSystemApps: false,
    privilege: PrivilegeState(
      isPrivileged: false,
      mode: 'Default',
      activeBackend: 'None',
      bindStatus: 'Idle',
    ),
    update: UpdateState(
      currentVersion: '1.0.0',
      message: '当前没有可用更新',
      latestRelease: null,
      historyReleases: [],
    ),
    debugLogs: [],
  );

  final int connectionStateCode;
  final int roleCode;
  final int workModeCode;
  final String connectionStateLabel;
  final String connectionStateDescription;
  final String roleLabel;
  final String workModeLabel;
  final bool isAnimating;
  final bool bluetoothPermissionDenied;
  final String? pairingDeviceName;
  final String? connectedDeviceName;
  final List<String> connectedDeviceHashes;
  final String localDeviceName;
  final String localDeviceHash;
  final List<CastDevice> onlineDevices;
  final List<BoundDevice> boundDevices;
  final TransferStatus? transferStatus;
  final String? latestReceivedMessage;
  final PinDisplay? pinDisplay;
  final CastDevice? pinInputDevice;
  final List<HistoryMessage> historyMessages;
  final List<ClipboardHistoryItem> clipboardItems;
  final List<AppSyncInfo> installedApps;
  final bool showSystemApps;
  final PrivilegeState privilege;
  final UpdateState update;
  final List<String> debugLogs;

  ConnectionPhase get phase => ConnectionPhase.fromCode(connectionStateCode);
  DeviceRole get role => DeviceRole.fromCode(roleCode);
  WorkMode get workMode => WorkMode.fromCode(workModeCode);
}

class CastDevice {
  const CastDevice({
    required this.deviceName,
    required this.role,
    required this.hash,
    required this.ipAddress,
    required this.filePort,
    required this.deviceType,
    required this.lanReachable,
  });

  factory CastDevice.fromJson(Map<String, Object?> json) {
    return CastDevice(
      deviceName: json['deviceName'] as String? ?? 'Unknown',
      role: json['role'] as String? ?? 'Unknown',
      hash: json['hash'] as String? ?? '',
      ipAddress: json['ipAddress'] as String? ?? '',
      filePort: json['filePort'] as int?,
      deviceType: json['deviceType'] as String? ?? 'Unknown',
      lanReachable: json['lanReachable'] as bool? ?? false,
    );
  }

  final String deviceName;
  final String role;
  final String hash;
  final String ipAddress;
  final int? filePort;
  final String deviceType;
  final bool lanReachable;
}

class BoundDevice {
  const BoundDevice({
    required this.name,
    required this.hash,
    required this.deviceType,
    required this.lastIp,
    required this.filePort,
    required this.notificationSharingEnabled,
  });

  factory BoundDevice.fromJson(Map<String, Object?> json) {
    return BoundDevice(
      name: json['name'] as String? ?? '已绑定设备',
      hash: json['hash'] as String? ?? '',
      deviceType: json['deviceType'] as String? ?? 'Unknown',
      lastIp: json['lastIp'] as String?,
      filePort: json['filePort'] as int?,
      notificationSharingEnabled:
          json['notificationSharingEnabled'] as bool? ?? true,
    );
  }

  final String name;
  final String hash;
  final String deviceType;
  final String? lastIp;
  final int? filePort;
  final bool notificationSharingEnabled;
}

class TransferStatus {
  const TransferStatus({
    required this.fileName,
    required this.peerLabel,
    required this.direction,
    required this.phase,
    required this.bytesTransferred,
    required this.totalBytes,
    required this.detail,
  });

  factory TransferStatus.fromJson(Map<String, Object?> json) {
    return TransferStatus(
      fileName: json['fileName'] as String? ?? '',
      peerLabel: json['peerLabel'] as String? ?? '',
      direction: json['direction'] as String? ?? '',
      phase: json['phase'] as String? ?? '',
      bytesTransferred: (json['bytesTransferred'] as num?)?.toInt() ?? 0,
      totalBytes: (json['totalBytes'] as num?)?.toInt(),
      detail: json['detail'] as String?,
    );
  }

  final String fileName;
  final String peerLabel;
  final String direction;
  final String phase;
  final int bytesTransferred;
  final int? totalBytes;
  final String? detail;

  double? get progressFraction {
    final total = totalBytes;
    if (total == null || total <= 0) {
      return null;
    }
    return bytesTransferred / total;
  }
}

class HistoryMessage {
  const HistoryMessage({
    required this.id,
    required this.deviceHash,
    required this.appName,
    required this.title,
    required this.content,
    required this.timestamp,
  });

  factory HistoryMessage.fromJson(Map<String, Object?> json) {
    return HistoryMessage(
      id: json['id'] as String? ?? '',
      deviceHash: json['deviceHash'] as String? ?? '',
      appName: json['appName'] as String? ?? '',
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String deviceHash;
  final String appName;
  final String title;
  final String content;
  final int timestamp;
}

class ClipboardHistoryItem {
  const ClipboardHistoryItem({
    required this.id,
    required this.content,
    required this.direction,
    required this.timestamp,
  });

  factory ClipboardHistoryItem.fromJson(Map<String, Object?> json) {
    return ClipboardHistoryItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      content: json['content'] as String? ?? '',
      direction: json['direction'] as String? ?? '',
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
    );
  }

  final int id;
  final String content;
  final String direction;
  final int timestamp;
}

class AppSyncInfo {
  const AppSyncInfo({
    required this.packageName,
    required this.appName,
    required this.isSystemApp,
    required this.isSelected,
  });

  factory AppSyncInfo.fromJson(Map<String, Object?> json) {
    return AppSyncInfo(
      packageName: json['packageName'] as String? ?? '',
      appName: json['appName'] as String? ?? '',
      isSystemApp: json['isSystemApp'] as bool? ?? false,
      isSelected: json['isSelected'] as bool? ?? true,
    );
  }

  final String packageName;
  final String appName;
  final bool isSystemApp;
  final bool isSelected;
}

class PrivilegeState {
  const PrivilegeState({
    required this.isPrivileged,
    required this.mode,
    required this.activeBackend,
    required this.bindStatus,
  });

  factory PrivilegeState.fromJson(Map<String, Object?> json) {
    return PrivilegeState(
      isPrivileged: json['isPrivileged'] as bool? ?? false,
      mode: json['mode'] as String? ?? 'Default',
      activeBackend: json['activeBackend'] as String? ?? 'None',
      bindStatus: json['bindStatus'] as String? ?? 'Idle',
    );
  }

  final bool isPrivileged;
  final String mode;
  final String activeBackend;
  final String bindStatus;
}

class UpdateState {
  const UpdateState({
    required this.currentVersion,
    required this.message,
    required this.latestRelease,
    required this.historyReleases,
  });

  factory UpdateState.fromJson(Map<String, Object?> json) {
    return UpdateState(
      currentVersion: json['currentVersion'] as String? ?? '1.0.0',
      message: json['message'] as String? ?? '',
      latestRelease: _object(json['latestRelease'], ReleaseInfo.fromJson),
      historyReleases: _list(
        json['historyReleases'],
      ).map(ReleaseInfo.fromJson).toList(),
    );
  }

  final String currentVersion;
  final String message;
  final ReleaseInfo? latestRelease;
  final List<ReleaseInfo> historyReleases;
}

class ReleaseInfo {
  const ReleaseInfo({
    required this.tagName,
    required this.versionName,
    required this.title,
    required this.body,
    required this.assetName,
    required this.download,
  });

  factory ReleaseInfo.fromJson(Map<String, Object?> json) {
    return ReleaseInfo(
      tagName: json['tagName'] as String? ?? '',
      versionName: json['versionName'] as String? ?? '',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      assetName: json['assetName'] as String? ?? '',
      download: _object(json['download'], ReleaseDownloadState.fromJson),
    );
  }

  final String tagName;
  final String versionName;
  final String title;
  final String body;
  final String assetName;
  final ReleaseDownloadState? download;
}

class ReleaseDownloadState {
  const ReleaseDownloadState({
    required this.progress,
    required this.isVerifying,
    required this.isVerified,
    required this.message,
  });

  factory ReleaseDownloadState.fromJson(Map<String, Object?> json) {
    return ReleaseDownloadState(
      progress: json['progress'] as int? ?? -1,
      isVerifying: json['isVerifying'] as bool? ?? false,
      isVerified: json['isVerified'] as bool? ?? false,
      message: json['message'] as String?,
    );
  }

  final int progress;
  final bool isVerifying;
  final bool isVerified;
  final String? message;
}

class PinDisplay {
  const PinDisplay({required this.pin, required this.requestingDevice});

  factory PinDisplay.fromJson(Map<String, Object?> json) {
    return PinDisplay(
      pin: json['pin'] as String? ?? '',
      requestingDevice: CastDevice.fromJson(_map(json['requestingDevice'])),
    );
  }

  final String pin;
  final CastDevice requestingDevice;
}

abstract class CastPigeonApi {
  Stream<CastPigeonSnapshot> get snapshotStream;

  Future<void> refresh();
  Future<bool> startPairing();
  Future<bool> startWorking();
  Future<bool> stop();
  Future<bool> setRole(DeviceRole role);
  Future<bool> requestBinding(CastDevice device);
  Future<bool> verifyBinding(CastDevice device, String pin);
  Future<bool> cancelPairingPrompt();
  Future<bool> approvePairingRequest();
  Future<bool> rejectPairingRequest();
  Future<bool> removeBoundDevice(String hash);
  Future<bool> renameBoundDevice(String hash, String name);
  Future<bool> setNotificationSharing(String hash, bool enabled);
  Future<bool> setShowSystemApps(bool show);
  Future<bool> setAppSyncEnabled(String packageName, bool enabled);
  Future<bool> sendFile(CastDevice device);
  Future<String?> appIconBase64(String packageName);
  Future<String?> historyIconBase64(String appName);
  Future<bool> copyClipboardHistory(String content);
  Future<bool> selectPrivilegeMode(String mode);
  Future<bool> checkUpdate();
  Future<bool> refreshUpdateHistory();
  Future<bool> downloadRelease(String tagName);
  Future<bool> installRelease(String tagName);
  Future<bool> sendTestNotification();
  Future<bool> openBluetoothPrivacySettings();
  Future<bool> insertDebugLog(String message);
  Future<bool> clearDebugLogs();

  void dispose();
}

List<Map<String, Object?>> _list(Object? value) {
  if (value is! List) {
    return const [];
  }
  return value
      .whereType<Map>()
      .map((entry) => entry.cast<String, Object?>())
      .toList();
}

Map<String, Object?> _map(Object? value) {
  if (value is Map) {
    return value.cast<String, Object?>();
  }
  return const {};
}

List<String> _stringList(Object? value) {
  if (value is! List) {
    return const [];
  }
  return value.whereType<String>().toList(growable: false);
}

T? _object<T>(Object? value, T Function(Map<String, Object?> json) decode) {
  if (value is Map) {
    return decode(value.cast<String, Object?>());
  }
  return null;
}
