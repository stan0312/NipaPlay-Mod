import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:nipaplay/models/emby_model.dart';
import 'package:nipaplay/models/media_server_playback.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/pages/emby_fullscreen_player_page.dart';
import 'package:nipaplay/pages/emby_swipe_page.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/services/playback_source_service.dart';
import 'package:nipaplay/settings/adaptive_settings_scope.dart';
import 'package:nipaplay/settings/pages/remote_media_library_settings_content.dart';
import 'package:nipaplay/utils/theme_notifier.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/widgets/media_server_network_image.dart';
import 'package:provider/provider.dart';

/// [QBSenHook] Emby 文件夹方式浏览页：按目录结构浏览媒体库，
/// 点击视频直接进入全屏播放器播放（按视频尺寸选择方向）。
class EmbyFolderBrowserPage extends StatefulWidget {
  const EmbyFolderBrowserPage({
    super.key,
    this.rootId,
    this.rootName,
    this.isRootHome = false,
  });

  /// 根目录 id；为空则显示所有媒体库
  final String? rootId;
  final String? rootName;

  /// [QBSenHook] v7.9: 作为应用初始首页（Tab 内嵌）时置 true，左滑/返回仅刷新不退出
  final bool isRootHome;

  @override
  State<EmbyFolderBrowserPage> createState() => _EmbyFolderBrowserPageState();
}

class _FolderEntry {
  final String id;
  final String name;
  const _FolderEntry(this.id, this.name);
}

