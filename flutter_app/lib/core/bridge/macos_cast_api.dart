import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import 'cast_pigeon_api.dart';

class MacOSCastApi implements CastPigeonApi {
  MacOSCastApi({MethodChannel? methodChannel, EventChannel? eventChannel})
    : _methods =
          methodChannel ?? const MethodChannel('castpigeon.macos/methods'),
      _events =
          eventChannel ?? const EventChannel('castpigeon.macos/snapshots') {
    _eventSubscription = _events.receiveBroadcastStream().listen((event) {
      if (event is String) {
        _emitSnapshot(event);
      }
    });
    unawaited(refresh());
  }

  final MethodChannel _methods;
  final EventChannel _events;
  final _snapshotController = StreamController<CastPigeonSnapshot>.broadcast();
  StreamSubscription<Object?>? _eventSubscription;
  CastPigeonSnapshot _latestSnapshot = CastPigeonSnapshot.empty;

  @override
  Stream<CastPigeonSnapshot> get snapshotStream => _snapshotController.stream;

  @override
  Future<void> refresh() async {
    final payload = await _methods.invokeMethod<String>('snapshot');
    if (payload != null) {
      _emitSnapshot(payload);
    }
  }

  @override
  Future<bool> startPairing() => _boolMethod('startPairing');

  @override
  Future<bool> startWorking() => _boolMethod('startWorking');

  @override
  Future<bool> stop() => _boolMethod('stop');

  @override
  Future<bool> setRole(DeviceRole role) {
    return _boolMethod('setRole', <String, Object?>{'role': role.code});
  }

  @override
  Future<bool> requestBinding(CastDevice device) {
    return _boolMethod('requestBinding', _deviceArguments(device));
  }

  @override
  Future<bool> verifyBinding(CastDevice device, String pin) {
    return _boolMethod('verifyBinding', <String, Object?>{
      ..._deviceArguments(device),
      'targetHash': device.hash,
      'pin': pin,
    });
  }

  @override
  Future<bool> cancelPairingPrompt() => _boolMethod('cancelPairingPrompt');

  @override
  Future<bool> approvePairingRequest() async => false;

  @override
  Future<bool> rejectPairingRequest() async => false;

  @override
  Future<bool> removeBoundDevice(String hash) {
    return _boolMethod('removeBoundDevice', <String, Object?>{'hash': hash});
  }

  @override
  Future<bool> renameBoundDevice(String hash, String name) {
    return _boolMethod('renameBoundDevice', <String, Object?>{
      'hash': hash,
      'name': name,
    });
  }

  @override
  Future<bool> setNotificationSharing(String hash, bool enabled) {
    return _boolMethod('setNotificationSharing', <String, Object?>{
      'hash': hash,
      'enabled': enabled,
    });
  }

  @override
  Future<bool> sendFile(CastDevice device) {
    return _boolMethod('sendFile', _deviceArguments(device));
  }

  @override
  Future<bool> checkUpdate() => _boolMethod('checkUpdate');

  @override
  Future<bool> refreshUpdateHistory() => _boolMethod('refreshUpdateHistory');

  @override
  Future<bool> downloadRelease(String tagName) {
    return _boolMethod('downloadRelease', <String, Object?>{
      'tagName': tagName,
    });
  }

  @override
  Future<bool> copyClipboardHistory(String content) {
    return _boolMethod('copyClipboardHistory', <String, Object?>{
      'content': content,
    });
  }

  @override
  Future<String?> historyIconBase64(String appName) {
    return _methods.invokeMethod<String>('historyIconBase64', <String, Object?>{
      'appName': appName,
    });
  }

  @override
  Future<bool> setShowSystemApps(bool show) async => false;

  @override
  Future<bool> setAppSyncEnabled(String packageName, bool enabled) async =>
      false;

  @override
  Future<String?> appIconBase64(String packageName) async => null;

  @override
  Future<bool> selectPrivilegeMode(String mode) async => false;

  @override
  Future<bool> installRelease(String tagName) {
    return _boolMethod('installRelease', <String, Object?>{'tagName': tagName});
  }

  @override
  Future<bool> sendTestNotification() async => false;

  @override
  Future<bool> openBluetoothPrivacySettings() {
    return _boolMethod('openBluetoothPrivacySettings');
  }

  @override
  Future<bool> insertDebugLog(String message) {
    return _boolMethod('insertDebugLog', <String, Object?>{'message': message});
  }

  @override
  Future<bool> clearDebugLogs() {
    return _boolMethod('clearDebugLogs');
  }

  @override
  void dispose() {
    unawaited(_eventSubscription?.cancel());
    _snapshotController.close();
  }

  Future<bool> _boolMethod(String method, [Map<String, Object?>? arguments]) {
    return _methods
        .invokeMethod<bool>(method, arguments)
        .then((value) => value ?? false);
  }

  void _emitSnapshot(String payload) {
    final decoded = jsonDecode(payload);
    if (decoded is Map<String, Object?>) {
      _latestSnapshot = CastPigeonSnapshot.fromJson(decoded);
    } else if (decoded is Map) {
      _latestSnapshot = CastPigeonSnapshot.fromJson(
        decoded.cast<String, Object?>(),
      );
    }
    _snapshotController.add(_latestSnapshot);
  }

  Map<String, Object?> _deviceArguments(CastDevice device) {
    return <String, Object?>{
      'deviceName': device.deviceName,
      'role': device.role,
      'hash': device.hash,
      'ipAddress': device.ipAddress,
      'filePort': device.filePort,
      'deviceType': device.deviceType,
      'lanReachable': device.lanReachable,
    };
  }
}
