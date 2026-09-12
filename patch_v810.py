# -*- coding: utf-8 -*-
"""v8.10 补丁：播放器缓冲方案 + 3 个 bug 修复
1) PlayerFactory 增加"预缓存时长"读取（键 player_precache_buffer_duration_seconds）
2) MDK 内核：setMedia 时应用 setBufferRange（min=时长秒*1000, max=*6）
3) MediaKit 内核：mpv cache=yes + cache-secs + cache-pause=yes
4) 收藏页为空兜底：getSwipeItems favoritesOnly 时客户端按 UserData.IsFavorite 再过滤
5) 刷片页：页码指示右移到圆钮左侧（不再重叠）
6) 刷片页：底部常驻极细播放进度条（未唤出控件时显示），单击唤出完整控制面板
"""
import io
import sys

def read(path):
    with io.open(path, 'r', encoding='utf-8-sig', newline='') as f:
        return f.read()

def write(path, text):
    with io.open(path, 'w', encoding='utf-8', newline='') as f:
        f.write(text)

def apply(path, pairs):
    text = read(path)
    for old, new in pairs:
        if old not in text:
            print(f'[FAIL] {path}: anchor not found -> {old[:80]!r}')
            sys.exit(1)
        text = text.replace(old, new, 1)
    write(path, text)
    print(f'[OK] {path}')

# ============ 1. player_factory.dart ============
pf = r'lib/player_abstraction/player_factory.dart'
apply(pf, [
    # 常量
    ("""  static const String _playerKernelTypeKey = 'player_kernel_type';
  static const String _precacheBufferSizeKey = 'player_precache_buffer_size_mb';""",
     """  static const String _playerKernelTypeKey = 'player_kernel_type';
  static const String _precacheBufferSizeKey = 'player_precache_buffer_size_mb';
  static const String _precacheBufferDurationKey =
      'player_precache_buffer_duration_seconds';"""),
    ("""  static const int defaultPrecacheBufferSizeMb = 32;
  static const int minPrecacheBufferSizeMb = 4;
  static const int maxPrecacheBufferSizeMb = 512;""",
     """  static const int defaultPrecacheBufferSizeMb = 32;
  static const int minPrecacheBufferSizeMb = 4;
  static const int maxPrecacheBufferSizeMb = 512;
  static const int defaultPrecacheBufferDurationSeconds = 4;
  static const int minPrecacheBufferDurationSeconds = 1;
  static const int maxPrecacheBufferDurationSeconds = 120;"""),
    # 字段
    ("""  static PlayerKernelType? _cachedKernelType;
  static int _cachedPrecacheBufferSizeMb = defaultPrecacheBufferSizeMb;""",
     """  static PlayerKernelType? _cachedKernelType;
  static int _cachedPrecacheBufferSizeMb = defaultPrecacheBufferSizeMb;
  static int _cachedPrecacheBufferDurationSeconds =
      defaultPrecacheBufferDurationSeconds;"""),
    # initialize 读
    ("""      final bufferSizeMb = prefs.getInt(_precacheBufferSizeKey);""",
     """      final bufferSizeMb = prefs.getInt(_precacheBufferSizeKey);
      final precacheBufferDurationSecs =
          prefs.getInt(_precacheBufferDurationKey);"""),
    ("""      _cachedPrecacheBufferSizeMb = _clampPrecacheBufferSizeMb(
        bufferSizeMb ?? defaultPrecacheBufferSizeMb,
      );""",
     """      _cachedPrecacheBufferSizeMb = _clampPrecacheBufferSizeMb(
        bufferSizeMb ?? defaultPrecacheBufferSizeMb,
      );
      _cachedPrecacheBufferDurationSeconds =
          _clampPrecacheBufferDurationSeconds(
        precacheBufferDurationSecs ?? defaultPrecacheBufferDurationSeconds,
      );"""),
    # 同步加载默认
    ("""      _cachedKernelType = _defaultKernelType;
      _cachedPrecacheBufferSizeMb = defaultPrecacheBufferSizeMb;
      _cachedMacOSNativeVideoEnabled = false;
      _cachedAndroidAudioOutput = 'opensles';
      _cachedErikaAndroidOutputMode = PlayerErikaAndroidOutputMode.sdr;
      _cachedCustomPlayerUA = '';
      _cachedHttpProxy = '';
      AppHttpProxy.clear();
      MediaKitPlayerAdapter.setMacOSNativeVideoPreference(false);
      _hasLoadedSettings = true;

      // 异步加载正确设置并更新缓存
      SharedPreferences.getInstance().then((prefs) {
        final kernelTypeIndex = prefs.getInt(_playerKernelTypeKey);
        final bufferSizeMb = prefs.getInt(_precacheBufferSizeKey);""",
     """      _cachedKernelType = _defaultKernelType;
      _cachedPrecacheBufferSizeMb = defaultPrecacheBufferSizeMb;
      _cachedPrecacheBufferDurationSeconds =
          defaultPrecacheBufferDurationSeconds;
      _cachedMacOSNativeVideoEnabled = false;
      _cachedAndroidAudioOutput = 'opensles';
      _cachedErikaAndroidOutputMode = PlayerErikaAndroidOutputMode.sdr;
      _cachedCustomPlayerUA = '';
      _cachedHttpProxy = '';
      AppHttpProxy.clear();
      MediaKitPlayerAdapter.setMacOSNativeVideoPreference(false);
      _hasLoadedSettings = true;

      // 异步加载正确设置并更新缓存
      SharedPreferences.getInstance().then((prefs) {
        final kernelTypeIndex = prefs.getInt(_playerKernelTypeKey);
        final bufferSizeMb = prefs.getInt(_precacheBufferSizeKey);
        final precacheBufferDurationSecs =
            prefs.getInt(_precacheBufferDurationKey);"""),
    ("""        if (bufferSizeMb != null) {
          _cachedPrecacheBufferSizeMb = _clampPrecacheBufferSizeMb(
            bufferSizeMb,
          );
        }
        _cachedMacOSNativeVideoEnabled = macOSNativeVideoEnabled;""",
     """        if (bufferSizeMb != null) {
          _cachedPrecacheBufferSizeMb = _clampPrecacheBufferSizeMb(
            bufferSizeMb,
          );
        }
        if (precacheBufferDurationSecs != null) {
          _cachedPrecacheBufferDurationSeconds =
              _clampPrecacheBufferDurationSeconds(
            precacheBufferDurationSecs,
          );
        }
        _cachedMacOSNativeVideoEnabled = macOSNativeVideoEnabled;"""),
    # getter（插在 getPrecacheBufferSizeBytes 前）
    ("""  static int getPrecacheBufferSizeBytes() {
    return getPrecacheBufferSizeMb() * 1024 * 1024;
  }""",
     """  static int getPrecacheBufferSizeBytes() {
    return getPrecacheBufferSizeMb() * 1024 * 1024;
  }

  /// 获取播放预缓存时长（秒）。MediaKit 用作 mpv cache-secs，MDK 用作缓冲范围。
  static int getPrecacheBufferDurationSeconds() {
    if (!_hasLoadedSettings) {
      _loadSettingsSync();
    }
    return _cachedPrecacheBufferDurationSeconds;
  }

  static int _clampPrecacheBufferDurationSeconds(int value) {
    return value
        .clamp(
          minPrecacheBufferDurationSeconds,
          maxPrecacheBufferDurationSeconds,
        )
        .toInt();
  }"""),
    # createPlayer 传参
    ("""      case PlayerKernelType.mdk:
        debugPrint('[PlayerFactory] 创建 MDK 播放器');
        return MdkPlayerAdapter(httpProxy: getHttpProxy());""",
     """      case PlayerKernelType.mdk:
        debugPrint('[PlayerFactory] 创建 MDK 播放器');
        return MdkPlayerAdapter(
          httpProxy: getHttpProxy(),
          bufferPrecacheSecs: getPrecacheBufferDurationSeconds(),
        );"""),
    ("""      case PlayerKernelType.mediaKit:
        return MediaKitPlayerAdapter(
          bufferSize: getPrecacheBufferSizeBytes(),
          androidAudioOutput: getAndroidAudioOutput(),
          httpProxy: getHttpProxy(),
        );""",
     """      case PlayerKernelType.mediaKit:
        return MediaKitPlayerAdapter(
          bufferSize: getPrecacheBufferSizeBytes(),
          androidAudioOutput: getAndroidAudioOutput(),
          httpProxy: getHttpProxy(),
          cacheSecs: getPrecacheBufferDurationSeconds(),
        );"""),
])

