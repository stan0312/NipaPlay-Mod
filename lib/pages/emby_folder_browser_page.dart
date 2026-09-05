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
  });

  /// 根目录 id；为空则显示所有媒体库
  final String? rootId;
  final String? rootName;

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
  bool _loading = true;
  String? _error;

  List<EmbyLibrary> _rootLibraries = [];

  @override
  void initState() {
    super.initState();
    _currentId = widget.rootId;
    _currentName = widget.rootName;
    _load();
  }

  String get _title {
    if (_path.isEmpty) return _currentName ?? '文件夹浏览';
    return _path.last.name;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_currentId == null) {
        // 根：列出媒体库
        final libs = EmbyService.instance.availableLibraries;
        if (!mounted) return;
        setState(() {
          _rootLibraries = libs;
          _items = [];
          _loading = false;
        });
      } else {
        final items =
            await EmbyService.instance.getFolderChildren(_currentId!);
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
    });
    _load();
  }

  void _goUp() {
    if (_path.isEmpty) {
      // 已在根：返回上一页（若有 rootId，回到媒体库列表）
      if (widget.rootId != null) {
        setState(() {
          _currentId = null;
          _currentName = null;
        });
        _load();
      } else {
        Navigator.pop(context);
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

  void _openSwipeInCurrentFolder() {
    if (_currentId == null) return;
    // [QBSenHook] v7.5.4: Cupertino 路由支持左缘右滑返回
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => EmbySwipePage(
          title: '$_currentName 刷片',
          initialParentId: _currentId,
          parentName: _currentName,
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
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: _goUp,
        ),
        title: Text(
          _title,
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          if (_currentId != null)
            IconButton(
              icon: const Icon(Icons.smart_display_rounded,
                  color: Colors.white),
              tooltip: '在此文件夹内上下滑播放',
              onPressed: _openSwipeInCurrentFolder,
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _load,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (_error != null) {
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

    if (_currentId == null && _rootLibraries.isEmpty) {
      return const Center(
        child: Text(
          '没有可浏览的媒体库',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }

    if (_currentId == null) {
      // 媒体库网格
      return GridView.builder(
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
      );
    }

    // 目录内容：文件夹 + 视频
    final folders = _items.where((e) => e.isFolder).toList();
    final videos = _items.where((e) => !e.isFolder).toList();
    return GridView.builder(
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
