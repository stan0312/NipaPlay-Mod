import 'package:flutter/material.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';

/// [QBSenHook] v7.4: 抖音式刷片页的全屏播放页。
///
/// 由刷片页双击进入，复用全局 VideoPlayerState（同一 texture），
/// 视频按原始比例 contain 居中（不扭曲）；
/// - 单击：暂停/播放
/// - 双击：返回刷片页（pop）
class EmbyFullscreenPlayerPage extends StatelessWidget {
  const EmbyFullscreenPlayerPage({super.key});

  double? _aspectRatio(VideoPlayerState videoState) {
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

  void _togglePlayPause(BuildContext context) {
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    if (!videoState.hasVideo) return;
    if (videoState.status == PlayerStatus.playing) {
      videoState.pause();
    } else {
      videoState.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _togglePlayPause(context),
        onDoubleTap: () => Navigator.of(context).pop(),
        child: Center(
          child: Consumer<VideoPlayerState>(
            builder: (context, videoState, _) {
              if (!videoState.hasVideo) {
                return const Text(
                  '当前没有正在播放的视频',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                );
              }
              final ratio = _aspectRatio(videoState);
              return AspectRatio(
                aspectRatio: ratio ?? 16 / 9,
                child: ValueListenableBuilder<int?>(
                  valueListenable: videoState.player.textureId,
                  builder: (context, textureId, _) {
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
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