class _EmbyFolderBrowserPageState extends State<EmbyFolderBrowserPage>
    with WidgetsBindingObserver {
  // 面包屑路径（不含根）；entries.last 为当前目录
  final List<_FolderEntry> _path = [];
  String? _currentId;
  String? _currentName;
  List<EmbyMediaItem> _items = [];
  // [QBSenHook] v7.5.5: 视频陈列模式数据
  List<EmbyMediaItem> _videos = [];
  bool _loading = true;
  String? _error;

  List<EmbyLibrary> _rootLibraries = [];

  // [QBSenHook] v7.5.5: 分类页默认视频陈列模式；排序；搜索词
  bool _videoGridMode = true;
  SwipeSort _sort = SwipeSort.dateCreated;
  bool _sortAscending = false; // [QBSenHook] v7.8: 排序方向（false=降序[默认新到旧]）
  String _query = '';
  final TextEditingController _searchController = TextEditingController();
  // [QBSenHook] v8.0: 首页全局搜索（防抖 300ms，点结果直接全屏播放）
  List<EmbyMediaItem> _searchResults = [];
  bool _searchLoading = false;
  Timer? _searchTimer;
  // [QBSenHook] v8.0: 文件夹递归摘要缓存（大小 + 缩略图继承）
  final Map<String, FolderSummary> _folderMeta = {};
  final Set<String> _folderMetaLoading = {};

  // [QBSenHook] v7.9: 左缘右滑返回手势起点
  double? _edgeStartX;
  // [QBSenHook] v8.0: 等待 Emby 连接就绪后自动刷新（修复"打开初始页无内容"）
  Timer? _connectRetryTimer;
  int _connectRetryAttempts = 0;

  @override
  void initState() {
    super.initState();
    _currentId = widget.rootId;
    _currentName = widget.rootName;
    // [QBSenHook] v7.5.5: 指定分类进入时默认视频陈列
    _videoGridMode = widget.rootId != null;
    // [QBSenHook] v8.0: 监听 App 生命周期（回前台时若首页仍空则自动刷新）
    WidgetsBinding.instance.addObserver(this);
    // [QBSenHook] v7.9: 初始页进入自动刷新媒体库列表
    _load();
    // [QBSenHook] v8.0: Emby 可能尚未连接（App 启动时序），就绪后自动补刷新
    _scheduleConnectRetry();
  }

  // [QBSenHook] v8.0: 等待 Emby 连接就绪后自动刷新首页
  void _scheduleConnectRetry() {
    _connectRetryTimer?.cancel();
    _connectRetryAttempts = 0;
    _connectRetryTimer = Timer.periodic(const Duration(milliseconds: 800), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      _connectRetryAttempts++;
      if (EmbyService.instance.isConnected) {
        t.cancel();
        if (_currentId == null && _rootLibraries.isEmpty && !_loading) {
          _load();
        }
      } else if (_connectRetryAttempts >= 8) {
        // 8 次仍未连接：按原逻辑走（错误/空态可手动刷新）
        t.cancel();
        if (_currentId == null && _rootLibraries.isEmpty && !_loading) {
          _load();
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _currentId == null &&
        _rootLibraries.isEmpty &&
        !_loading) {
      _load();
    }
  }

  @override
  void dispose() {
    _connectRetryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _searchTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  String get _title {
    if (_path.isEmpty) return _currentName ?? '文件夹浏览';
    return _path.last.name;
  }

  /// [QBSenHook] v7.9: 下拉刷新（静默，不切 loading 全屏）
  Future<void> _refresh() async {
    try {
      if (_currentId == null) {
        await EmbyService.instance.loadAvailableLibraries();
        if (!mounted) return;
        setState(() => _rootLibraries = EmbyService.instance.availableLibraries);
      } else if (_videoGridMode) {
        final items = await EmbyService.instance.getSwipeItems(
          libraryId: _currentId,
          sortBy: _sort.name,
          sortAscending: _sortAscending,
          limit: 0, // [QBSenHook] v8.0: 全量加载（分页拼接）
        );
        if (!mounted) return;
        setState(() => _videos = items);
      } else {
        final items = await EmbyService.instance.getFolderChildren(
          _currentId!,
          sortBy: _sort.name,
          sortAscending: _sortAscending,
        );
        if (!mounted) return;
        setState(() => _items = items);
      }
    } catch (e) {
      debugPrint('下拉刷新失败: $e');
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_currentId == null) {
        // [QBSenHook] v7.7: 根目录先从服务器刷新媒体库列表，避免只显示缓存
        try {
          await EmbyService.instance.loadAvailableLibraries();
        } catch (e) {
          debugPrint('根目录刷新媒体库失败: $e');
        }
        // 根：列出媒体库
        final libs = EmbyService.instance.availableLibraries;
        if (!mounted) return;
        setState(() {
          _rootLibraries = libs;
          _items = [];
          _videos = [];
          _loading = false;
        });
      } else if (_videoGridMode) {
        // [QBSenHook] v7.5.5: 分类视频陈列（3 个一排）
        await _loadVideoGrid();
      } else {
        // [QBSenHook] v7.9: 文件夹模式应用排序（时间/文件名/随机/大小 + 升降序）
        final items = await EmbyService.instance.getFolderChildren(
          _currentId!,
          sortBy: _sort.name,
          sortAscending: _sortAscending,
        );
        if (!mounted) return;
        setState(() {
          _rootLibraries = [];
          _items = items;
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _openFolder(EmbyMediaItem folder) {
    // [QBSenHook] v7.5.3: 文件夹模式真实层级浏览——
    // 点文件夹继续进入子文件夹（一层层下钻），点视频才进抖音式刷片播放。
    setState(() {
      _path.add(_FolderEntry(folder.id, folder.name));
      _currentId = folder.id;
      _currentName = folder.name;
    });
    _load();
  }

  void _enterLibrary(EmbyLibrary lib) {
    setState(() {
      _path.clear();
      _path.add(_FolderEntry(lib.id, lib.name));
      _currentId = lib.id;
      _currentName = lib.name;
      // [QBSenHook] v7.5.5: 进入分类默认视频陈列（3 个一排）
      _videoGridMode = true;
    });
    _load();
  }

  void _goUp() {
    if (_path.isEmpty) {
      // [QBSenHook] v7.6: 作为初始界面时根目录不再 pop（避免退出/黑屏），仅刷新
      if (widget.rootId != null) {
        setState(() {
          _currentId = null;
          _currentName = null;
        });
        _load();
        return;
      }
      // [QBSenHook] v7.9: 初始首页仅刷新；从其他页面 push 进来的根目录页则 pop 返回
      if (!widget.isRootHome && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      return;
    }
    setState(() {
      _path.removeLast();
      if (_path.isEmpty) {
        _currentId = widget.rootId;
        _currentName = widget.rootName;
      } else {
        _currentId = _path.last.id;
        _currentName = _path.last.name;
      }
    });
    _load();
  }

  // [QBSenHook] v8.0: 首页搜索防抖 300ms，触发全局搜索
  void _onSearchChanged(String v) {
    setState(() => _query = v.trim());
    _searchTimer?.cancel();
    if (_query.isEmpty) {
      if (_currentId == null) {
        setState(() {
          _searchResults = [];
          _searchLoading = false;
        });
      }
      return;
    }
    _searchTimer = Timer(const Duration(milliseconds: 300), () {
      if (_currentId == null) {
        _runGlobalSearch();
      }
    });
  }

  // [QBSenHook] v8.0: 首页全局搜索全部媒体库（Emby 服务端 Recursive 搜索）
  Future<void> _runGlobalSearch() async {
    final term = _query.trim();
    if (term.isEmpty) return;
    setState(() => _searchLoading = true);
    try {
      final results = await EmbyService.instance.searchMediaItems(
        term,
        includeItemTypes: const ['Movie', 'Episode', 'Video'],
      );
      if (!mounted || _query.trim() != term) return;
      setState(() {
        _searchResults = results.where((e) => !e.isFolder).toList();
        _searchLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searchResults = [];
        _searchLoading = false;
      });
    }
  }

  // [QBSenHook] v8.0: 文件夹递归摘要（总大小 + 缩略图继承），每卡一次、缓存结果
  void _ensureFolderMeta(EmbyMediaItem folder) {
    final id = folder.id;
    if (_folderMeta.containsKey(id) || _folderMetaLoading.contains(id)) return;
    _folderMetaLoading.add(id);
    EmbyService.instance.getFolderRecursiveSummary(id).then((summary) {
      _folderMetaLoading.remove(id);
      if (!mounted || summary == null) return;
      setState(() => _folderMeta[id] = summary);
    }).catchError((Object e) {
      _folderMetaLoading.remove(id);
    });
  }

  /// [QBSenHook] v7.5.5: 循环切换排序（时间添加→文件名→随机→大小）。
  void _cycleSort() {
    setState(() {
      final values = SwipeSort.values;
      _sort = values[(_sort.index + 1) % values.length];
    });
    _load();
  }

  /// [QBSenHook] v7.8: 切换排序方向（升序↔降序）
  void _toggleSortOrder() {
    setState(() => _sortAscending = !_sortAscending);
    _load();
  }

  /// [QBSenHook] v7.5.5: 视频陈列模式加载（服务端排序）。
  Future<void> _loadVideoGrid() async {
    try {
      final items = await EmbyService.instance.getSwipeItems(
        libraryId: _currentId,
        sortBy: _sort.name,
        sortAscending: _sortAscending,
        limit: 0, // [QBSenHook] v8.0: 全量加载（分页拼接）
      );
      if (!mounted) return;
      setState(() {
        _videos = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _openSwipeInCurrentFolder() {
    if (_currentId == null) return;
    // [QBSenHook] v7.5.4: Cupertino 路由支持左缘右滑返回
    // [QBSenHook] v7.8: 传入当前排序设置，抖音模式与外部排序一致
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => EmbySwipePage(
          title: '$_currentName 刷片',
          initialParentId: _currentId,
          parentName: _currentName,
          initialSort: _sort,
          initialSortAscending: _sortAscending,
        ),
      ),
    );
  }

  Future<void> _openVideoPlayer(EmbyMediaItem video) async {
    // [QBSenHook] v8.0: 搜索结果点击同样直接全屏播放（不要求位于某个分类内）
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    // [QBSenHook] v7.5.4: 内嵌播放必须绑定本页 context
    videoState.setContext(context);
    try {
      // 续播：从 Emby 服务端观看进度恢复
      final resumeMs =
          (video.userData?.playbackPositionTicks ?? 0.0) / 10000.0;
      final resumePositionMs = resumeMs > 0 ? resumeMs.round() : 0;
      final historyItem = WatchHistoryItem(
        filePath: 'emby://${video.id}',
        animeName: video.name,
        episodeTitle: null,
        watchProgress: 0.0,
        lastPosition: resumePositionMs,
        duration: 0,
        lastWatchTime: DateTime.now(),
        animeId: null,
        isFromScan: false,
      );
      PlaybackSession? session;
      try {
        session = await EmbyService.instance
            .createPlaybackSession(itemId: video.id);
      } catch (e) {
        debugPrint('文件夹播放预创建会话失败(将由播放器内部处理): $e');
      }
      if (!mounted) return;
      final playable = PlayableItem(
        videoPath: historyItem.filePath,
        title: video.name,
        historyItem: historyItem,
        playbackSession: session,
      );
      final detailContext =
          await PlaybackSourceService.resolve(context, playable);
      if (!mounted) return;
      await videoState.initializePlayer(
        playable.videoPath,
        historyItem: historyItem,
        playbackSession: session,
        playbackDetailContext: detailContext,
      );
      if (!mounted) return;
      final initError = videoState.error;
      if (initError != null && initError.trim().isNotEmpty) {
        debugPrint('文件夹播放初始化失败: $initError');
        return;
      }
      if (!videoState.hasVideo) {
        debugPrint('文件夹播放未能建立视频画面');
        return;
      }
      videoState.play();
      if (!mounted) return;
      // [QBSenHook] v7.5.4: 直接进入全屏播放器（按视频尺寸自动选横竖屏）
      Navigator.of(context).push(
        CupertinoPageRoute<void>(
          builder: (_) =>
              const EmbyFullscreenPlayerPage(preferredOrientation: 'auto'),
        ),
      );
    } catch (e, s) {
      debugPrint('文件夹播放失败: $e\n$s');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeNotifier>().themeMode != ThemeMode.light;
    // [QBSenHook] v7.9: 初始页（第一页）无返回键
    final isRootHome = widget.isRootHome || (widget.rootId == null && _path.isEmpty);
    // 次级文字/图标色（随主题反色，白天模式可读）
    final iconColor = isDark ? Colors.white : Colors.black87;
    final iconSubColor = isDark ? Colors.white70 : Colors.black54;
    final searchBg = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.06);
    final searchTextColor = isDark ? Colors.white : Colors.black87;
    final searchHintColor = isDark ? Colors.white38 : Colors.black38;
    final searchIconColor = isDark ? Colors.white60 : Colors.black45;
    final emptyColor = isDark ? Colors.white54 : Colors.black45;

    return GestureDetector(
      // [QBSenHook] v7.9: 除全屏外全部页面支持左缘右滑返回（含文件夹二级/内容二级）
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (d) => _edgeStartX = d.localPosition.dx,
      onHorizontalDragEnd: (d) {
        final startX = _edgeStartX;
        _edgeStartX = null;
        if (startX != null &&
            startX < 60 &&
            d.primaryVelocity != null &&
            d.primaryVelocity! > 250) {
          _goUp();
        }
      },
      child: Scaffold(
        backgroundColor: isDark ? Colors.black : const Color(0xFFF5F5F5),
        appBar: AppBar(
          backgroundColor: isDark ? Colors.black : Colors.white,
          foregroundColor: iconColor,
          automaticallyImplyLeading: false,
          // [QBSenHook] v7.5.5: 返回 + 搜索框同一排靠左；按钮排（排序/文件夹/抖音/刷新）
          titleSpacing: 0,
          leading: isRootHome
              ? null
              : IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  color: iconColor,
                  onPressed: _goUp,
                ),
          title: Container(
            height: 36,
            margin: EdgeInsets.only(
                left: isRootHome ? 10 : 0, top: 4, bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: searchBg,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Icon(Icons.search_rounded, color: searchIconColor, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(color: searchTextColor, fontSize: 14),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: '搜索',
                      hintStyle:
                          TextStyle(color: searchHintColor, fontSize: 14),
                    ),
                    onChanged: _onSearchChanged,
                  ),
                ),
                if (_query.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                    child: Icon(Icons.close_rounded,
                        color: searchIconColor, size: 16),
                  ),
              ],
            ),
          ),
          actions: [
            if (_currentId != null) ...[
              // [QBSenHook] v7.9: 排序胶囊按钮（类型图标+名称+升降序箭头，更美观）
              // [QBSenHook] v8.0: 多功能——单击循环切排序方式；右滑=新到旧、左滑=旧到新
              GestureDetector(
                onTap: _cycleSort,
                onHorizontalDragEnd: (d) {
                  final v = d.primaryVelocity;
                  if (v == null) return;
                  if (v > 200) {
                    if (!_sortAscending) return;
                    _sortAscending = false;
                    _load();
                  } else if (v < -200) {
                    if (_sortAscending) return;
                    _sortAscending = true;
                    _load();
                  }
                },
                child: Container(
                  height: 32,
                  margin: const EdgeInsets.only(right: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.12)
                        : Colors.black.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.15)
                          : Colors.black.withValues(alpha: 0.10),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_sortIcon(_sort), size: 14, color: iconSubColor),
                      const SizedBox(width: 4),
                      Text(
                        _sort.label,
                        style: TextStyle(
                            fontSize: 12, color: iconColor),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        _sortAscending
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        size: 14,
                        color: iconSubColor,
                      ),
                    ],
                  ),
                ),
              ),
              // 文件夹模式切换（视频陈列 <-> 文件夹）
              IconButton(
                icon: Icon(
                  _videoGridMode
                      ? Icons.folder_open_rounded
                      : Icons.grid_view_rounded,
                  color: iconColor,
                  size: 22,
                ),
                tooltip: _videoGridMode ? '切换到文件夹模式' : '切换到视频陈列',
                onPressed: () {
                  setState(() => _videoGridMode = !_videoGridMode);
                  _load();
                },
              ),
              // 抖音刷片
              IconButton(
                icon: Icon(Icons.smart_display_rounded,
                    color: iconColor, size: 22),
                tooltip: '在此分类/文件夹内上下滑播放',
                onPressed: _openSwipeInCurrentFolder,
              ),
            ],
            // [QBSenHook] v7.6: 夜间模式切换 + 设置（原顶部悬浮控件并入本页）
            IconButton(
              icon: Icon(
                Theme.of(context).brightness == Brightness.dark
                    ? Icons.light_mode_rounded
                    : Icons.dark_mode_rounded,
                color: iconColor,
                size: 22,
              ),
              tooltip: '切换夜间模式',
              onPressed: () {
                final notifier = context.read<ThemeNotifier>();
                notifier.themeMode =
                    Theme.of(context).brightness == Brightness.dark
                        ? ThemeMode.light
                        : ThemeMode.dark;
              },
            ),
            IconButton(
              icon: Icon(Icons.settings_rounded, color: iconColor, size: 22),
              tooltip: '设置',
              onPressed: () {
                // [QBSenHook] v8.2: 设置入口直接打开"添加媒体库（网络媒体库）"
                Navigator.of(context).push(
                  CupertinoPageRoute<void>(
                    builder: (_) => const AdaptiveSettingsScope(
                      style: AdaptiveSettingsStyle.phone,
                      child: RemoteMediaLibrarySettingsContent(),
                    ),
                  ),
                );
              },
            ),
            IconButton(
              icon: Icon(Icons.refresh_rounded, color: iconColor, size: 22),
              onPressed: _load,
            ),
          ],
        ),
        body: _buildBody(emptyColor, isDark),
      ),
    );
  }

  IconData _sortIcon(SwipeSort sort) {
    switch (sort) {
      case SwipeSort.name:
        return Icons.sort_by_alpha_rounded;
      case SwipeSort.random:
        return Icons.shuffle_rounded;
      case SwipeSort.size:
        return Icons.data_usage_rounded;
      case SwipeSort.dateCreated:
        return Icons.schedule_rounded;
    }
  }

  Widget _buildBody(Color emptyColor, bool isDark) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(
            color: isDark ? Colors.white : Colors.black54),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded,
                color: isDark ? Colors.white54 : Colors.black45, size: 48),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                '加载失败：$_error',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black54,
                    fontSize: 14),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }

    if (_currentId == null && _rootLibraries.isEmpty) {
      return Center(
        child: Text(
          '没有可浏览的媒体库',
          style: TextStyle(color: emptyColor),
        ),
      );
    }

    if (_currentId == null) {
      // [QBSenHook] v8.0: 首页搜索词非空 -> 全局搜索结果（点击直接全屏播放）
      if (_query.isNotEmpty) {
        if (_searchLoading) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white54),
          );
        }
        if (_searchResults.isEmpty) {
          return Center(
            child: Text(
              '没有找到相关内容',
              style: TextStyle(color: emptyColor),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _runGlobalSearch,
          color: isDark ? Colors.white : Colors.black54,
          child: GridView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(10),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
              childAspectRatio: 0.62,
            ),
            itemCount: _searchResults.length,
            itemBuilder: (context, index) =>
                _buildVideoCard(_searchResults[index]),
          ),
        );
      }
      // 媒体库网格
      return RefreshIndicator(
        onRefresh: _refresh,
        color: isDark ? Colors.white : Colors.black54,
        child: GridView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.1,
          ),
          itemCount: _rootLibraries.length,
          itemBuilder: (context, index) {
            final lib = _rootLibraries[index];
            return _buildLibraryCard(lib);
          },
        ),
      );
    }

    // [QBSenHook] v7.5.5: 分类视频陈列模式：3 个一排，本地搜索过滤
    if (_videoGridMode) {
      final visible = _query.isEmpty
          ? _videos
          : _videos
              .where((e) => e.name.toLowerCase().contains(_query.toLowerCase()))
              .toList();
      if (visible.isEmpty) {
        return Center(
          child: Text(
            '没有匹配的视频',
            style: TextStyle(color: emptyColor),
          ),
        );
      }
      return RefreshIndicator(
        onRefresh: _refresh,
        color: isDark ? Colors.white : Colors.black54,
        child: GridView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(10),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
            childAspectRatio: 0.62,
          ),
          itemCount: visible.length,
          itemBuilder: (context, index) => _buildVideoCard(visible[index]),
        ),
      );
    }

    // 目录内容：文件夹 + 视频
    // [QBSenHook] v7.9: 文件夹模式也支持本地搜索过滤
    final allItems = _items.where((e) {
      if (_query.isEmpty) return true;
      return e.name.toLowerCase().contains(_query.toLowerCase());
    }).toList();
    final folders = allItems.where((e) => e.isFolder).toList();
    final videos = allItems.where((e) => !e.isFolder).toList();
    if (allItems.isEmpty) {
      return Center(
        child: Text(
          _query.isEmpty ? '此文件夹为空' : '没有匹配的内容',
          style: TextStyle(color: emptyColor),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      color: isDark ? Colors.white : Colors.black54,
      child: GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.1,
        ),
        itemCount: folders.length + videos.length,
        itemBuilder: (context, index) {
          if (index < folders.length) {
            return _buildFolderCard(folders[index]);
          }
          return _buildVideoCard(videos[index - folders.length]);
        },
      ),
    );
  }

  Widget _buildLibraryCard(EmbyLibrary lib) {
    final service = EmbyService.instance;
    final imageUri = lib.imageTagsPrimary != null
        ? Uri.tryParse(
            service.getImageUrl(lib.id, tag: lib.imageTagsPrimary))
        : null;
    return _Card(
      onTap: () => _enterLibrary(lib),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageUri != null)
            MediaServerNetworkImage(imageUri, fit: BoxFit.cover)
          else
            Container(
              color: const Color(0xFF222222),
              alignment: Alignment.center,
              child: const Icon(Icons.video_library_rounded,
                  color: Colors.white38, size: 48),
            ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.75),
                ],
              ),
            ),
          ),
          Positioned(
            left: 10,
            right: 10,
            bottom: 8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lib.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (lib.totalItems != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${lib.totalItems} 项',
                    style: const TextStyle(
                        color: Colors.white60, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderCard(EmbyMediaItem folder) {
    final service = EmbyService.instance;
    // [QBSenHook] v8.0: 无图文件夹递归继承第一个带图后代的缩略图
    final summary = _folderMeta[folder.id];
    String? imageItemId;
    String? imageTag;
    if (folder.imagePrimaryTag != null) {
      imageItemId = folder.id;
      imageTag = folder.imagePrimaryTag;
    } else if (summary != null && summary.thumbnailItemId != null) {
      imageItemId = summary.thumbnailItemId;
      imageTag = summary.thumbnailTag;
    }
    final imageUri = imageItemId != null && imageTag != null
        ? Uri.tryParse(service.getImageUrl(imageItemId, tag: imageTag))
        : null;
    // [QBSenHook] v8.0: 异步计算文件夹大小（递归子项 Size 求和）
    _ensureFolderMeta(folder);
    final sizeLabel = _formatBytes(summary?.totalSizeBytes);
    return _Card(
      onTap: () => _openFolder(folder),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageUri != null)
            MediaServerNetworkImage(imageUri, fit: BoxFit.cover)
          else
            Container(
              color: const Color(0xFF222222),
              alignment: Alignment.center,
              child: const Icon(Icons.folder_rounded,
                  color: Colors.white38, size: 48),
            ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.75),
                ],
              ),
            ),
          ),
          // [QBSenHook] v8.0: 右上角文件夹大小标注
          if (sizeLabel != null)
            Positioned(
              right: 6,
              top: 6,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  sizeLabel,
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ),
          Positioned(
            left: 10,
            right: 10,
            bottom: 8,
            child: Row(
              children: [
                const Icon(Icons.folder_rounded,
                    color: Colors.white70, size: 16),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    folder.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // [QBSenHook] v8.0: 字节数 -> 可读大小（B/KB/MB/GB/TB）
  String? _formatBytes(int? bytes) {
    if (bytes == null || bytes <= 0) return null;
    if (bytes < 1024) return '$bytes B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    var v = bytes.toDouble();
    var u = -1;
    while (v >= 1024 && u < units.length - 1) {
      v /= 1024;
      u++;
    }
    return u < 0 ? '$bytes B' : '${v.toStringAsFixed(1)} ${units[u]}';
  }

  Widget _buildVideoCard(EmbyMediaItem video) {
    final service = EmbyService.instance;
    final imageUri = video.imagePrimaryTag != null
        ? Uri.tryParse(
            service.getImageUrl(video.id, tag: video.imagePrimaryTag))
        : null;
    return _Card(
      onTap: () => _openVideoPlayer(video),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageUri != null)
            MediaServerNetworkImage(imageUri, fit: BoxFit.cover)
          else
            Container(
              color: const Color(0xFF1A1A1A),
              alignment: Alignment.center,
              child: const Icon(Icons.movie_rounded,
                  color: Colors.white24, size: 48),
            ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.75),
                ],
              ),
            ),
          ),
          Positioned(
            left: 10,
            right: 10,
            bottom: 8,
            child: Text(
              video.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // [QBSenHook] v8.0: 卡片底部 2px 已播放进度线（Emby UserData.PlayedPercentage）
          if ((video.userData?.playedPercentage ?? 0) > 0)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: 2,
                color: Colors.black.withValues(alpha: 0.4),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: ((video.userData!.playedPercentage ?? 0) / 100)
                      .clamp(0.0, 1.0),
                  child: Container(
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;

  const _Card({required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox.expand(child: child),
      ),
    );
  }
}