# ============ 2. mdk_player_adapter_io.dart ============
mdk = r'lib/player_abstraction/mdk_player_adapter_io.dart'
apply(mdk, [
    ("""  final String _httpProxy;

  MdkPlayerAdapter({String? httpProxy})
      : _httpProxy = (httpProxy ?? '').trim() {
    _mdkPlayer = mdk.Player();
    _attachMdkEventListeners();
    _applyInitialSettings();
  }""",
     """  final String _httpProxy;
  final int _bufferPrecacheSecs;

  MdkPlayerAdapter({String? httpProxy, int bufferPrecacheSecs = 0})
      : _httpProxy = (httpProxy ?? '').trim(),
        _bufferPrecacheSecs = bufferPrecacheSecs {
    _mdkPlayer = mdk.Player();
    _attachMdkEventListeners();
    _applyInitialSettings();
  }"""),
    ("""    _mdkPlayer.setMedia(path, _fromPlayerMediaType(type));
  }""",
     """    _mdkPlayer.setMedia(path, _fromPlayerMediaType(type));
    // [QBSenHook] v8.10: 应用预缓存缓冲范围（秒→毫秒），缓解高码率视频卡顿
    if (type == PlayerMediaType.video &&
        path.isNotEmpty &&
        _bufferPrecacheSecs > 0) {
      try {
        _mdkPlayer.setBufferRange(
          min: _bufferPrecacheSecs * 1000,
          max: _bufferPrecacheSecs * 1000 * 6,
          drop: false,
        );
        debugPrint('MDK: 应用预缓存缓冲范围 ${_bufferPrecacheSecs}s');
      } catch (e) {
        debugPrint('MDK: 应用预缓存缓冲范围失败: $e');
      }
    }
  }"""),
])

