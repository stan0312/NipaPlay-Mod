import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';

/// [QBSenHook] v7.4: 抖音式刷片页的全屏播放页。
///
/// [QBSenHook] v7.5 增强：
/// - 按视频分辨率自动横竖屏（横屏视频 → 横屏，竖屏视频 → 竖屏），
///   离开本页自动恢复竖屏；
/// - 视频按原始比例 contain 居中（不扭曲）；
/// - 单击：暂停/播放并切换控件显隐
/// - 双击：返回刷片页（pop）
/// - 左右滑：快进/快退（各 10 秒）
/// - 底部完整播放器控件：播放/暂停、快退、快进、进度条、时间
class EmbyFullscreenPlayerPage extends StatefulWidget {
  const EmbyFullscreenPlayerPage({super.key});

  @override
  State<EmbyFullscreenPlayerPage> createState() =>
      _EmbyFullscreenPlayerPageState();
}

class _EmbyFullscreenPlayerPageState extends State<EmbyFullscreenPlayerPage> {
  bool _controlsVisible = true;
  bool _orientationApplied = false;

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

  /// [QBSenHook] v7.5: 按视频分辨率自动设置屏幕方向。
  void _applyOrientation(VideoPlayerState videoState) {
    if (_orientationApplied) return;
    final ratio = _aspectRatio(videoState);
    if (ratio == null) return;
    _orientationApplied = true;
    if (ratio > 1.0) {
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]);
    }
  }

  @override
  void dispose() {
    // [QBSenHook] v7.5: 离开全屏页恢复竖屏（回到刷片页/详情页）
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    super.dispose();
  }

  void _togglePlayPause() {
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    if (!videoState.hasVideo) return;
    if (videoState.status == PlayerStatus.playing) {
      videoState.pause();
    } else {
      videoState.play();
    }
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
  }

  /// [QBSenHook] v7.5: 左右滑快进/快退（左滑快进、右滑快退，各 10 秒）。
  void _onHorizontalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    if (!videoState.hasVideo) return;
    if (velocity < -300) {
      videoState.seekForwardByStep();
    } else if (velocity > 300) {
      videoState.seekBackwardByStep();
    }
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Consumer<VideoPlayerState>(
        builder: (context, videoState, _) {
          if (videoState.hasVideo) {
            _applyOrientation(videoState);
          }
          if (!videoState.hasVideo) {
            return Stack(
              children: [
                const Center(
                  child: Text(
                    '当前没有正在播放的视频',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ),
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 12,
                  child: _buildCloseButton(),
                ),
              ],
            );
          }
          final ratio = _aspectRatio(videoState) ?? 16 / 9;
          return Stack(
            fit: StackFit.expand,
            children: [
              // 视频画面（单击暂停/播放并切控件、双击返回、左右滑快进快退）
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  _togglePlayPause();
                  _toggleControls();
                },
                onDoubleTap: () => Navigator.of(context).pop(),
                onHorizontalDragEnd: _onHorizontalDragEnd,
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: SizedBox(
                      width: 100,
                      height: 100 / ratio,
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
                    ),
                  ),
                ),
              ),
              // 顶部：返回按钮 + 标题
              AnimatedOpacity(
                opacity: _controlsVisible ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: SafeArea(
                  bottom: false,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    color: Colors.black.withValues(alpha: 0.35),
                    child: Row(
                      children: [
                        _buildCloseButton(),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            videoState.currentMediaKey ?? '全屏播放',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 15),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // 底部：播放器控件
              AnimatedOpacity(
                opacity: _controlsVisible ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                    color: Colors.black.withValues(alpha: 0.5),
                    child: SafeArea(
                      top: false,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildProgressRow(videoState),
                          _buildControlRow(videoState),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCloseButton() {
    return IconButton(
      icon: const Icon(Icons.arrow_back, color: Colors.white, size: 26),
      onPressed: () => Navigator.of(context).pop(),
    );
  }

  Widget _buildProgressRow(VideoPlayerState videoState) {
    final Duration total = videoState.duration;
    final Duration pos = videoState.position;
    final double totalMs = total.inMilliseconds.toDouble();
    final double maxMs = totalMs > 0 ? totalMs : 1.0;
    final double value =
        (pos.inMilliseconds.toDouble() / maxMs).clamp(0.0, 1.0);
    return Row(
      children: [
        Text(
          _formatDuration(pos),
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape:
                  const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
            ),
            child: Slider(
              value: value,
              onChanged: (v) {
                videoState.seekTo(Duration(milliseconds: (v * maxMs).round()));
              },
            ),
          ),
        ),
        Text(
          _formatDuration(total),
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildControlRow(VideoPlayerState videoState) {
    final bool isPlaying = videoState.status == PlayerStatus.playing;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.replay_10, color: Colors.white, size: 30),
          onPressed: () => videoState.seekBackwardByStep(),
        ),
        IconButton(
          icon: Icon(
            isPlaying ? Icons.pause : Icons.play_arrow,
            color: Colors.white,
            size: 40,
          ),
          onPressed: () => _togglePlayPause(),
        ),
        IconButton(
          icon: const Icon(Icons.forward_10, color: Colors.white, size: 30),
          onPressed: () => videoState.seekForwardByStep(),
        ),
      ],
    );
  }
}
