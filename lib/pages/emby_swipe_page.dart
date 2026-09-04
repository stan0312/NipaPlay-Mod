import 'package:flutter/material.dart';
import 'package:nipaplay/models/emby_model.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/services/playback_service.dart';
import 'package:nipaplay/widgets/media_server_network_image.dart';

/// [QBSenHook] 抖音式刷片页：竖屏上下滑浏览 Emby 媒体库/收藏/播放列表。
/// 数据来自 NAS Emby 服务端，播放走现有 media_kit(mpv) 内核。
class EmbySwipePage extends StatefulWidget {
  const EmbySwipePage({
    super.key,
    this.title = '刷片',
    this.initialLibraryId,
    this.favoritesOnly = false,
    this.playlistId,
    this.playlistName,
  });

  final String title;
  final String? initialLibraryId;
  final bool favoritesOnly;
  final String? playlistId;
  final String? playlistName;

  @override
  State<EmbySwipePage> createState() => _EmbySwipePageState();
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

  List<EmbyLibrary> _libraries = [];
  List<EmbyLibrary> _playlists = [];

  // 本地收藏覆盖（避免重建不可变模型）
  final Set<String> _favoriteOn = {};
  final Set<String> _favoriteOff = {};

  @override
  void initState() {
    super.initState();
    _libraryId = widget.initialLibraryId;
    _favoritesOnly = widget.favoritesOnly;
    _playlistId = widget.playlistId;
    _playlistName = widget.playlistName;
    _load();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String get _sourceTitle {
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
    });
    try {
      final service = EmbyService.instance;
      final items = await service.getSwipeItems(
        libraryId: _libraryId,
        favoritesOnly: _favoritesOnly,
        playlistId: _playlistId,
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

  Future<void> _playItem(EmbyMediaItem item) async {
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
      final playbackSession = await EmbyService.instance
          .createPlaybackSession(itemId: item.id);
      if (!mounted) return;
      await PlaybackService().play(PlayableItem(
        videoPath: historyItem.filePath,
        title: item.name,
        historyItem: historyItem,
        playbackSession: playbackSession,
      ));
    } catch (e) {
      if (mounted) _showTip('播放失败: $e');
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

  void _openSourcePicker() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.grid_view_rounded),
              title: const Text('全部'),
              selected: _libraryId == null &&
                  !_favoritesOnly &&
                  _playlistId == null,
              onTap: () {
                Navigator.pop(sheetContext);
                _switchSource();
              },
            ),
            ListTile(
              leading: const Icon(Icons.favorite_rounded, color: Colors.redAccent),
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
                  selected: _libraryId == l.id,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _switchSource(libraryId: l.id);
                  },
                ),
            ],
          ],
        ),
      ),
    );
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
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
              onPageChanged: (i) => setState(() => _currentIndex = i),
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
    return Stack(
      fit: StackFit.expand,
      children: [
        // 背景图
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
                icon: Icons.play_circle_fill_rounded,
                color: Colors.white,
                label: '播放',
                onTap: () => _playItem(item),
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
          OutlinedButton(onPressed: _openSourcePicker, child: const Text('换个数据源')),
        ],
      ),
    );
  }
}
