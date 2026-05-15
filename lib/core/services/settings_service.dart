import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/adapters.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const String _isDeveloperModeKey = 'isDeveloperMode';
  static const String _isDebugVisibleKey = 'isDebugVisible';
  static const String _isDarkModeKey = 'isDarkMode';
  static const String _isSystemBrightnessKey = 'isSystemBrightness';
  static const String _castProxyUrlKey = 'castProxyUrl';
  static const String _castReceiverAppIdKey = 'castReceiverAppId';

  /// Default Application ID - oficjalny Default Media Receiver Google.
  /// Wspiera MP4, podstawowe HLS, DASH. NIE radzi sobie dobrze z fMP4-in-HLS
  /// (CMAF) - dla takich strumieni potrzebny jest custom receiver z shaka.
  static const String defaultCastReceiverAppId = 'CC1AD845';

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

  /// Application ID Google Cast receivera. Domyslnie [defaultCastReceiverAppId]
  /// (Default Media Receiver Google). Mozna ustawic wlasny ID custom receivera
  /// z shaka-playerem, ktory wspiera fMP4-in-HLS (CMAF).
  ///
  /// UWAGA: zmiana wymaga ponownego uruchomienia aplikacji - CastContext
  /// jest tworzony tylko raz przy starcie procesu.
  String get castReceiverAppId {
    final raw = box.get(_castReceiverAppIdKey);
    if (raw is String) {
      final v = raw.trim();
      if (v.isNotEmpty) return v;
    }
    return defaultCastReceiverAppId;
  }

  /// Zapisuje Application ID. Pusty string lub `null` przywraca default.
  /// Rownolegle zapisuje wartosc do natywnego SharedPreferences (klucz
  /// `flutter.castReceiverAppId`), zeby [CastOptionsProvider] mogl odczytac
  /// ID przed startem Fluttera. Zwraca `Future` ktory zakonczy sie po
  /// zapisaniu w obu miejscach.
  Future<void> setCastReceiverAppId(String value) async {
    var v = value.trim().toUpperCase();
    // Application ID to 8 znakow hex; nie walidujemy ostro, bo Google moze
    // zmienic format w przyszlosci - po prostu zapisujemy co user wpisal.
    if (v.isEmpty) {
      await box.delete(_castReceiverAppIdKey);
    } else {
      await box.put(_castReceiverAppIdKey, v);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      if (v.isEmpty) {
        await prefs.remove(_castReceiverAppIdKey);
      } else {
        await prefs.setString(_castReceiverAppIdKey, v);
      }
    } on MissingPluginException {
      // Test/edge env - ignorujemy.
    }
  }
}
