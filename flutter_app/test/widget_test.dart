import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:castpigeon_flutter/core/bridge/cast_pigeon_api.dart';
import 'package:castpigeon_flutter/core/theme/theme_controller.dart';
import 'package:castpigeon_flutter/main.dart';

void main() {
  testWidgets('CastPigeon renders the full tab shell', (tester) async {
    _installThemePreferenceMock();
    final themeController = await ThemeController.create();
    final api = _TestCastPigeonApi();
    await tester.pumpWidget(
      CastPigeonApp(api: api, themeController: themeController),
    );
    api.emit(CastPigeonSnapshot.empty);
    await tester.pump();

    expect(find.text('系统待机中'), findsWidgets);
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      expect(find.text('投鸽工作台'), findsOneWidget);
      expect(find.text('BLE 实时诊断日志：'), findsOneWidget);
      expect(find.text('工作台'), findsOneWidget);
      expect(find.text('设备管理'), findsOneWidget);
    } else {
      expect(find.text('已绑定设备'), findsOneWidget);
      expect(find.text('高级实验室'), findsOneWidget);
      expect(find.byType(IconButton), findsNWidgets(4));
    }
  });
}

void _installThemePreferenceMock() {
  Future<Object?> handler(MethodCall call) async {
    return switch (call.method) {
      'themePreference' => 'system',
      'setThemePreference' => true,
      _ => null,
    };
  }

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('castpigeon.android/methods'),
        handler,
      );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('castpigeon.macos/methods'),
        handler,
      );
}

class _TestCastPigeonApi implements CastPigeonApi {
  final _controller = StreamController<CastPigeonSnapshot>.broadcast();

  void emit(CastPigeonSnapshot snapshot) {
    _controller.add(snapshot);
  }

  @override
  Stream<CastPigeonSnapshot> get snapshotStream => _controller.stream;

  @override
  Future<void> refresh() async {}

  @override
  Future<bool> cancelPairingPrompt() async => true;

  @override
  Future<bool> approvePairingRequest() async => true;

  @override
  Future<bool> rejectPairingRequest() async => true;

  @override
  Future<String?> appIconBase64(String packageName) async => null;

  @override
  Future<String?> historyIconBase64(String appName) async => null;

  @override
  Future<bool> checkUpdate() async => true;

  @override
  Future<bool> copyClipboardHistory(String content) async => true;

  @override
  Future<bool> downloadRelease(String tagName) async => true;

  @override
  Future<bool> installRelease(String tagName) async => true;

  @override
  Future<bool> refreshUpdateHistory() async => true;

  @override
  Future<bool> removeBoundDevice(String hash) async => true;

  @override
  Future<bool> renameBoundDevice(String hash, String name) async => true;

  @override
  Future<bool> requestBinding(CastDevice device) async => true;

  @override
  Future<bool> selectPrivilegeMode(String mode) async => true;

  @override
  Future<bool> sendFile(CastDevice device) async => true;

  @override
  Future<bool> sendTestNotification() async => true;

  @override
  Future<bool> setAppSyncEnabled(String packageName, bool enabled) async =>
      true;

  @override
  Future<bool> setNotificationSharing(String hash, bool enabled) async => true;

  @override
  Future<bool> setRole(DeviceRole role) async => true;

  @override
  Future<bool> setShowSystemApps(bool show) async => true;

  @override
  Future<bool> startPairing() async => true;

  @override
  Future<bool> startWorking() async => true;

  @override
  Future<bool> stop() async => true;

  @override
  Future<bool> verifyBinding(CastDevice device, String pin) async => true;

  @override
  Future<bool> openBluetoothPrivacySettings() async => true;

  @override
  Future<bool> insertDebugLog(String message) async => true;

  @override
  Future<bool> clearDebugLogs() async => true;

  @override
  void dispose() {
    _controller.close();
  }
}
