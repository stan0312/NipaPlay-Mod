import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:nipaplay/models/emby_model.dart';
import 'package:nipaplay/models/media_server_playback.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/pages/emby_folder_browser_page.dart';
import 'package:nipaplay/pages/emby_fullscreen_player_page.dart' show EmbyFitMode;
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/services/playback_source_service.dart';
import 'package:nipaplay/utils/screen_orientation_manager.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/widgets/media_server_network_image.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [QBSenHook] 抖音式刷片页：竖屏上下滑浏览 Emby 媒体库/收藏/播放列表/文件夹。
/// 数据来自 NAS Emby 服务端，播放内嵌在刷片页内（不跳转播放器页），
/// 滑动到哪一页就自动播放哪一页。
class EmbySwipePage extends StatefulWidget {
  const EmbySwipePage({
    super.key,
    this.title = '刷片',
    this.initialLibraryId,
    this.favoritesOnly = false,
    this.playlistId,
    this.playlistName,
    this.initialParentId,
    this.parentName,
    this.initialItemId,
  });

  final String title;
  final String? initialLibraryId;
  final bool favoritesOnly;
  final String? playlistId;
  final String? playlistName;

  /// 文件夹模式：从文件夹浏览页进入，在此文件夹内上下滑播放
  final String? initialParentId;
  final String? parentName;

  /// [QBSenHook] v7.5.3: 初始定位条目：进入后直接跳到该条目并从它开始播放
  final String? initialItemId;

  @override
  State<EmbySwipePage> createState() => _EmbySwipePageState();
}

/// 排序方式
enum SwipeSort {
  dateCreated('按时间添加'),
  name('按文件名'),
  random('随机'),
  size('按大小');

  const SwipeSort(this.label);
  final String label;
}

/// [QBSenHook] v7.5.3: 视频区左右边缘手势：左侧调亮度、右侧调音量（尽量靠边）
enum EdgeGestureSide { left, right }

class _EmbySwipePageState extends State<EmbySwipePage> {
  final PageController _pageController = PageController();
  List<EmbyMediaItem> _items = [];
  bool _loading = true;
  String? _error;
  int _currentIndex = 0;

  // 数据源状态
  String? _libraryId;
  bool _favoritesOnly = false;
  String? _playlistId;
  String? _playlistName;
  String? _parentId; // 文件夹模式
  String? _parentName;

  // 排序
  SwipeSort _sort = SwipeSort.dateCreated;

  List<EmbyLibrary> _libraries = [];
  List<EmbyLibrary> _playlists = [];

  // 本地收藏覆盖（避免重建不可变模型）
  final Set<String> _favoriteOn = {};
  final Set<String> _favoriteOff = {};

  // 内嵌播放状态
  String? _playingItemId;
  // 正在加载中的条目（initializePlayer 尚未完成时立即反馈）
  String? _pendingPlayId;
  // 当前条目的播放错误（有值时在卡片上显示红字提示）
  String? _playbackError;
  int _playbackGeneration = 0;

  // [QBSenHook] v7.5.2: 单击调出的播放控件面板（3 秒自动隐藏）
  bool _controlsVisible = false;
  Timer? _controlsTimer;
  // 画面尺寸模式
  EmbyFitMode _fitMode = EmbyFitMode.original;
  // [QBSenHook] v7.6: 屏幕方向适配开关（false=竖屏适配[默认]，true=横屏适配）
  bool _landscapeView = false;

  // [QBSenHook] v7.5.3: 缓存播放器引用，dispose 时停止播放（退出后立即无声音）
  late final VideoPlayerState _videoState;
  // 持续 seek 拖拽状态：起始位置与累计偏移
  bool _seekDragging = false;
  // [QBSenHook] v7.5.4: 左右滑快进快退时，底部显示极细播放进度条
  bool _seekBarVisible = false;
  Duration _seekDragStartPos = Duration.zero;
  double _seekDragAccum = 0.0;
  // 左右边缘手势起始模式：brightness / volume
  String? _edgeDragMode;

