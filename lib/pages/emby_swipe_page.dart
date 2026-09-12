import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:nipaplay/models/emby_model.dart';
import 'package:nipaplay/models/media_server_playback.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/models/swipe_play_record.dart';
import 'package:nipaplay/pages/emby_folder_browser_page.dart';
import 'package:nipaplay/pages/emby_fullscreen_player_page.dart' show EmbyFitMode;
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/services/playback_source_service.dart';
import 'package:nipaplay/utils/screen_orientation_manager.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/widgets/edge_swipe_back.dart';
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
    this.initialSort, // [QBSenHook] v7.8: 外部传入排序
    this.initialSortAscending = false, // [QBSenHook] v7.8: 外部传入排序方向
    this.initialFolderMode = false, // [QBSenHook] v8.5: 来源是否为文件夹模式
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

  /// [QBSenHook] v7.8: 外部传入的排序方式（null 时从偏好恢复）
  final SwipeSort? initialSort;
  final bool initialSortAscending;

  /// [QBSenHook] v8.5: 来源是否为文件夹模式（用于播放记录恢复）
  final bool initialFolderMode;

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

class _EmbySwipePageState extends State<EmbySwipePage>
    with WidgetsBindingObserver {
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
  bool _sortAscending = false; // [QBSenHook] v7.8: 排序方向

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
  // [QBSenHook] v8.13: 左右滑快进快退时临时显示底部细进度条，松手自动隐藏
  bool _seekBarVisible = false;
  Timer? _controlsTimer;
  // 画面尺寸模式
  EmbyFitMode _fitMode = EmbyFitMode.original;
  // [QBSenHook] v7.6: 屏幕方向适配开关（false=竖屏适配[默认]，true=横屏适配）
  bool _landscapeView = false;

  // [QBSenHook] v7.5.3: 缓存播放器引用，dispose 时停止播放（退出后立即无声音）
  late final VideoPlayerState _videoState;
  // 持续 seek 拖拽状态：起始位置与累计偏移
  bool _seekDragging = false;

  Duration _seekDragStartPos = Duration.zero;
  double _seekDragAccum = 0.0;
  // [QBSenHook] v8.5: 控制面板进度条拖动——按下时的比例起点
  double _panelBarStartRatio = 0.0;
  // 左右边缘手势起始模式：brightness / volume
  String? _edgeDragMode;

  @override
  void initState() {
    super.initState();
    // [QBSenHook] v8.5: 退后台时保存播放记录（覆盖"完全退出软件"场景）
    WidgetsBinding.instance.addObserver(this);
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
    // [QBSenHook] v7.8: 外部传入排序优先；未传入时从偏好恢复
    if (widget.initialSort != null) {
      _sort = widget.initialSort!;
      _sortAscending = widget.initialSortAscending;
    }
    _restorePreferences();
    _load();
  }

  @override
  void dispose() {
    // [QBSenHook] v8.5: 返回上一层时保存播放记录
    _savePlayRecord();
    // [QBSenHook] v8.11: 立即恢复竖屏，不等 stop 异步完成（修复偶发退出后横屏）
    ScreenOrientationManager.instance.forcePortraitPlayback = true;
    unawaited(SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]));
    WidgetsBinding.instance.removeObserver(this);
    _controlsTimer?.cancel();
    // [QBSenHook] v7.5.3: 退出刷片页立即停止播放，避免"退出后仍有声音"
    _playbackGeneration++;
    // [QBSenHook] v8.8: 修复"返回后偶发横屏"——若切换视频的 initializePlayer 仍在进行，
    // 其完成时的 setVideoPlayingOrientation 会按 forcePortraitPlayback 决定方向；
    // 因此在 stop 完全结束前保持强制竖屏，stop 完成后释放标志并确保竖屏。
    ScreenOrientationManager.instance.forcePortraitPlayback = true;
    try {
      unawaited(_videoState.stop().whenComplete(() {
        ScreenOrientationManager.instance.forcePortraitPlayback = false;
        SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.portraitUp,
        ]);
      }));
    } catch (e) {
      debugPrint('退出刷片页停止播放失败: $e');
      ScreenOrientationManager.instance.forcePortraitPlayback = false;
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]);
    }
    _pageController.dispose();
    _playingItemId = null;
    super.dispose();
  }

  // [QBSenHook] v8.5: 退后台时也保存（杀进程前 paused 触发）
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _savePlayRecord();
    }
  }

  /// [QBSenHook] v8.5: 把当前刷片列表与最后播放视频记为一条播放记录
  void _savePlayRecord() {
    if (!mounted) return;
    final sourceId = widget.initialParentId ?? widget.initialLibraryId;
    if (sourceId == null || sourceId.isEmpty) return;
    if (_items.isEmpty ||
        _currentIndex < 0 ||
        _currentIndex >= _items.length) {
      return;
    }
    final item = _items[_currentIndex];
    final String sourceName =
        widget.parentName ?? widget.title.replaceAll(' 刷片', '');
    SwipePlayRecord.saveRecord(
      sourceId: sourceId,
      sourceName: sourceName,
      folderMode: widget.initialFolderMode,
      sortName: _sort.name,
      sortAscending: _sortAscending,
      lastItemId: item.id,
      lastItemName: item.name,
    );
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
      // [QBSenHook] v7.9: 仅未显式传入排序时才从偏好恢复，避免覆盖外部设置的排序
      if (widget.initialSort == null) {
        final sortName = prefs.getString('qbsen_swipe_sort');
        if (sortName != null) {
          for (final s in SwipeSort.values) {
            if (s.name == sortName) {
              setState(() => _sort = s);
              break;
            }
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
      var items = await service.getSwipeItems(
        libraryId: sourceId,
        favoritesOnly: _favoritesOnly,
        playlistId: _playlistId,
        sortBy: _sort.name,
        sortAscending: _sortAscending,
        limit: 0, // [QBSenHook] v8.0: 全量加载（分页拼接，不再截断 500 条）
      );
      // [QBSenHook] v8.13: 收藏/播放列表中的 Series（剧集）展开为剧集列表，
      // 这样收藏页能看到剧集，点击进入刷片可直接上下滑播放各集。
      items = await _expandSeriesItems(items);
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
      // [QBSenHook] v8.4b: PageView 首次 build 后才跳转——setState 后立即
      // 检查 hasClients 仍为 false（PageView 尚未挂载），jumpToPage 会静默
      // 失败，导致画面停在第一个视频而声音在播点击的视频。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_pageController.hasClients) {
          _pageController.jumpToPage(startIndex);
        }
      });
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

  /// [QBSenHook] v8.13: 将列表中的 Series 项展开为该剧的全部剧集（可播放）。
  Future<List<EmbyMediaItem>> _expandSeriesItems(
    List<EmbyMediaItem> items,
  ) async {
    if (!items.any((e) => e.type == 'Series')) return items;
    final result = <EmbyMediaItem>[];
    for (final item in items) {
      if (item.type == 'Series') {
        final episodes = await EmbyService.instance.getSeriesEpisodes(
          item.id,
          sortBy: _sort.name,
          sortAscending: _sortAscending,
        );
        if (episodes.isNotEmpty) {
          result.addAll(episodes);
        } else {
          result.add(item);
        }
      } else {
        result.add(item);
      }
    }
    return result;
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
    // [QBSenHook] v8.4: 防重入——jumpToPage 触发的 onPageChanged 与 _load 显式调用
    // 会连续触发同一视频的 _autoPlay，并发初始化会竞争播放器单例，导致播放器
    // 在播但 _playingItemId 未挂上、画面一直停留在缩略图。同一视频只初始化一次。
    if (_pendingPlayId == item.id || _playingItemId == item.id) {
      return;
    }
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
      // [QBSenHook] v8.3: 刷片模式不续播——每次进入/切换都从头开始播放
      final historyItem = WatchHistoryItem(
        filePath: 'emby://${item.id}',
        animeName: item.name,
        episodeTitle: null,
        watchProgress: 0.0,
        lastPosition: 0,
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
        // [QBSenHook] v8.4: 刷片模式不续播——强制从头播放
        startFromBeginning: true,
        // [QBSenHook] v8.7: currentMediaKey=真实文件名（全屏页顶部显示）
        mediaKey: item.displayName,
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

              // [QBSenHook] v8.12: 旋转元数据修正——倒置视频（180°）在竖屏分支补转 180°。
              final int videoRot = _videoRotation(videoState);
              final Widget rotatedTexture = videoRot == 180
                  ? RotatedBox(quarterTurns: 2, child: texture)
                  : texture;

              // [QBSenHook] v7.6: 横屏适配开关——视频旋转到横向后 cover 铺满（等效横屏观看）
              if (_landscapeView) {
                return SizedBox.expand(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    clipBehavior: Clip.hardEdge,
                    child: RotatedBox(
                      quarterTurns: videoRot == 180 ? 2 : (ratio > 1.0 ? 0 : 1),
                      child: SizedBox(
                        width: maxW,
                        height: maxW / ratio,
                        child: texture,
                      ),
                    ),
                  ),
                );
              }

              // [QBSenHook] v7.5.4: 横屏视频（宽>高）自动旋转 90° 竖着播放；
              // [QBSenHook] v8.11: 按 _fitMode 控制画面尺寸——cover 铺满，
              // 其余模式（原尺寸/16:9/4:3/1:1/9:16）旋转后完整显示不拉伸。
              if (ratio > 1.0) {
                if (_fitMode == EmbyFitMode.cover) {
                  return SizedBox.expand(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      clipBehavior: Clip.hardEdge,
                      child: RotatedBox(
                        quarterTurns: videoRot == 180 ? 2 : 1,
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
                      quarterTurns: videoRot == 180 ? 2 : 1,
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
                        child: rotatedTexture,
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
                        child: rotatedTexture,
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
                    child: rotatedTexture,
                  ),
                );
              }
              return FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: maxW,
                  height: hForWidth,
                  child: rotatedTexture,
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
      var w = codec.width;
      var h = codec.height;
      if (w <= 0 || h <= 0) return null;
      // [QBSenHook] v8.12: 竖拍视频（rotation 90/270）纹理已按旋转校正，
      // codec 宽高需交换，否则把竖拍视频当横屏再转一次导致长宽反。
      final rotate = (codec.rotate ?? 0) % 360;
      if (rotate == 90 || rotate == 270) {
        final t = w;
        w = h;
        h = t;
      }
      return w / h;
    } catch (_) {
      return null;
    }
  }

  /// [QBSenHook] v8.12: 视频旋转元数据（0/90/180/270），供旋转方向修正。
  int _videoRotation(VideoPlayerState videoState) {
    try {
      final video = videoState.player.mediaInfo.video;
      if (video == null || video.isEmpty) return 0;
      return (video.first.codec.rotate ?? 0) % 360;
    } catch (_) {
      return 0;
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
            // [QBSenHook] v8.3: 左缘右滑返回（好滑版：90px 触发区 + 位移/速度双判据），
            // 叠在最上层，不与卡片左右滑快进快退手势竞争
            const EdgeSwipeBackOverlay(),
            // 页码指示
            if (_items.isNotEmpty)
              Positioned(
                top: MediaQuery.of(context).padding.top + 10,
                right: 70,
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
    // [QBSenHook] v7.8: 去掉顶部半透明条，排序在外部调好
    return const SizedBox.shrink();
  }

  Widget _buildTopBarOld() {
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
              // [QBSenHook] v7.7: 去掉返回按钮，统一左缘右滑返回（CupertinoPageRoute）
              const SizedBox(width: 8),
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
      // [QBSenHook] v8.0: 单击唤出底部细进度条+时间，双击暂停/播放
      // [QBSenHook] v8.8: 单击在 显示/隐藏 间切换
      onTap: _toggleControlPanel,
      onDoubleTap: _togglePlayPause,
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
              // [QBSenHook] v8.8: 右下角播放/暂停按钮移除（由右上角圆形按钮承担）
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
        // [QBSenHook] v8.8: 右上角圆形 播放/暂停 图标（半透明）+ 周围一圈播放进度环（360°=播放完成）
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          right: 14,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _togglePlayPause,
            child: Consumer<VideoPlayerState>(
              builder: (context, v, _) {
                // [QBSenHook] v8.8b: 三态——缓冲(转圈)/播放(暂停图标)/暂停(播放图标)
                final bool buffering = v.status == PlayerStatus.loading ||
                    (!v.hasVideo && _pendingPlayId != null);
                final bool playing =
                    v.hasVideo && v.status == PlayerStatus.playing;
                final double progress =
                    v.hasVideo && v.duration.inMilliseconds > 0
                        ? (v.position.inMilliseconds /
                                v.duration.inMilliseconds)
                            .clamp(0.0, 1.0)
                        : 0.0;
                return SizedBox(
                  width: 48,
                  height: 48,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: CircularProgressIndicator(
                          value: buffering ? null : progress,
                          strokeWidth: 3,
                          backgroundColor: Colors.white.withValues(alpha: 0.22),
                          color: Colors.white,
                        ),
                      ),
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.35),
                          shape: BoxShape.circle,
                        ),
                        child: buffering
                            // [QBSenHook] v8.8b: 缓冲=转圈缓冲图标（无文字）
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.6,
                                  color: Colors.white70,
                                ),
                              )
                            // [QBSenHook] v8.8b: 图标反映当前状态：播放=播放图标，暂停=暂停图标
                            : Icon(
                                playing
                                    ? Icons.play_arrow_rounded
                                    : Icons.pause_rounded,
                                color: Colors.white.withValues(alpha: 0.85),
                                size: 26,
                              ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        // [QBSenHook] v7.5.5: 文件名移到上侧（顶部信息栏下方）
        // [QBSenHook] v8.8: 与控制面板同显同隐（单击唤出）
        if (_controlsVisible)
          Positioned(
          left: 18,
          right: 90,
          top: MediaQuery.of(context).padding.top + 56,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                // [QBSenHook] v8.7: 顶部显示真实文件名（路径最后一段），无路径回退元数据名
                item.displayName,
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
        // [QBSenHook] v8.5: 进度条合并——快进快退/单击均只显示下方控制面板进度条（可拖动）
        // [QBSenHook] v8.10: 未唤出控件时底部常驻极细播放进度条（显示播放到哪里）
        if (_controlsVisible)
          _buildControlPanel()
        else if (_seekBarVisible)
          _buildMiniProgressBar()
        else
          const SizedBox.shrink(),
        ],
      ),
    );
  }

  /// [QBSenHook] v7.4: 切换播放/暂停（双击/右上角圆形按钮触发）。
  void _togglePlayPause() {
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    if (!videoState.hasVideo) return;
    if (videoState.status == PlayerStatus.playing) {
      videoState.pause();
    } else {
      videoState.play();
      // [QBSenHook] v8.8: 从暂停恢复播放后重新计时，3 秒后自动隐藏控件
      if (_controlsVisible) {
        _controlsTimer?.cancel();
        _controlsTimer = Timer(const Duration(seconds: 2), () {
          if (mounted) setState(() => _controlsVisible = false);
        });
      }
    }
  }

  /// [QBSenHook] v7.5.2: 单击调出播放控件面板，3 秒后自动隐藏。
  /// [QBSenHook] v8.8: 暂停时保持显示（不启动自动隐藏计时）；播放中才 3 秒隐藏。
  void _showControlPanel() {
    if (!mounted) return;
    setState(() => _controlsVisible = true);
    _controlsTimer?.cancel();
    final v = Provider.of<VideoPlayerState>(context, listen: false);
    final playing = v.hasVideo && v.status == PlayerStatus.playing;
    if (!playing) return;
    _controlsTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  /// [QBSenHook] v8.8: 单击切换 显示/隐藏 控制面板。
  void _toggleControlPanel() {
    if (!mounted) return;
    if (_controlsVisible) {
      _controlsTimer?.cancel();
      setState(() => _controlsVisible = false);
    } else {
      _showControlPanel();
    }
  }

  /// 面板按钮动作：执行操作并重置 3 秒隐藏计时。
  void _panelAction(VoidCallback action) {
    action();
    _showControlPanel();
  }

  /// [QBSenHook] v8.11: 底部常驻进度条——当前时间 + 可拖动进度条 + 总时长。
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
                            height: 22, // [QBSenHook] v8.12: 固定手势热区高度，避免 Row 无界高度布局异常
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
  }

  /// [QBSenHook] v7.5.2: 循环切换画面尺寸模式。
  void _cycleFitMode() {
    setState(() {
      final values = EmbyFitMode.values;
      _fitMode = values[(_fitMode.index + 1) % values.length];
    });
  }

  /// [QBSenHook] v7.5.2: 播放控件面板（底部浮层，3 秒自动隐藏）。
  /// [QBSenHook] v8.0: 改为"极细进度条 + 当前/总时长 + 播放暂停 + 尺寸"一行，无背景。
  Widget _buildControlPanel() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        top: false,
        child: Container(
          // [QBSenHook] v8.0: 无背景卡片，仅文字/按钮悬浮在画面上
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Consumer<VideoPlayerState>(
            builder: (context, videoState, child) {
              final bool hasVideo = videoState.hasVideo;
              final bool isPlaying = videoState.status == PlayerStatus.playing;
              final double pos =
                  hasVideo && videoState.duration.inMilliseconds > 0
                      ? (videoState.position.inMilliseconds /
                              videoState.duration.inMilliseconds)
                          .clamp(0.0, 1.0)
                      : 0.0;
              final String cur = _fmtDuration(videoState.position);
              final String total = _fmtDuration(videoState.duration);
              return Row(
                children: [
                  // [QBSenHook] v8.8: 播放/暂停统一为右上角圆形进度环按钮，此处不再放置
                  // 当前时间
                  Text(
                    cur,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      shadows: [Shadow(color: Colors.black87, blurRadius: 3)],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // [QBSenHook] v8.5: 进度条合并后唯一一条——可拖动 seek
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
                            height: 22, // [QBSenHook] v8.12: 固定手势热区高度，避免 Row 无界高度布局异常
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
                  // 总时长
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
  }

  // [QBSenHook] v8.0: 时长格式化 mm:ss / h:mm:ss
  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final sec = d.inSeconds % 60;
    final ss = sec.toString().padLeft(2, '0');
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:$ss';
    }
    return '$m:$ss';
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
    // [QBSenHook] v8.13: 左右滑快进时显示底部细进度条（与顶部文件名同隐同显体系）
    if (mounted) setState(() => _seekBarVisible = true);
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    if (!_seekDragging || !videoState.hasVideo) return;
    // [QBSenHook] v8.0: 按视频时长比例分配快进快退灵敏度——
    // 单步基准 = 时长×2%，保底 3 秒、封顶 30 秒；拖满 80px 完成一个基准步长。
    _seekDragAccum += details.delta.dx;
    final durationSec = videoState.duration.inSeconds > 0
        ? videoState.duration.inSeconds
        : 1;
    final baseStep = (durationSec * 0.02).clamp(3.0, 30.0);
    const double pxPerStep = 80.0;
    final secondsPerPx = baseStep / pxPerStep;
    final totalSeconds = (_seekDragAccum * secondsPerPx).round();
    final target = _seekDragStartPos + Duration(seconds: totalSeconds);
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > videoState.duration ? videoState.duration : target);
    videoState.seekTo(clamped);
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    _seekDragging = false;
    _seekDragAccum = 0.0;
    // [QBSenHook] v8.13: 手离开屏幕立即隐藏快进进度条
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
