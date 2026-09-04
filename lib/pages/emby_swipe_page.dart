import 'package:flutter/material.dart';
import 'package:nipaplay/models/emby_model.dart';
import 'package:nipaplay/models/media_server_playback.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/pages/emby_folder_browser_page.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/services/playback_source_service.dart';
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
  });

  final String title;
  final String? initialLibraryId;
  final bool favoritesOnly;
  final String? playlistId;
  final String? playlistName;

  /// 文件夹模式：从文件夹浏览页进入，在此文件夹内上下滑播放
  final String? initialParentId;
  final String? parentName;

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

  @override
  void initState() {
    super.initState();
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
    _pageController.dispose();
    _playbackGeneration++;
    _playingItemId = null;
    super.dispose();
  }

  Future<void> _restorePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      // 仅在非显式指定来源时恢复上次选择
      if (widget.initialLibraryId == null &&
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
        limit: 80,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _currentIndex = 0;
      });
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
      _loadSourceOptions();
      _savePreferences();
      if (items.isNotEmpty) {
        _autoPlay(items.first);
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
          // iOS/Android：texture 模式，textureId 是异步更新的 ValueNotifier，
          // 必须用 ValueListenableBuilder 监听变化，否则画面永远不出现。
          return ValueListenableBuilder<int?>(
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
        } catch (e) {
          return const SizedBox.shrink();
        }
      },
    );
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
    Navigator.of(context).push(
      MaterialPageRoute<void>(
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
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 6,
          left: 6,
          right: 6,
          bottom: 6,
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            const SizedBox(width: 4),
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
    );
  }

  Widget _buildSwipeCard(EmbyMediaItem item, int index) {
    final service = EmbyService.instance;
    final imageUri = item.imagePrimaryTag != null
        ? Uri.tryParse(service.getImageUrl(item.id, tag: item.imagePrimaryTag))
        : null;
    final isPending = _pendingPlayId == item.id;
    final isPlayingNow = _playingItemId == item.id;
    final isActiveCard =
        index == _currentIndex && (isPending || isPlayingNow);
    final showPlaybackError =
        _playbackError != null && index == _currentIndex;
    return Stack(
      fit: StackFit.expand,
      children: [
        // 已开始播放：显示视频画面
        if (isPlayingNow) Positioned.fill(child: _buildVideoSurface()),
        // 状态提示条（加载中/播放中/出错时显示）
        if (isActiveCard)
          Positioned(
            left: 12,
            right: 12,
            top: MediaQuery.of(context).padding.top + 54,
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
                icon: isPlayingNow
                    ? Icons.pause_circle_filled_rounded
                    : (isPending
                        ? Icons.hourglass_top_rounded
                        : Icons.play_circle_fill_rounded),
                color: Colors.white,
                label: isPlayingNow
                    ? '播放中'
                    : (isPending ? '加载中' : '播放'),
                onTap: () {
                  if (!isPending && !isPlayingNow) {
                    _autoPlay(item);
                  }
                },
              ),
            ],
          ),
        ),
        // 底部信息
        Positioned(
          left: 16,
          right: 76,
          bottom: 24,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (item.productionYear != null ||
                  item.communityRating != null) ...[
                const SizedBox(height: 6),
                Text(
                  [
                    if (item.productionYear != null) '${item.productionYear}',
                    if (item.communityRating != null)
                      '★ ${item.communityRating}',
                  ].join(' · '),
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
              if (item.overview != null && item.overview!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  item.overview!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
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