  @override
  void initState() {
    super.initState();
    // [QBSenHook] v7.5.1: 抖音式刷片页锁定竖屏，防止播放横屏视频时自动旋转
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    // [QBSenHook] v7.5.4: 强制竖屏播放（播放回调不再切横屏）
    ScreenOrientationManager.instance.forcePortraitPlayback = true;
    _videoState = Provider.of<VideoPlayerState>(context, listen: false);
    _libraryId = widget.initialLibraryId;
    _favoritesOnly = widget.favoritesOnly;
    _playlistId = widget.playlistId;
    _playlistName = widget.playlistName;
    _parentId = widget.initialParentId;
    _parentName = widget.parentName;
    _restorePreferences();
    _load();
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    // [QBSenHook] v7.5.3: 退出刷片页立即停止播放，避免"退出后仍有声音"
    _playbackGeneration++;
    try {
      unawaited(_videoState.stop());
    } catch (e) {
      debugPrint('退出刷片页停止播放失败: $e');
    }
    // [QBSenHook] v7.5.1: 离开刷片页恢复竖屏（全局默认竖屏）
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    // [QBSenHook] v7.5.4: 释放强制竖屏标志（全屏播放器页按视频尺寸选方向）
    ScreenOrientationManager.instance.forcePortraitPlayback = false;
    _pageController.dispose();
    _playingItemId = null;
    super.dispose();
  }

