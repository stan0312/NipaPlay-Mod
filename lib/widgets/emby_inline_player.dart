import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';

/// [QBSenHook] 内嵌播放器：用于详情页等场景，点击播放后直接在当前位置
/// 渲染视频画面（不跳转播放器页）。监听 VideoPlayerState 全局播放状态：
/// - 加载中/识别中：显示"正在加载播放…"
/// - 播放中：显示视频画面（iOS 走 texture 模式，监听 textureId 异步更新）
/// - 出错：显示具体错误
class EmbyInlinePlayer extends StatelessWidget {
  const EmbyInlinePlayer({
    super.key,
    this.height = 200,
    this.radius = 10,
  });

  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        final hasVideo = videoState.hasVideo;
        final loading = videoState.status == PlayerStatus.loading ||
            videoState.status == PlayerStatus.recognizing;
        final error = videoState.status == PlayerStatus.error;
        if (!hasVideo && !loading && !error) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: SizedBox(
              height: height,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(color: Colors.black),
                  // 视频画面（仅在有视频时）
                  if (hasVideo)
                    ValueListenableBuilder<int?>(
                      valueListenable: videoState.player.textureId,
                      builder: (context, textureId, _) {
                        if (videoState.player.prefersPlatformVideoSurface) {
                          try {
                            final surface = videoState.player
                                .buildPlatformVideoSurface(
                                  debugLabel: 'detail',
                                );
                            if (surface != null) return surface;
                          } catch (_) {}
                          return const SizedBox.shrink();
                        }
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
                  // 加载中提示
                  if (loading)
                    _buildStatusBox(context, '正在加载播放…', spinning: true),
                  // 错误提示
                  if (error)
                    _buildStatusBox(
                      context,
                      '播放出错：${videoState.error ?? '未知错误'}',
                      error: true,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusBox(
    BuildContext context,
    String text, {
    bool spinning = false,
    bool error = false,
  }) {
    return Container(
      color: Colors.black.withValues(alpha: 0.55),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (spinning)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white70,
              ),
            )
          else
            Icon(
              error ? Icons.error_outline_rounded : Icons.info_outline,
              color: error ? Colors.redAccent : Colors.white70,
              size: 26,
            ),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
