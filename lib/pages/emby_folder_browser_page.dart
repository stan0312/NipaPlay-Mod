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
import 'package:nipaplay/settings/unified_settings_page.dart';
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

class _EmbyFolderBrowserPageState extends State<EmbyFolderBrowserPage> {
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

  // [QBSenHook] v7.9: 左缘右滑返回手势起点
  double? _edgeStartX;

  @override
  void initState() {
    super.initState();
    _currentId = widget.rootId;
    _currentName = widget.rootName;
    // [QBSenHook] v7.5.5: 指定分类进入时默认视频陈列
    _videoGridMode = widget.rootId != null;
    // [QBSenHook] v7.9: 初始页进入自动刷新媒体库列表
    _load();
  }

  @override
  void dispose() {
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
          limit: 500,
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
        limit: 500,
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
    if (_currentId == null) return;
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
                    onChanged: (v) => setState(() => _query = v.trim()),
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
              InkWell(
                onTap: _cycleSort,
                borderRadius: BorderRadius.circular(16),
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
                      GestureDetector(
                        onTap: _toggleSortOrder,
                        child: Icon(
                          _sortAscending
                              ? Icons.arrow_upward_rounded
                              : Icons.arrow_downward_rounded,
                          size: 14,
                          color: iconSubColor,
                        ),
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
                Navigator.of(context).push(
                  CupertinoPageRoute<void>(
                    builder: (_) => const UnifiedSettingsPage(),
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
    final imageUri = folder.imagePrimaryTag != null
        ? Uri.tryParse(
            service.getImageUrl(folder.id, tag: folder.imagePrimaryTag))
        : null;
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