  Future<void> _restorePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      // 仅在非显式指定来源时恢复上次选择；initialItemId 场景（详情页直进）不覆盖来源
      if (widget.initialItemId == null &&
          widget.initialLibraryId == null &&
          !widget.favoritesOnly &&
          widget.playlistId == null &&
          widget.initialParentId == null) {
        final type = prefs.getString('qbsen_swipe_source_type') ?? 'all';
        final id = prefs.getString('qbsen_swipe_source_id');
        setState(() {
          switch (type) {
            case 'favorites':
              _favoritesOnly = true;
              break;
            case 'playlist':
              _playlistId = id;
              break;
            case 'library':
              _libraryId = id;
              break;
            case 'folder':
              _parentId = id;
              _parentName = prefs.getString('qbsen_swipe_source_name');
              break;
            default:
              break;
          }
        });
      }
      final sortName = prefs.getString('qbsen_swipe_sort');
      if (sortName != null) {
        for (final s in SwipeSort.values) {
          if (s.name == sortName) {
            setState(() => _sort = s);
            break;
          }
        }
      }
    } catch (e) {
      debugPrint('刷片恢复偏好失败: $e');
    }
  }

  Future<void> _savePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String type;
      String? id;
      String? name;
      if (_parentId != null) {
        type = 'folder';
        id = _parentId;
        name = _parentName;
      } else if (_playlistId != null) {
        type = 'playlist';
        id = _playlistId;
        name = _playlistName;
      } else if (_favoritesOnly) {
        type = 'favorites';
      } else if (_libraryId != null) {
        type = 'library';
        id = _libraryId;
      } else {
        type = 'all';
      }
      await prefs.setString('qbsen_swipe_source_type', type);
      if (id != null) {
        await prefs.setString('qbsen_swipe_source_id', id);
      } else {
        await prefs.remove('qbsen_swipe_source_id');
      }
      if (name != null) {
        await prefs.setString('qbsen_swipe_source_name', name);
      }
      await prefs.setString('qbsen_swipe_sort', _sort.name);
    } catch (e) {
      debugPrint('保存刷片偏好失败: $e');
    }
  }

  String get _sourceTitle {
    if (_parentId != null) return _parentName ?? '文件夹';
    if (_playlistId != null) return _playlistName ?? '播放列表';
    if (_favoritesOnly) return '我的收藏';
    if (_libraryId != null) {
      for (final l in _libraries) {
        if (l.id == _libraryId) return l.name;
      }
      return '媒体库';
    }
    return '全部';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _playbackError = null;
    });
    await _stopPlayback();
    try {
      final service = EmbyService.instance;
      // 文件夹模式用 parentId 作为数据源
      final sourceId = _parentId ?? _libraryId;
      final items = await service.getSwipeItems(
        libraryId: sourceId,
        favoritesOnly: _favoritesOnly,
        playlistId: _playlistId,
        sortBy: _sort.name,
        limit: 500,
      );
      if (!mounted) return;
      // [QBSenHook] v7.5.3: initialItemId 定位到该条目（详情页/文件夹点视频直进）
      var startIndex = 0;
      if (widget.initialItemId != null) {
        final idx = items.indexWhere((e) => e.id == widget.initialItemId);
        if (idx >= 0) startIndex = idx;
      }
      setState(() {
        _items = items;
        _loading = false;
        _currentIndex = startIndex;
      });
      if (_pageController.hasClients) {
        _pageController.jumpToPage(startIndex);
      }
      _loadSourceOptions();
      _savePreferences();
      if (items.isNotEmpty && startIndex < items.length) {
        _autoPlay(items[startIndex]);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _loadSourceOptions() async {
    final service = EmbyService.instance;
    final libraries = service.availableLibraries;
    final playlists = await service.getPlaylists();
    if (!mounted) return;
    setState(() {
      _libraries = libraries;
      _playlists = playlists;
    });
  }

  // ============ 内嵌播放 ============

  Future<void> _autoPlay(EmbyMediaItem item) async {
    final gen = ++_playbackGeneration;
    // 立即反馈：正在加载播放，避免用户以为点击没反应
    if (mounted) {
      setState(() {
        _pendingPlayId = item.id;
        _playingItemId = null;
        _playbackError = null;
      });
    }
    try {
      // [QBSenHook] v7.5.3: 续播——从 Emby 服务端的观看进度(PlaybackPositionTicks)恢复
      // ticks 转毫秒 = ticks / 10000
      final resumeMs =
          (item.userData?.playbackPositionTicks ?? 0.0) / 10000.0;
      final resumePositionMs = resumeMs > 0 ? resumeMs.round() : 0;
      final historyItem = WatchHistoryItem(
        filePath: 'emby://${item.id}',
        animeName: item.name,
        episodeTitle: null,
        watchProgress: 0.0,
        lastPosition: resumePositionMs,
        duration: 0,
        lastWatchTime: DateTime.now(),
        animeId: null,
        isFromScan: false,
      );
      final videoState = Provider.of<VideoPlayerState>(context, listen: false);
      // [QBSenHook] v7.3: 内嵌播放必须绑定本页 context（视频 tab 已移除，
      // 不再有播放器页帮忙 setContext）。
      videoState.setContext(context);
      // 预创建播放会话；失败不放弃，交给播放器内部处理
      PlaybackSession? session;
      try {
        session = await EmbyService.instance
            .createPlaybackSession(itemId: item.id);
      } catch (e) {
        debugPrint('刷片预创建播放会话失败(将由播放器内部处理): $e');
      }
      if (!mounted || gen != _playbackGeneration) return;
      final playable = PlayableItem(
        videoPath: historyItem.filePath,
        title: item.name,
        historyItem: historyItem,
        playbackSession: session,
      );
      final detailContext =
          await PlaybackSourceService.resolve(context, playable);
      if (!mounted || gen != _playbackGeneration) return;
      await videoState.initializePlayer(
        playable.videoPath,
        historyItem: historyItem,
        playbackSession: session,
        playbackDetailContext: detailContext,
      );
      if (!mounted || gen != _playbackGeneration) return;
      // [QBSenHook] v7.3: initializePlayer 内部失败会置 error 而非抛异常，
      // 必须显式检查，否则卡片会一直只显示缩略图、用户看不到原因。
      final initError = videoState.error;
      final hasVideo = videoState.hasVideo;
      if (initError != null && initError.trim().isNotEmpty) {
        setState(() {
          _playingItemId = null;
          _pendingPlayId = null;
          _playbackError = initError.trim();
        });
        return;
      }
      if (!hasVideo) {
        setState(() {
          _playingItemId = null;
          _pendingPlayId = null;
          _playbackError = '播放器未能建立视频画面';
        });
        return;
      }
      setState(() {
        _playingItemId = item.id;
        _pendingPlayId = null;
        _playbackError = null;
      });
      // 自动开始播放（initializePlayer 已就绪，直接 play）
      // [QBSenHook] v7.3: play() 是同步 void，不可 await
      try {
        videoState.play();
      } catch (e) {
        debugPrint('刷片 play() 失败: $e');
      }
    } catch (e, s) {
      debugPrint('刷片自动播放失败: $e\n$s');
      if (mounted && gen == _playbackGeneration) {
        setState(() {
          _playingItemId = null;
          _pendingPlayId = null;
          _playbackError = '播放出错: $e';
        });
      }
    }
  }

  Future<void> _stopPlayback() async {
    _playbackGeneration++;
    if (!mounted) return;
    try {
      final videoState =
          Provider.of<VideoPlayerState>(context, listen: false);
      await videoState.stop();
    } catch (e) {
      debugPrint('停止刷片播放失败: $e');
    }
    _playingItemId = null;
    _pendingPlayId = null;
    _playbackError = null;
  }

  /// [QBSenHook] v7.5.4: 刷片页页内画面渲染 —— 不进入全屏页，
  /// 方向（竖屏/横屏）+ 尺寸模式在页面内直接作用于画面。
  Widget _buildVideoSurface() {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        if (!videoState.hasVideo) return const SizedBox.shrink();
        final player = videoState.player;
        try {
          if (player.prefersPlatformVideoSurface) {
            final surface = player.buildPlatformVideoSurface(
              debugLabel: 'swipe',
            );
            if (surface != null) return surface;
            return const SizedBox.shrink();
          }
          // [QBSenHook] v7.5.1: 竖屏刷片，宽度优先铺满、不拉伸。
          // 横屏视频 → 宽铺满、上下留白；竖屏视频 → 正常竖屏（高度受限时 contain）。
          final ratio = _videoAspectRatio(videoState) ?? 16 / 9;
          return LayoutBuilder(
            builder: (context, constraints) {
              final double maxW = constraints.maxWidth;
              final double maxH = constraints.maxHeight;
              if (maxW <= 0 || maxH <= 0) return const SizedBox.shrink();
              final Widget texture = ValueListenableBuilder<int?>(
                valueListenable: player.textureId,
                builder: (context, textureId, child) {
                  if (textureId == null || textureId < 0) {
                    return const SizedBox.shrink();
                  }
                  return SizedBox.expand(
                    child: Texture(
                      textureId: textureId,
                      filterQuality: FilterQuality.medium,
                    ),
                  );
                },
              );

              // [QBSenHook] v7.6: 横屏适配开关——视频旋转到横向后 cover 铺满（等效横屏观看）
              if (_landscapeView) {
                return SizedBox.expand(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    clipBehavior: Clip.hardEdge,
                    child: RotatedBox(
                      quarterTurns: ratio > 1.0 ? 0 : 1,
                      child: SizedBox(
                        width: maxW,
                        height: maxW / ratio,
                        child: texture,
                      ),
                    ),
                  ),
                );
              }

              // [QBSenHook] v7.5.4: 横屏视频（宽>高）自动旋转 90° 竖着铺满全屏，
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
              }

              // 竖屏模式：按 _fitMode 控制画面尺寸
              switch (_fitMode) {
                case EmbyFitMode.cover:
                  return SizedBox.expand(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      clipBehavior: Clip.hardEdge,
                      child: SizedBox(
                        width: maxW,
                        height: maxW / ratio,
                        child: texture,
                      ),
                    ),
                  );
                case EmbyFitMode.r16_9:
                case EmbyFitMode.r4_3:
                case EmbyFitMode.r1_1:
                case EmbyFitMode.r9_16:
                  final double targetRatio = _fitModeRatio(_fitMode);
                  final double hTarget = maxW / targetRatio;
                  return Center(
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(
                        width: maxW,
                        height: hTarget,
                        child: texture,
                      ),
                    ),
                  );
                case EmbyFitMode.original:
                  break;
              }
              // 原始模式：宽铺满（横屏视频上下留白），高度受限时 contain
              final double hForWidth = maxW / ratio;
              if (hForWidth <= maxH) {
                return Align(
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: maxW,
                    height: hForWidth,
                    child: texture,
                  ),
                );
              }
              return FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: maxW,
                  height: hForWidth,
                  child: texture,
                ),
              );
            },
          );
        } catch (e) {
          return const SizedBox.shrink();
        }
      },
    );
  }

  /// [QBSenHook] v7.5.4: 尺寸模式对应的目标宽高比。
  double _fitModeRatio(EmbyFitMode mode) {
    switch (mode) {
      case EmbyFitMode.r16_9:
        return 16 / 9;
      case EmbyFitMode.r4_3:
        return 4 / 3;
      case EmbyFitMode.r1_1:
        return 1.0;
      case EmbyFitMode.r9_16:
        return 9 / 16;
      default:
        return 16 / 9;
    }
  }

  /// 从播放器媒体信息读取视频宽高比（未知时返回 null，走 16:9 默认）。
  double? _videoAspectRatio(VideoPlayerState videoState) {
    try {
      final video = videoState.player.mediaInfo.video;
      if (video == null || video.isEmpty) return null;
      final codec = video.first.codec;
      final w = codec.width;
      final h = codec.height;
      if (w <= 0 || h <= 0) return null;
      return w / h;
    } catch (_) {
      return null;
    }
  }

  // ============ 收藏 ============

  bool _isFavorite(EmbyMediaItem item) {
    if (_favoriteOn.contains(item.id)) return true;
    if (_favoriteOff.contains(item.id)) return false;
    return item.userData?.isFavorite ?? false;
  }

  Future<void> _toggleFavorite(EmbyMediaItem item) async {
    final target = !_isFavorite(item);
    final ok = await EmbyService.instance.toggleFavorite(
      item.id,
      isFavorite: _isFavorite(item),
    );
    if (!mounted) return;
    if (ok) {
      setState(() {
        if (target) {
          _favoriteOn.add(item.id);
          _favoriteOff.remove(item.id);
        } else {
          _favoriteOff.add(item.id);
          _favoriteOn.remove(item.id);
        }
      });
      _showTip(target ? '已收藏' : '已取消收藏');
    } else {
      _showTip('收藏操作失败');
    }
  }

  void _showTip(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ============ 数据源 + 排序选择 ============

  void _openSourcePicker() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_open_rounded),
              title: const Text('以文件夹方式浏览'),
              subtitle: const Text('按目录结构浏览并上下滑播放'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.pop(sheetContext);
                _openFolderBrowser();
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.grid_view_rounded),
              title: const Text('全部'),
              selected: _parentId == null &&
                  _libraryId == null &&
                  !_favoritesOnly &&
                  _playlistId == null,
              onTap: () {
                Navigator.pop(sheetContext);
                _switchSource();
              },
            ),
            ListTile(
              leading: const Icon(Icons.favorite_rounded,
                  color: Colors.redAccent),
              title: const Text('我的收藏'),
              selected: _favoritesOnly,
              onTap: () {
                Navigator.pop(sheetContext);
                _switchSource(favoritesOnly: true);
              },
            ),
            if (_playlists.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Text(
                  '播放列表',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
              for (final p in _playlists)
                ListTile(
                  leading: const Icon(Icons.playlist_play_rounded),
                  title: Text(p.name),
                  selected: _playlistId == p.id,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _switchSource(playlistId: p.id, playlistName: p.name);
                  },
                ),
            ],
            if (_libraries.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Text(
                  '媒体库',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
              for (final l in _libraries)
                ListTile(
                  leading: const Icon(Icons.video_library_rounded),
                  title: Text(l.name),
                  selected: _parentId == null &&
                      _libraryId == l.id &&
                      !_favoritesOnly,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _switchSource(libraryId: l.id);
                  },
                ),
            ],
            const Divider(),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Text(
                '排序方式',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            for (final s in SwipeSort.values)
              RadioListTile<SwipeSort>(
                value: s,
                groupValue: _sort,
                title: Text(s.label),
                onChanged: (v) {
                  if (v == null) return;
                  Navigator.pop(sheetContext);
                  _switchSort(v);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _openFolderBrowser() {
    // [QBSenHook] v7.5.4: 文件夹浏览页用 Cupertino 路由，支持左缘右滑返回
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => const EmbyFolderBrowserPage(),
      ),
    );
  }

  void _switchSort(SwipeSort sort) {
    _sort = sort;
    _savePreferences();
    _load();
  }

  void _switchSource({
    String? libraryId,
    bool favoritesOnly = false,
    String? playlistId,
    String? playlistName,
  }) {
    _libraryId = libraryId;
    _favoritesOnly = favoritesOnly;
    _playlistId = playlistId;
    _playlistName = playlistName;
    _parentId = null;
    _parentName = null;
    _savePreferences();
    _load();
  }

  // ============ UI ============

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) return;
        _stopPlayback();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            if (_loading)
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            else if (_error != null)
              _buildError()
            else if (_items.isEmpty)
              _buildEmpty()
            else
              PageView.builder(
                controller: _pageController,
                scrollDirection: Axis.vertical,
                itemCount: _items.length,
                onPageChanged: (i) {
                  setState(() => _currentIndex = i);
                  if (i >= 0 && i < _items.length) {
                    _autoPlay(_items[i]);
                  }
                },
                itemBuilder: (context, index) =>
                    _buildSwipeCard(_items[index], index),
              ),
            // 顶部栏
            _buildTopBar(),
            // 页码指示
            if (_items.isNotEmpty)
              Positioned(
                top: MediaQuery.of(context).padding.top + 10,
                right: 14,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_currentIndex + 1}/${_items.length}',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    // [QBSenHook] v7.5.4: 顶部信息栏半透明圆角、左右留边、窄化，避开灵动岛
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 8,
          left: 14,
          right: 14,
          bottom: 4,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.38),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.15),
              width: 0.6,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: GestureDetector(
                  onTap: _openSourcePicker,
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          _sourceTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Icon(Icons.arrow_drop_down_rounded,
                          color: Colors.white),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                onPressed: _load,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSwipeCard(EmbyMediaItem item, int index) {
    final service = EmbyService.instance;
    final imageUri = item.imagePrimaryTag != null
        ? Uri.tryParse(service.getImageUrl(item.id, tag: item.imagePrimaryTag))
        : null;
    final isPending = _pendingPlayId == item.id;
    final isPlayingNow = _playingItemId == item.id;
    // [QBSenHook] v7.5.5: 实际是否正在播放（暂停时显示播放图标）
    final vState = Provider.of<VideoPlayerState>(context, listen: false);
    final isActuallyPlaying =
        isPlayingNow && vState.status == PlayerStatus.playing;
    final isActiveCard =
        index == _currentIndex && (isPending || isPlayingNow);
    final showPlaybackError =
        _playbackError != null && index == _currentIndex;
    // [QBSenHook] v7.5.3: 单击调出播放控件面板（3秒自动隐藏）、
    // 双击暂停/播放、左右滑持续快进/快退（慢速持续滑动一直快进快退）。
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: _onHorizontalDragStart,
      onHorizontalDragUpdate: _onHorizontalDragUpdate,
      onHorizontalDragEnd: _onHorizontalDragEnd,
      child: Stack(
        fit: StackFit.expand,
        children: [
        // 已开始播放：显示视频画面（叠加左右边缘亮度/音量手势区）
        if (isPlayingNow)
          Positioned.fill(child: _buildVideoSurface()),
        // 状态提示条（加载中/播放中/出错时显示）
        if (isActiveCard)
          Positioned(
            left: 12,
            right: 12,
            top: MediaQuery.of(context).padding.top + 128,
            child: _buildPlaybackStatusBanner(),
          ),
        // 播放失败红字提示（当前卡片）
        if (showPlaybackError)
          Positioned(
            left: 16,
            right: 16,
            top: MediaQuery.of(context).padding.top + 200,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.redAccent, width: 1),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline,
                          color: Colors.redAccent, size: 18),
                      SizedBox(width: 6),
                      Text(
                        '播放失败',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _playbackError!,
                    textAlign: TextAlign.center,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        // 背景图（尚未出画面时显示，含加载中）
        if (!isPlayingNow)
          if (imageUri != null)
            MediaServerNetworkImage(
              imageUri,
              fit: BoxFit.cover,
              errorBuilder: (c, e, st) => _buildPlaceholder(item),
            )
          else
            _buildPlaceholder(item),
        // 底部渐变
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.35),
                Colors.black.withValues(alpha: 0.85),
              ],
              stops: const [0.35, 0.65, 1.0],
            ),
          ),
        ),
        // 右侧操作列
        Positioned(
          right: 8,
          bottom: 90,
          child: Column(
            children: [
              _buildActionButton(
                icon: _isFavorite(item)
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: _isFavorite(item) ? Colors.redAccent : Colors.white,
                label: _isFavorite(item) ? '已收藏' : '收藏',
                onTap: () => _toggleFavorite(item),
              ),
              const SizedBox(height: 18),
              _buildActionButton(
                icon: isPending
                    ? Icons.hourglass_top_rounded
                    : (isActuallyPlaying
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_circle_fill_rounded),
                color: Colors.white,
                label: isPending
                    ? '加载中'
                    : (isActuallyPlaying ? '暂停' : '播放'),
                onTap: () {
                  if (isPending) return;
                  if (isActuallyPlaying) {
                    _togglePlayPause();
                  } else if (isPlayingNow) {
                    _togglePlayPause();
                  } else {
                    _autoPlay(item);
                  }
                },
              ),
              const SizedBox(height: 18),
              _buildActionButton(
                icon: Icons.aspect_ratio_rounded,
                color: Colors.white,
                label: _fitMode.label,
                onTap: _cycleFitMode,
              ),
              const SizedBox(height: 18),
              _buildActionButton(
                icon: Icons.screen_rotation_rounded,
                color: Colors.white,
                label: _landscapeView ? '横屏' : '竖屏',
                onTap: () => setState(() => _landscapeView = !_landscapeView),
              ),
            ],
          ),
        ),
        // [QBSenHook] v7.5.5: 文件名移到上侧（顶部信息栏下方）
        Positioned(
          left: 18,
          right: 90,
          top: MediaQuery.of(context).padding.top + 56,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.95),
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  shadows: const [
                    Shadow(color: Colors.black87, blurRadius: 6),
                  ],
                ),
              ),
              if (item.productionYear != null ||
                  item.communityRating != null) ...[
                const SizedBox(height: 5),
                Text(
                  [
                    if (item.productionYear != null) '${item.productionYear}',
                    if (item.communityRating != null)
                      '★ ${item.communityRating}',
                  ].join(' · '),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12,
                    shadows: const [
                      Shadow(color: Colors.black87, blurRadius: 4),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        // [QBSenHook] v7.5.4: 左右滑快进快退时底部极细播放进度条
        if (_seekBarVisible) _buildSeekBar(),
        ],
      ),
    );
  }

  /// [QBSenHook] v7.5.4: 底部极细一条播放进度条（左右滑快进快退时显示）
  Widget _buildSeekBar() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: IgnorePointer(
        child: Consumer<VideoPlayerState>(
          builder: (context, videoState, child) {
            final double pos =
                videoState.hasVideo && videoState.duration.inMilliseconds > 0
                    ? (videoState.position.inMilliseconds /
                            videoState.duration.inMilliseconds)
                        .clamp(0.0, 1.0)
                    : 0.0;
            return Container(
              height: 2.5,
              color: Colors.black.withValues(alpha: 0.35),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: pos,
                child: Container(
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// [QBSenHook] v7.4: 切换播放/暂停（双击触发）。
  void _togglePlayPause() {
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    if (!videoState.hasVideo) return;
    if (videoState.status == PlayerStatus.playing) {
      videoState.pause();
    } else {
      videoState.play();
    }
  }

  /// [QBSenHook] v7.5.2: 单击调出播放控件面板，3 秒后自动隐藏。
  void _showControlPanel() {
    if (!mounted) return;
    setState(() => _controlsVisible = true);
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  /// 面板按钮动作：执行操作并重置 3 秒隐藏计时。
  void _panelAction(VoidCallback action) {
    action();
    _showControlPanel();
  }

  /// [QBSenHook] v7.5.2: 循环切换画面尺寸模式。
  void _cycleFitMode() {
    setState(() {
      final values = EmbyFitMode.values;
      _fitMode = values[(_fitMode.index + 1) % values.length];
    });
  }

  /// [QBSenHook] v7.5.2: 播放控件面板（底部浮层，2 秒自动隐藏）。
  Widget _buildControlPanel() {
    // [QBSenHook] v7.5.4: 播放控件面板贴底一条、窄化、半透明圆角（仅顶部圆角）
    return Positioned(
      left: 14,
      right: 14,
      bottom: 0,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.15),
              width: 0.6,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // [QBSenHook] v7.5.4: 尺寸调整行（抖音页不进入全屏，仅页内调整画面尺寸）
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _panelButton(
                    '尺寸:${_fitMode.label}',
                    false,
                    () => _panelAction(_cycleFitMode),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // 播放控制行
              Consumer<VideoPlayerState>(
                builder: (context, videoState, child) {
                  final bool isPlaying =
                      videoState.status == PlayerStatus.playing;
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // [QBSenHook] v7.5.4: 去掉快进/快退按钮，左右滑手势已可快进快退
                      IconButton(
                        icon: Icon(
                          isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                          size: 36,
                        ),
                        onPressed: () => _panelAction(_togglePlayPause),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _panelButton(
      String label, bool selected, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.white24 : Colors.white12,
          borderRadius: BorderRadius.circular(8),
          border: selected ? Border.all(color: Colors.white70) : null,
        ),
        child: Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
      ),
    );
  }

  /// [QBSenHook] v7.5: 左右滑快进/快退（左滑快进、右滑快退，各 10 秒）。
  // [QBSenHook] v7.5.3: 左右滑持续快进/快退——
  // 按下记录起点，拖动每累计 24px 跳 5 秒（慢速持续滑动就一直快进/快退），松手结束。
  void _onHorizontalDragStart(DragStartDetails details) {
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    if (!videoState.hasVideo) return;
    _seekDragging = true;
    _seekDragStartPos = videoState.position;
    _seekDragAccum = 0.0;
    if (mounted) setState(() => _seekBarVisible = true);
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    if (!_seekDragging || !videoState.hasVideo) return;
    _seekDragAccum += details.delta.dx;
    const double pxPerStep = 24.0;
    const int secondsPerStep = 5;
    if (_seekDragAccum.abs() >= pxPerStep) {
      final steps = (_seekDragAccum / pxPerStep).round();
      final target =
          _seekDragStartPos + Duration(seconds: steps * secondsPerStep);
      videoState.seekTo(target);
      _seekDragStartPos = videoState.position;
      _seekDragAccum = 0.0;
    }
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    _seekDragging = false;
    _seekDragAccum = 0.0;
    if (mounted) setState(() => _seekBarVisible = false);
  }

  // [QBSenHook] v7.5.3: 视频区左右边缘手势条——左边缘上下滑调亮度、
  // 右边缘上下滑调音量，宽度约为屏宽 22%（尽量靠边），中间区域留给上下滑切页。
  Widget _buildEdgeGestureArea(EdgeGestureSide side) {
    return Positioned(
      left: side == EdgeGestureSide.left ? 0 : null,
      right: side == EdgeGestureSide.right ? 0 : null,
      top: 0,
      bottom: 0,
      width: MediaQuery.of(context).size.width * 0.22,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _showControlPanel,
        onDoubleTap: _togglePlayPause,
        onVerticalDragStart: (details) {
          _edgeDragMode = side == EdgeGestureSide.left
              ? 'brightness'
              : 'volume';
          if (_edgeDragMode == 'brightness') {
            _videoState.startBrightnessDrag();
          } else {
            _videoState.startVolumeDrag();
          }
        },
        onVerticalDragUpdate: (details) {
          if (_edgeDragMode == 'brightness') {
            _videoState.updateBrightnessOnDrag(details.delta.dy, context);
          } else if (_edgeDragMode == 'volume') {
            _videoState.updateVolumeOnDrag(details.delta.dy, context);
          }
        },
        onVerticalDragEnd: (details) {
          if (_edgeDragMode == 'brightness') {
            _videoState.endBrightnessDrag();
          } else if (_edgeDragMode == 'volume') {
            _videoState.endVolumeDrag();
          }
          _edgeDragMode = null;
        },
        onVerticalDragCancel: () {
          if (_edgeDragMode == 'brightness') {
            _videoState.endBrightnessDrag();
          } else if (_edgeDragMode == 'volume') {
            _videoState.endVolumeDrag();
          }
          _edgeDragMode = null;
        },
      ),
    );
  }

  Widget _buildPlaybackStatusBanner() {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        String? text;
        switch (videoState.status) {
          case PlayerStatus.loading:
            text = '正在加载播放…';
            break;
          case PlayerStatus.recognizing:
            text = '正在准备…';
            break;
          case PlayerStatus.ready:
          case PlayerStatus.playing:
            return const SizedBox.shrink();
          case PlayerStatus.paused:
            text = '已暂停';
            break;
          case PlayerStatus.error:
            text = '播放出错：${videoState.error ?? '未知错误'}';
            break;
          default:
            return const SizedBox.shrink();
        }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Icon(
            icon,
            color: color,
            size: 30,
            shadows: const [Shadow(color: Colors.black54, blurRadius: 8)],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder(EmbyMediaItem item) {
    return Container(
      color: const Color(0xFF1A1A1A),
      alignment: Alignment.center,
      child: Icon(Icons.movie_rounded, color: Colors.white24, size: 64),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded,
              color: Colors.white54, size: 48),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              '加载失败：$_error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: _load, child: const Text('重试')),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.video_library_outlined,
              color: Colors.white38, size: 48),
          const SizedBox(height: 12),
          const Text('这里还没有内容', style: TextStyle(color: Colors.white54)),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _openSourcePicker,
            child: const Text('换个数据源'),
          ),
        ],
      ),
    );
  }
}