# ============ 3. media_kit_player_adapter.dart ============
mk = r'lib/player_abstraction/media_kit_player_adapter.dart'
apply(mk, [
    ("""void applyMediaKitNetworkOptions(
  void Function(String key, String value) setter, {
  required String userAgent,
  String httpProxy = '',
}) {
  if (userAgent.isNotEmpty) setter('user-agent', userAgent);
  if (httpProxy.isNotEmpty) setter('http-proxy', httpProxy);
}""",
     """void applyMediaKitNetworkOptions(
  void Function(String key, String value) setter, {
  required String userAgent,
  String httpProxy = '',
  int cacheSecs = 0,
}) {
  if (userAgent.isNotEmpty) setter('user-agent', userAgent);
  if (httpProxy.isNotEmpty) setter('http-proxy', httpProxy);
  // [QBSenHook] v8.10: 启用 mpv 网络缓存（按秒预缓存 + 缓冲不足自动暂停等缓冲）
  if (cacheSecs > 0) {
    setter('cache', 'yes');
    setter('cache-secs', '$cacheSecs');
    setter('cache-pause', 'yes');
  }
}"""),
    ("""  MediaKitPlayerAdapter({
    int? bufferSize,
    String? androidAudioOutput,
    String? httpProxy,
  })  : _mpvDiagnosticsEnabled = _shouldEnableMpvDiagnostics(),""",
     """  MediaKitPlayerAdapter({
    int? bufferSize,
    String? androidAudioOutput,
    String? httpProxy,
    int cacheSecs = 0,
  })  : _cacheSecs = cacheSecs,
        _mpvDiagnosticsEnabled = _shouldEnableMpvDiagnostics(),"""),
    ("""  final String _httpProxy;
  static const int _defaultBufferSize = 32 * 1024 * 1024;""",
     """  final String _httpProxy;
  final int _cacheSecs;
  static const int _defaultBufferSize = 32 * 1024 * 1024;"""),
    ("""    applyMediaKitNetworkOptions(
      _setMpvPropertyOption,
      userAgent: '',
      httpProxy: _httpProxy,
    );""",
     """    applyMediaKitNetworkOptions(
      _setMpvPropertyOption,
      userAgent: '',
      httpProxy: _httpProxy,
      cacheSecs: _cacheSecs,
    );"""),
])

# ============ 4. emby_service.dart 收藏兜底 ============
es = r'lib/services/emby_service.dart'
apply(es, [
    ("""      final result = all;
      if (sortBy == 'random') {""",
     """      // [QBSenHook] v8.10: 收藏模式双保险——服务端 Filters=IsFavorite 偶尔失效时，
      // 客户端按 UserData.IsFavorite 再过滤一次，避免收藏页为空。
      final result = favoritesOnly
          ? all.where((e) => e.userData?.isFavorite == true).toList()
          : all;
      if (sortBy == 'random') {"""),
])

# ============ 5/6. emby_swipe_page.dart ============
sw = r'lib/pages/emby_swipe_page.dart'
apply(sw, [
    # 页码指示右移避开右上角圆形播放/暂停控件
    ("""              Positioned(
                top: MediaQuery.of(context).padding.top + 10,
                right: 14,""",
     """              Positioned(
                top: MediaQuery.of(context).padding.top + 10,
                right: 70,"""),
    # 底部：未唤出控件时显示常驻极细进度条
    ("""        // [QBSenHook] v8.5: 进度条合并——快进快退/单击均只显示下方控制面板进度条（可拖动）
        if (_controlsVisible) _buildControlPanel(),""",
     """        // [QBSenHook] v8.5: 进度条合并——快进快退/单击均只显示下方控制面板进度条（可拖动）
        // [QBSenHook] v8.10: 未唤出控件时底部常驻极细播放进度条（显示播放到哪里）
        if (_controlsVisible) _buildControlPanel() else _buildMiniProgressBar(),"""),
    # 新增 _buildMiniProgressBar 方法（插在 _buildControlPanel 定义之前）
    ("""  /// [QBSenHook] v7.5.2: 循环切换画面尺寸模式。
  void _cycleFitMode() {""",
     """  /// [QBSenHook] v8.10: 底部常驻极细播放进度条（无背景，仅显示播放进度）。
  /// 单击唤出完整控制面板后由控制面板进度条替代。
  Widget _buildMiniProgressBar() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        top: false,
        child: Consumer<VideoPlayerState>(
          builder: (context, videoState, child) {
            final bool hasVideo = videoState.hasVideo;
            final double pos = hasVideo &&
                    videoState.duration.inMilliseconds > 0
                ? (videoState.position.inMilliseconds /
                        videoState.duration.inMilliseconds)
                    .clamp(0.0, 1.0)
                : 0.0;
            return Container(
              height: 2.5,
              color: Colors.black.withValues(alpha: 0.3),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: pos,
                child: Container(
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// [QBSenHook] v7.5.2: 循环切换画面尺寸模式。
  void _cycleFitMode() {"""),
])

print('ALL PATCHES APPLIED')
