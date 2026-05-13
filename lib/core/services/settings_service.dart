import 'package:flutter/material.dart';
import 'package:hive_flutter/adapters.dart';

class SettingsService {
  static const String _isDeveloperModeKey = 'isDeveloperMode';
  static const String _isDebugVisibleKey = 'isDebugVisible';
  static const String _isDarkModeKey = 'isDarkMode';
  static const String _isSystemBrightnessKey = 'isSystemBrightness';
  static const String _castProxyUrlKey = 'castProxyUrl';

  late final Box box;

  Future<void> init() async {
    try {
      box = await Hive.openBox('settings');
    } catch (e) {
      await Hive.deleteBoxFromDisk('settings');
      box = await Hive.openBox('settings');
    }
  }

  bool get isDeveloperMode =>
      bool.parse(box.get(_isDeveloperModeKey) ?? 'false');

  void setDeveloperMode(bool value) {
    box.put(_isDeveloperModeKey, value.toString());
  }

  bool get isDebugVisible => bool.parse(box.get(_isDebugVisibleKey) ?? 'false');

  void setDebugVisible(bool value) {
    box.put(_isDebugVisibleKey, value.toString());
  }

  bool get isDarkMode => bool.parse(box.get(_isDarkModeKey) ?? 'false');

  void setDarkMode(bool value) {
    box.put(_isDarkModeKey, value.toString());
  }

  bool get isSystemBrightness =>
      bool.parse(box.get(_isSystemBrightnessKey) ?? 'true');

  void setSystemBrightness(bool value) {
    box.put(_isSystemBrightnessKey, value.toString());
  }

  ThemeMode get theme {
    if (isSystemBrightness) {
      return ThemeMode.system;
    } else if (isDarkMode) {
      return ThemeMode.dark;
    } else {
      return ThemeMode.light;
    }
  }

  /// Adres (schema+host+port) serwera proxy dla Google Cast, np.
  /// `http://192.168.1.42:8080`. Pusty string = proxy wyłączone.
  String get castProxyUrl {
    final raw = box.get(_castProxyUrlKey);
    if (raw is String) return raw.trim();
    return '';
  }

  /// Zapisuje adres proxy. Usuwa końcowe `/`. Pusty string kasuje proxy.
  void setCastProxyUrl(String value) {
    var v = value.trim();
    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }
    box.put(_castProxyUrlKey, v);
  }

  bool get hasCastProxy => castProxyUrl.isNotEmpty;
}
