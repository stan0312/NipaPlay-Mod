# -*- coding: utf-8 -*-
"""v8.11 补丁：修复用户反馈的 6 个问题
1) 刷片底部常驻"当前时间+可拖动进度条+总时长"（替代极细条）
2) 退出刷片页偶发横屏：dispose 立即同步恢复竖屏
3) 横屏视频切换画面尺寸无效：按 _fitMode 处理
4) 收藏页为空：服务端不认 Filters 时去掉重试 + 客户端过滤兜底
5) 设置页新增"播放预缓存时长/大小"滑块（内核卡片下方）
6) 默认预缓存时长 4s -> 15s，缓解高码率卡顿
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
            print(f'[FAIL] {path}: anchor not found -> {old[:90]!r}')
            sys.exit(1)
        text = text.replace(old, new, 1)
    write(path, text)
    print(f'[OK] {path}')

# ============ 1. player_factory.dart：默认 15s + 新增保存方法 ============
pf = r'lib/player_abstraction/player_factory.dart'
apply(pf, [
    ("""  static const int defaultPrecacheBufferDurationSeconds = 4;""",
     """  static const int defaultPrecacheBufferDurationSeconds = 15;"""),
    ("""  static Future<void> savePrecacheBufferSizeMb(int value) async {""",
     """  /// 保存播放预缓存时长（秒），1~120。
  static Future<void> savePrecacheBufferDurationSeconds(int value) async {
    final resolved = _clampPrecacheBufferDurationSeconds(value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_precacheBufferDurationKey, resolved);
      _cachedPrecacheBufferDurationSeconds = resolved;
      debugPrint('[PlayerFactory] 已保存播放预缓存时长: ${resolved}s');
    } catch (e) {
      debugPrint('[PlayerFactory] 保存播放预缓存时长出错: $e');
    }
  }

  static Future<void> savePrecacheBufferSizeMb(int value) async {"""),
])

# ============ 2. emby_swipe_page.dart ============
sw = r'lib/pages/emby_swipe_page.dart'
apply(sw, [
    # --- 2a. dispose 立即恢复竖屏 ---
    ("""  @override
  void dispose() {
    // [QBSenHook] v8.5: 返回上一层时保存播放记录
    _savePlayRecord();""",
     """  @override
  void dispose() {
    // [QBSenHook] v8.5: 返回上一层时保存播放记录
    _savePlayRecord();
    // [QBSenHook] v8.11: 立即恢复竖屏，不等 stop 异步完成（修复偶发退出后横屏）
    ScreenOrientationManager.instance.forcePortraitPlayback = true;
    unawaited(SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]));"""),
    # --- 2b. 横屏视频按 _fitMode 处理 ---
    ("""              // [QBSenHook] v7.5.4: 横屏视频（宽>高）自动旋转 90° 竖着铺满全屏，
              // 等比不拉伸（cover 裁切左右），与抖音横视频观看一致；竖视频走下方正常逻辑
              if (ratio > 1.0) {
                return SizedBox.expand(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    clipBehavior: Clip.hardEdge,
                    child: RotatedBox(
                      quarterTurns: 1,
                      child: SizedBox(
                        width: maxW,
                        height: maxW / ratio,
                        child: texture,
                      ),
                    ),
                  ),
                );
              }""",
     """              // [QBSenHook] v7.5.4: 横屏视频（宽>高）自动旋转 90° 竖着播放；
              // [QBSenHook] v8.11: 按 _fitMode 控制画面尺寸——cover 铺满，
              // 其余模式（原尺寸/16:9/4:3/1:1/9:16）旋转后完整显示不拉伸。
              if (ratio > 1.0) {
                if (_fitMode == EmbyFitMode.cover) {
                  return SizedBox.expand(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      clipBehavior: Clip.hardEdge,
                      child: RotatedBox(
                        quarterTurns: 1,
                        child: SizedBox(
                          width: maxW,
                          height: maxW / ratio,
                          child: texture,
                        ),
                      ),
                    ),
                  );
                }
                return Center(
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: RotatedBox(
                      quarterTurns: 1,
                      child: SizedBox(
                        width: maxW,
                        height: maxW / ratio,
                        child: texture,
                      ),
                    ),
                  ),
                );
              }"""),
    # --- 2c. 常驻可拖动进度条（带时间） ---
    ("""  /// [QBSenHook] v8.10: 底部常驻极细播放进度条（无背景，仅显示播放进度）。
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
  }""",
     """  /// [QBSenHook] v8.11: 底部常驻进度条——当前时间 + 可拖动进度条 + 总时长。
  /// 单击唤出完整控制面板后由控制面板进度条替代。
  Widget _buildMiniProgressBar() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Consumer<VideoPlayerState>(
            builder: (context, videoState, child) {
              final bool hasVideo = videoState.hasVideo;
              final double pos = hasVideo &&
                      videoState.duration.inMilliseconds > 0
                  ? (videoState.position.inMilliseconds /
                          videoState.duration.inMilliseconds)
                      .clamp(0.0, 1.0)
                  : 0.0;
              final String cur = _fmtDuration(videoState.position);
              final String total = _fmtDuration(videoState.duration);
              return Row(
                children: [
                  Text(
                    cur,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      shadows: [Shadow(color: Colors.black87, blurRadius: 3)],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final double barWidth = constraints.maxWidth;
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onHorizontalDragStart: (d) {
                            _panelBarStartRatio =
                                (d.localPosition.dx / barWidth)
                                    .clamp(0.0, 1.0);
                          },
                          onHorizontalDragUpdate: (d) {
                            final v = Provider.of<VideoPlayerState>(context,
                                listen: false);
                            if (!v.hasVideo ||
                                v.duration.inMilliseconds <= 0) {
                              return;
                            }
                            final ratio = (_panelBarStartRatio +
                                    d.delta.dx / barWidth)
                                .clamp(0.0, 1.0);
                            v.seekTo(v.duration * ratio);
                          },
                          child: Container(
                            height: double.infinity,
                            alignment: Alignment.center,
                            child: Container(
                              height: 2.5,
                              color: Colors.black.withValues(alpha: 0.35),
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor: pos,
                                child: Container(
                                  color: Colors.white.withValues(alpha: 0.9),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    total,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      shadows: [Shadow(color: Colors.black87, blurRadius: 3)],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }"""),
    # --- 2d. 左右滑快进快退时不再弹出控制面板（常驻条实时显示进度） ---
    ("""    _seekDragAccum = 0.0;
    // [QBSenHook] v8.5: 快进快退时显示控制面板（含可拖动进度条），3 秒自动隐藏
    _showControlPanel();
  }""",
     """    _seekDragAccum = 0.0;
    // [QBSenHook] v8.11: 底部常驻进度条已实时显示进度，快进快退时不再弹出控制面板
  }"""),
])

# ============ 3. emby_service.dart：收藏空结果重试 ============
es = r'lib/services/emby_service.dart'
apply(es, [
    ("""      // [QBSenHook] v8.0: 全量加载——分页循环拉取直到 TotalRecordCount（limit<=0 表示全量）
      final pageSize = limit > 0 ? limit : 500;
      final all = <EmbyMediaItem>[];
      var startIndex = 0;
      while (true) {
        final pagePath = '$path&StartIndex=$startIndex&Limit=$pageSize';
        final response = await _makeAuthenticatedRequest(pagePath);
        if (response.statusCode != 200) {
          DebugLogService().addLog('EmbyService: 获取刷片条目失败 HTTP ');
          break;
        }
        final data = json.decode(response.body);
        final items = data['Items'];
        if (items is! List || items.isEmpty) break;
        all.addAll(items
            .map((e) => EmbyMediaItem.fromJson(e))
            .where((e) => !e.isFolder));
        final total = data['TotalRecordCount'];
        startIndex += items.length;
        if (limit > 0) break;
        if (total is num && startIndex >= total) break;
        if (startIndex >= 5000) break; // 安全上限，防止异常服务端死循环
      }""",
     """      // [QBSenHook] v8.0: 全量加载——分页循环拉取直到 TotalRecordCount（limit<=0 表示全量）
      final pageSize = limit > 0 ? limit : 500;
      final all = <EmbyMediaItem>[];
      Future<void> fetchAllFrom(String p) async {
        var idx = 0;
        while (true) {
          final pagePath = '$p&StartIndex=$idx&Limit=$pageSize';
          final response = await _makeAuthenticatedRequest(pagePath);
          if (response.statusCode != 200) {
            DebugLogService().addLog(
                'EmbyService: 获取刷片条目失败 HTTP ${response.statusCode}');
            break;
          }
          final data = json.decode(response.body);
          final items = data['Items'];
          if (items is! List || items.isEmpty) break;
          all.addAll(items
              .map((e) => EmbyMediaItem.fromJson(e))
              .where((e) => !e.isFolder));
          final total = data['TotalRecordCount'];
          idx += items.length;
          if (limit > 0) break;
          if (total is num && idx >= total) break;
          if (idx >= 5000) break; // 安全上限，防止异常服务端死循环
        }
      }
      await fetchAllFrom(path);
      // [QBSenHook] v8.11: 收藏页——部分服务端不认 Filters=IsFavorite 返回空，
      // 去掉过滤器重试一次，再由下方客户端按 UserData.IsFavorite 过滤兜底。
      if (favoritesOnly && all.isEmpty) {
        final retryPath = path.replace('&Filters=IsFavorite', '');
        await fetchAllFrom(retryPath);
      }"""),
])

# ============ 4. player_settings_content.dart：新增缓存设置 ============
ps = r'lib/settings/pages/player_settings_content.dart'
apply(ps, [
    # --- 4a. state 字段 ---
    ("""  static const int _minSkipSeconds = 10;
  static const int _maxSkipSeconds = 600;""",
     """  static const int _minSkipSeconds = 10;
  static const int _maxSkipSeconds = 600;
  // [QBSenHook] v8.11: 播放预缓存设置（秒 / MB）
  double _precacheBufferSecs =
      PlayerFactory.defaultPrecacheBufferDurationSeconds.toDouble();
  double _precacheBufferSizeMb =
      PlayerFactory.defaultPrecacheBufferSizeMb.toDouble();"""),
    # --- 4b. didChangeDependencies 加载 ---
    ("""    _loadPlayerKernelSettings();
    _loadMacOSNativeVideoSettings();
    _loadAndroidAudioOutputSettings();
    _loadErikaAndroidOutputSettings();
  }""",
     """    _loadPlayerKernelSettings();
    _loadMacOSNativeVideoSettings();
    _loadAndroidAudioOutputSettings();
    _loadErikaAndroidOutputSettings();
    _loadPrecacheSettings();
  }

  Future<void> _loadPrecacheSettings() async {
    if (!mounted) return;
    setState(() {
      _precacheBufferSecs =
          PlayerFactory.getPrecacheBufferDurationSeconds().toDouble();
      _precacheBufferSizeMb = PlayerFactory.getPrecacheBufferSizeMb().toDouble();
    });
  }"""),
    # --- 4c. 内核卡片后插入缓存滑块分组 ---
    ("""                dropdownKey: _playerKernelDropdownKey,
              ),
              Divider(
                  color: colorScheme.onSurface.withValues(alpha: 0.12),
                  height: 1),
            ],
            if (visibleKernelType == PlayerKernelType.erika) ...[""",
     """                dropdownKey: _playerKernelDropdownKey,
              ),
              Divider(
                  color: colorScheme.onSurface.withValues(alpha: 0.12),
                  height: 1),
            ],
            // [QBSenHook] v8.11: 播放网络缓存设置（缓解高码率视频卡顿）
            if (!kIsWeb && !globals.isTvOS) ...[
              AdaptiveSettingsTile.slider(
                title: '播放预缓存时长（秒）',
                subtitle: '越大缓冲越充分，高码率/慢速 NAS 更流畅；受内存限制',
                icon: Ionicons.battery_charging_outline,
                value: _precacheBufferSecs,
                min: PlayerFactory.minPrecacheBufferDurationSeconds.toDouble(),
                max: PlayerFactory.maxPrecacheBufferDurationSeconds.toDouble(),
                divisions:
                    PlayerFactory.maxPrecacheBufferDurationSeconds -
                        PlayerFactory.minPrecacheBufferDurationSeconds,
                labelFormatter: (v) => '${v.round()} 秒',
                onChanged: (v) {
                  setState(() => _precacheBufferSecs = v);
                  PlayerFactory.savePrecacheBufferDurationSeconds(v.round());
                },
              ),
              Divider(
                  color: colorScheme.onSurface.withValues(alpha: 0.12),
                  height: 1),
              AdaptiveSettingsTile.slider(
                title: '播放预缓存大小（MB）',
                subtitle: '网络预读缓存上限，越大越流畅但占内存更多',
                icon: Ionicons.hardware_chip_outline,
                value: _precacheBufferSizeMb,
                min: PlayerFactory.minPrecacheBufferSizeMb.toDouble(),
                max: PlayerFactory.maxPrecacheBufferSizeMb.toDouble(),
                divisions:
                    (PlayerFactory.maxPrecacheBufferSizeMb -
                            PlayerFactory.minPrecacheBufferSizeMb) ~/
                        4,
                labelFormatter: (v) => '${v.round()} MB',
                onChanged: (v) {
                  setState(() => _precacheBufferSizeMb = v);
                  PlayerFactory.savePrecacheBufferSizeMb(v.round());
                },
              ),
              Divider(
                  color: colorScheme.onSurface.withValues(alpha: 0.12),
                  height: 1),
            ],
            if (visibleKernelType == PlayerKernelType.erika) ...["""),
])

print('ALL PATCHES APPLIED')
