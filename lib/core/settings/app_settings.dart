import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:path_provider/path_provider.dart';

/// 轻量级应用设置（path_provider + JSON 持久化，不引入新依赖）。
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  static const String defaultCameraIp = '192.168.0.1';
  static const int defaultCameraPort = 15740;
  static const bool defaultAutoBindNetwork = true;
  static const bool defaultAutoKeepAlive = true;
  static const bool defaultDownloadRaw = false;
  static const int defaultPreferredFps = 15;
  static const bool defaultPowerProtectionEnabled = true;
  static const int defaultPowerThreshold = 15;
  static const AppThemeMode defaultThemeMode = AppThemeMode.system;

  static const List<int> fpsOptions = [4, 8, 15];
  static const List<int> powerThresholdOptions = [10, 15, 20, 30];

  String cameraIp = defaultCameraIp;
  int cameraPort = defaultCameraPort;
  bool autoBindNetwork = defaultAutoBindNetwork;
  bool autoKeepAlive = defaultAutoKeepAlive;
  bool downloadRaw = defaultDownloadRaw;
  int preferredFps = defaultPreferredFps;
  bool powerProtectionEnabled = defaultPowerProtectionEnabled;
  int powerThreshold = defaultPowerThreshold;
  AppThemeMode themeMode = defaultThemeMode;

  File? _file;
  bool _suppressSave = false;

  Future<File> _prefFile() async {
    final cached = _file;
    if (cached != null) return cached;
    final dir = await getApplicationDocumentsDirectory();
    return _file = File('${dir.path}/snaplink_settings.json');
  }

  Future<void> load() async {
    _suppressSave = true;
    try {
      final file = await _prefFile();
      if (!await file.exists()) return;
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return;
      final m = Map<String, dynamic>.from(raw);
      cameraIp = _readString(m, 'cameraIp', defaultCameraIp);
      cameraPort = _readInt(m, 'cameraPort', defaultCameraPort);
      autoBindNetwork = _readBool(m, 'autoBindNetwork', defaultAutoBindNetwork);
      autoKeepAlive = _readBool(m, 'autoKeepAlive', defaultAutoKeepAlive);
      downloadRaw = _readBool(m, 'downloadRaw', defaultDownloadRaw);
      preferredFps = _normalizeFps(_readInt(m, 'preferredFps', defaultPreferredFps));
      powerProtectionEnabled =
          _readBool(m, 'powerProtectionEnabled', defaultPowerProtectionEnabled);
      powerThreshold =
          _normalizeThreshold(_readInt(m, 'powerThreshold', defaultPowerThreshold));
      themeMode = parseThemeMode(m['themeMode']);
    } catch (_) {
      // 配置文件损坏：保持默认值
    } finally {
      _suppressSave = false;
    }
  }

  Future<void> save() async {
    try {
      final file = await _prefFile();
      await file.writeAsString(jsonEncode({
        'cameraIp': cameraIp,
        'cameraPort': cameraPort,
        'autoBindNetwork': autoBindNetwork,
        'autoKeepAlive': autoKeepAlive,
        'downloadRaw': downloadRaw,
        'preferredFps': preferredFps,
        'powerProtectionEnabled': powerProtectionEnabled,
        'powerThreshold': powerThreshold,
        'themeMode': themeMode.name,
      }));
    } catch (_) {
      // 落盘失败不中断用户操作
    }
  }

  void _scheduleSave() {
    if (_suppressSave) return;
    save();
  }

  ThemeMode get materialThemeMode => switch (themeMode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      };

  void setCameraIp(String value) {
    final v = value.trim();
    if (v.isEmpty || v == cameraIp) return;
    cameraIp = v;
    notifyListeners();
    _scheduleSave();
  }

  void setCameraPort(int value) {
    if (value <= 0 || value > 65535 || value == cameraPort) return;
    cameraPort = value;
    notifyListeners();
    _scheduleSave();
  }

  void setAutoBindNetwork(bool value) {
    if (value == autoBindNetwork) return;
    autoBindNetwork = value;
    notifyListeners();
    _scheduleSave();
  }

  void setAutoKeepAlive(bool value) {
    if (value == autoKeepAlive) return;
    autoKeepAlive = value;
    notifyListeners();
    _scheduleSave();
  }

  void setDownloadRaw(bool value) {
    if (value == downloadRaw) return;
    downloadRaw = value;
    notifyListeners();
    _scheduleSave();
  }

  void setPreferredFps(int value) {
    final v = _normalizeFps(value);
    if (v == preferredFps) return;
    preferredFps = v;
    notifyListeners();
    _scheduleSave();
  }

  void setPowerProtectionEnabled(bool value) {
    if (value == powerProtectionEnabled) return;
    powerProtectionEnabled = value;
    notifyListeners();
    _scheduleSave();
  }

  void setPowerThreshold(int value) {
    final v = _normalizeThreshold(value);
    if (v == powerThreshold) return;
    powerThreshold = v;
    notifyListeners();
    _scheduleSave();
  }

  void setThemeMode(AppThemeMode value) {
    if (value == themeMode) return;
    themeMode = value;
    notifyListeners();
    _scheduleSave();
  }

  @visibleForTesting
  void resetForTest() {
    cameraIp = defaultCameraIp;
    cameraPort = defaultCameraPort;
    autoBindNetwork = defaultAutoBindNetwork;
    autoKeepAlive = defaultAutoKeepAlive;
    downloadRaw = defaultDownloadRaw;
    preferredFps = defaultPreferredFps;
    powerProtectionEnabled = defaultPowerProtectionEnabled;
    powerThreshold = defaultPowerThreshold;
    themeMode = defaultThemeMode;
    _file = null;
  }

  @visibleForTesting
  static AppThemeMode parseThemeMode(Object? value) =>
      AppThemeMode.values.firstWhere(
        (mode) => mode.name == value,
        orElse: () => defaultThemeMode,
      );

  static int _normalizeFps(int v) => fpsOptions.contains(v) ? v : defaultPreferredFps;

  static int _normalizeThreshold(int v) =>
      powerThresholdOptions.contains(v) ? v : defaultPowerThreshold;

  static String _readString(Map<String, dynamic> m, String key, String fallback) {
    final v = m[key];
    if (v is String && v.trim().isNotEmpty) return v.trim();
    return fallback;
  }

  static int _readInt(Map<String, dynamic> m, String key, int fallback) =>
      (m[key] as num?)?.toInt() ?? fallback;

  static bool _readBool(Map<String, dynamic> m, String key, bool fallback) =>
      m[key] as bool? ?? fallback;
}

/// 外观模式：跟随系统、浅色、深色。
enum AppThemeMode { system, light, dark }
