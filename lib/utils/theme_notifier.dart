// ThemeNotifier.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nipaplay/utils/settings_storage.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/models/anime_detail_display_mode.dart';
import 'package:nipaplay/models/background_image_render_mode.dart';

class ThemeNotifier with ChangeNotifier {
  static const String backgroundImageRenderModeKey =
      'background_image_render_mode';
  static const String backgroundImageOverlayOpacityKey =
      'background_image_overlay_opacity';
  static const double defaultBackgroundImageOverlayOpacity = 0.3;

  // [QBSenHook] v8.5: 按时间自动日夜切换
  static const int _dayStartHour = 6; // 6:00 进入日间
  static const int _nightStartHour = 18; // 18:00 进入夜间
  bool _nightBucket;
  Timer? _autoThemeTimer;

  ThemeMode _themeMode;
  String _backgroundImageMode;
  String _customBackgroundPath;
  AnimeDetailDisplayMode _animeDetailDisplayMode;
  BackgroundImageRenderMode _backgroundImageRenderMode;
  double _backgroundImageOverlayOpacity;

  ThemeNotifier({
    ThemeMode initialThemeMode = ThemeMode.system,
    String initialBackgroundImageMode = "关闭",
    String initialCustomBackgroundPath = 'assets/backempty.png',
    AnimeDetailDisplayMode initialAnimeDetailDisplayMode =
        AnimeDetailDisplayMode.simple,
    BackgroundImageRenderMode initialBackgroundImageRenderMode =
        BackgroundImageRenderMode.opacity,
    double initialBackgroundImageOverlayOpacity =
        defaultBackgroundImageOverlayOpacity,
  })  : _nightBucket = _isNightNow(),
        _themeMode = _isNightNow() ? ThemeMode.dark : ThemeMode.light,
        _backgroundImageMode = initialBackgroundImageMode,
        _customBackgroundPath = initialCustomBackgroundPath,
        _animeDetailDisplayMode = initialAnimeDetailDisplayMode,
        _backgroundImageRenderMode = initialBackgroundImageRenderMode,
        _backgroundImageOverlayOpacity = initialBackgroundImageOverlayOpacity;

  ThemeMode get themeMode => _themeMode;
  String get backgroundImageMode => _backgroundImageMode;

  /// [QBSenHook] v8.5: 当前时段是否为夜间（18:00-5:59）
  static bool _isNightNow() {
    final h = DateTime.now().hour;
    return h >= _nightStartHour || h < _dayStartHour;
  }

  /// [QBSenHook] v8.5: 启动自动日夜定时器（每 30 秒检查跨时段切换）
  void startAutoTheme() {
    _autoThemeTimer?.cancel();
    _autoThemeTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _autoCheckTheme());
  }

  void _autoCheckTheme() {
    final night = _isNightNow();
    if (night == _nightBucket) return;
    _nightBucket = night;
    final mode = night ? ThemeMode.dark : ThemeMode.light;
    _themeMode = mode;
    SettingsStorage.saveString('themeMode', mode.toString().split('.').last);
    notifyListeners();
  }

  @override
  void dispose() {
    _autoThemeTimer?.cancel();
    _autoThemeTimer = null;
    super.dispose();
  }
  String get customBackgroundPath => _customBackgroundPath;
  AnimeDetailDisplayMode get animeDetailDisplayMode =>
      _animeDetailDisplayMode;
  BackgroundImageRenderMode get backgroundImageRenderMode =>
      _backgroundImageRenderMode;
  double get backgroundImageOverlayOpacity => _backgroundImageOverlayOpacity;

  set themeMode(ThemeMode mode) {
    _themeMode = mode;
    // [QBSenHook] v8.5: 手动切换同步当前时段桶，自动逻辑不会立即把用户的选择拉回
    _nightBucket = _isNightNow();
    SettingsStorage.saveString('themeMode', mode.toString().split('.').last).then((_) {
      ////////debugPrint('Theme mode saved: ${mode.toString().split('.').last}'); // 添加日志输出
    });
    notifyListeners();
  }

  set backgroundImageMode(String mode) {
    if (_backgroundImageMode != mode) {
      _backgroundImageMode = mode;
      SettingsStorage.saveString('backgroundImageMode', mode).then((_) {
        ////////debugPrint('Background image mode saved: $mode'); // 添加日志输出
      });
      globals.backgroundImageMode = mode; // 更新全局变量
      notifyListeners();
    }
  }

  set customBackgroundPath(String path) {
    if (_customBackgroundPath != path) {
      _customBackgroundPath = path;
      SettingsStorage.saveString('customBackgroundPath', path).then((_) {
        ////////debugPrint('Custom background path saved: $path'); // 添加日志输出
      });
      globals.customBackgroundPath = path; // 更新全局变量
      notifyListeners();
    }
  }

  set animeDetailDisplayMode(AnimeDetailDisplayMode mode) {
    if (_animeDetailDisplayMode != mode) {
      _animeDetailDisplayMode = mode;
      SettingsStorage
          .saveString('anime_detail_display_mode', mode.storageKey)
          .then((_) {
        ////////debugPrint('Anime detail display mode saved: ${mode.storageKey}');
      });
      notifyListeners();
    }
  }

  set backgroundImageRenderMode(BackgroundImageRenderMode mode) {
    if (_backgroundImageRenderMode != mode) {
      _backgroundImageRenderMode = mode;
      SettingsStorage.saveString(backgroundImageRenderModeKey, mode.storageKey);
      notifyListeners();
    }
  }

  set backgroundImageOverlayOpacity(double value) {
    final double clampedValue = value.clamp(0.0, 1.0);
    if (_backgroundImageOverlayOpacity != clampedValue) {
      _backgroundImageOverlayOpacity = clampedValue;
      SettingsStorage.saveDouble(
        backgroundImageOverlayOpacityKey,
        clampedValue,
      );
      notifyListeners();
    }
  }
}
