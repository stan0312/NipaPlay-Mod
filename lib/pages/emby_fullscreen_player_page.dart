import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';

/// [QBSenHook] v7.4: 抖音式刷片页的全屏播放页。
///
/// [QBSenHook] v7.5.x 增强：
/// - 按视频分辨率自动横竖屏（横屏视频 → 横屏，竖屏视频 → 竖屏），
///   离开本页自动恢复竖屏；
/// - 视频以最大画面 contain 显示、不拉伸（可用画面尺寸按钮切换为
///   cover 填满裁剪，同样不拉伸）；
/// - 单击画面：暂停/播放；双击：返回刷片页（pop）；
/// - 左右滑：快进/快退（各 10 秒）；
/// - 底部完整播放器控件（常驻可交互）：
///   播放/暂停、快退、快进、倍速、画面尺寸、进度条、时间
class EmbyFullscreenPlayerPage extends StatefulWidget {
  const EmbyFullscreenPlayerPage({super.key});

  @override
  State<EmbyFullscreenPlayerPage> createState() =>
      _EmbyFullscreenPlayerPageState();
}

class _EmbyFullscreenPlayerPageState extends State<EmbyFullscreenPlayerPage> {
  bool _orientationApplied = false;
  bool _fillMode = false; // false=contain(原始比例最大画面) true=cover(填满裁剪)
  double? _dragValue; // 拖动进度条时的临时值（跟手）

  static const List<double> _speedOptions = [1.0, 1.25, 1.5, 2.0];

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

  /// [QBSenHook] v7.5.1: 循环切换倍速（1.0 → 1.25 → 1.5 → 2.0 → 1.0）。
  void _cyclePlaybackRate(VideoPlayerState videoState) {
    final current = videoState.playbackRate;
    int idx = _speedOptions.indexWhere((s) => (s - current).abs() < 0.001);
    if (idx < 0) idx = 0;
    final next = _speedOptions[(idx + 1) % _speedOptions.length];
    unawaited(videoState.setPlaybackRate(next));
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
              // 视频画面区（单击暂停/播放、双击返回、左右滑快进快退）
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _togglePlayPause,
                  onDoubleTap: () => Navigator.of(context).pop(),
                  onHorizontalDragEnd: _onHorizontalDragEnd,
                  child: _buildVideo(videoState, ratio),
                ),
              ),
              // 顶部：返回按钮 + 标题
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    color: Colors.black.withValues(alpha: 0.4),
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
              // 底部：播放器控件（常驻，独立于视频手势区，可交互）
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                    color: Colors.black.withValues(alpha: 0.55),
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
            ],
          );
        },
      ),
    );
  }

  Widget _buildVideo(VideoPlayerState videoState, double ratio) {
    final player = videoState.player;
    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxW = constraints.maxWidth;
        final double maxH = constraints.maxHeight;
        if (maxW <= 0 || maxH <= 0) return const SizedBox.shrink();
        final double hForWidth = maxW / ratio;
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
        if (_fillMode) {
          // cover：填满屏幕、居中裁剪，不拉伸
          return FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: maxW,
              height: hForWidth,
              child: texture,
            ),
          );
        }
        // contain：以最大画面显示原始比例，不拉伸
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
    final double value = (_dragValue ??
            (pos.inMilliseconds.toDouble() / maxMs).clamp(0.0, 1.0))
        .clamp(0.0, 1.0);
    return Row(
      children: [
        Text(
          _formatDuration(_dragValue != null
              ? Duration(milliseconds: (_dragValue! * maxMs).round())
              : pos),
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
            ),
            child: Slider(
              value: value,
              onChanged: (v) => setState(() => _dragValue = v),
              onChangeEnd: (v) {
                videoState.seekTo(
                    Duration(milliseconds: (v * maxMs).round()));
                setState(() => _dragValue = null);
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
        // [QBSenHook] v7.5.1: 倍速切换按钮
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _cyclePlaybackRate(videoState),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${videoState.playbackRate.toStringAsFixed(2)}x',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // [QBSenHook] v7.5.1: 画面尺寸切换按钮（contain ↔ cover）
        IconButton(
          icon: Icon(
            _fillMode ? Icons.aspect_ratio : Icons.fit_screen_outlined,
            color: Colors.white,
            size: 26,
          ),
          onPressed: () => setState(() => _fillMode = !_fillMode),
        ),
      ],
    );
  }
}
