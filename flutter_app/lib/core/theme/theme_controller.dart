import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum AppThemePreference {
  system('system', '跟随系统', Icons.brightness_auto_rounded),
  light('light', '浅色', Icons.light_mode_rounded),
  dark('dark', '深色', Icons.dark_mode_rounded);

  const AppThemePreference(this.storageValue, this.label, this.icon);

  final String storageValue;
  final String label;
  final IconData icon;

  ThemeMode get themeMode {
    return switch (this) {
      AppThemePreference.system => ThemeMode.system,
      AppThemePreference.light => ThemeMode.light,
      AppThemePreference.dark => ThemeMode.dark,
    };
  }

  static AppThemePreference fromStorageValue(String? value) {
    return AppThemePreference.values.firstWhere(
      (preference) => preference.storageValue == value,
      orElse: () => AppThemePreference.system,
    );
  }
}

class ThemeController extends ChangeNotifier {
  ThemeController._(this._store, this._themePreference);

  final _ThemePreferenceStore _store;
  AppThemePreference _themePreference;

  AppThemePreference get themePreference => _themePreference;

  ThemeMode get themeMode => _themePreference.themeMode;

  static Future<ThemeController> create() async {
    final store = _ThemePreferenceStore();
    final themePreference = AppThemePreference.fromStorageValue(
      await store.load(),
    );
    return ThemeController._(store, themePreference);
  }

  Future<void> setThemePreference(AppThemePreference preference) async {
    if (_themePreference == preference) {
      return;
    }
    _themePreference = preference;
    await _store.save(preference.storageValue);
    notifyListeners();
  }
}

class _ThemePreferenceStore {
  static const _androidMethods = MethodChannel('castpigeon.android/methods');
  static const _macosMethods = MethodChannel('castpigeon.macos/methods');

  MethodChannel? get _channel {
    if (Platform.isAndroid) {
      return _androidMethods;
    }
    if (Platform.isMacOS) {
      return _macosMethods;
    }
    return null;
  }

  Future<String?> load() async {
    final channel = _channel;
    if (channel == null) {
      return null;
    }
    try {
      return await channel.invokeMethod<String>('themePreference');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<void> save(String value) async {
    final channel = _channel;
    if (channel == null) {
      return;
    }
    try {
      await channel.invokeMethod<bool>('setThemePreference', {
        'preference': value,
      });
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }
}
