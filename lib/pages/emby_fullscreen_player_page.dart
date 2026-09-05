import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nipaplay/pages/emby_track_menu.dart';
import 'package:nipaplay/utils/screen_orientation_manager.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';

/// [QBSenHook] v7.5.2: 画面尺寸模式。
enum EmbyFitMode {
  original('原始'),
  cover('填满'),
  r16_9('16:9'),
  r4_3('4:3'),
  r1_1('1:1'),
  r9_16('9:16');

  const EmbyFitMode(this.label);
  final String label;
}

/// [QBSenHook] v7.4: 抖音式刷片页的全屏播放页。
///
/// [QBSenHook] v7.5.x 增强：
/// - 双击：暂停/播放（统一操作）；单击：调出播放控件，2 秒自动隐藏；
/// - 左右滑：快进/快退（各 10 秒），与进度条拖动平行互不干扰；
/// - 方向：默认按 preferredOrientation（auto=按视频分辨率 / portrait / landscape），
///   控件内可随时循环切换（自动→竖屏→横屏）；
/// - 画面尺寸：多个模式可选（原始/填满/16:9/4:3/1:1/9:16），均不拉伸；
/// - 播放器控件：播放/暂停、快退、快进、倍速、尺寸、方向、进度条、时间、返回。
class EmbyFullscreenPlayerPage extends StatefulWidget {
  const EmbyFullscreenPlayerPage({
    super.key,
    this.preferredOrientation = 'auto',
    this.initialFitMode = EmbyFitMode.original,
  });

  /// 进入时方向：'auto'（按视频分辨率）| 'portrait' | 'landscape'
  final String preferredOrientation;
  final EmbyFitMode initialFitMode;

  @override
  State<EmbyFullscreenPlayerPage> createState() =>
      _EmbyFullscreenPlayerPageState();
}

class _EmbyFullscreenPlayerPageState extends State<EmbyFullscreenPlayerPage> {
  bool _orientationApplied = false;
  late String _orientation;
  late EmbyFitMode _fitMode;
  bool _controlsVisible = true;
  Timer? _controlsTimer;
  double? _dragValue; // 拖动进度条时的临时值（跟手）

  static const List<double> _speedOptions = [1.0, 1.25, 1.5, 2.0];

  @override
  void initState() {
    super.initState();
    _orientation = widget.preferredOrientation;
    _fitMode = widget.initialFitMode;
    // [QBSenHook] v7.5.4: 全屏播放器允许按视频尺寸选择横竖方向
    ScreenOrientationManager.instance.forcePortraitPlayback = false;
    _startControlsTimer();
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    // [QBSenHook] v7.5: 离开全屏页恢复竖屏（回到刷片页/详情页）
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    super.dispose();
  }

  /// 显示控件并重置 3 秒自动隐藏计时。
  void _showControls() {
    if (!mounted) return;
    setState(() => _controlsVisible = true);
    _startControlsTimer();
  }

  void _startControlsTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

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

  /// 按方向设置屏幕方向（auto 时按视频分辨率）。
  void _applyOrientation(VideoPlayerState videoState) {
    if (_orientationApplied) return;
    _orientationApplied = true;
    if (_orientation == 'portrait') {
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]);
      return;
    }
    if (_orientation == 'landscape') {
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      return;
    }
    final ratio = _aspectRatio(videoState);
    if (ratio == null) return;
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

  /// 循环切换方向：自动 → 竖屏 → 横屏 → 自动。
  void _cycleOrientation() {
    setState(() {
      if (_orientation == 'auto') {
        _orientation = 'portrait';
      } else if (_orientation == 'portrait') {
        _orientation = 'landscape';
      } else {
        _orientation = 'auto';
      }
      _orientationApplied = false;
    });
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

  /// [QBSenHook] v7.5.2: 循环切换画面尺寸模式。
  void _cycleFitMode() {
    setState(() {
      final values = EmbyFitMode.values;
      _fitMode = values[(_fitMode.index + 1) % values.length];
    });
  }

  String _orientationLabel() {
    switch (_orientation) {
      case 'portrait':
        return '竖屏';
      case 'landscape':
        return '横屏';
      default:
        return '自动';
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
              // 视频画面区（双击暂停/播放、单击调出控件、左右滑快进快退）
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _showControls,
                  onDoubleTap: _togglePlayPause,
                  onHorizontalDragEnd: _onHorizontalDragEnd,
                  child: _buildVideo(videoState, ratio),
                ),
              ),
              // 顶部：返回按钮 + 文件名（无背景，半透明）
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        Expanded(
                          child: AnimatedOpacity(
                            opacity: _controlsVisible ? 1 : 0,
                            duration: const Duration(milliseconds: 200),
                            child: Text(
                              videoState.currentMediaKey ?? '全屏播放',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 14,
                                shadows: const [
                                  Shadow(
                                    color: Colors.black45,
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // 底部：极细进度条 + 控制按钮同一排（无背景，半透明）
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: AnimatedOpacity(
                  opacity: _controlsVisible ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(
                    ignoring: !_controlsVisible,
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
                        child: _buildControlRow(videoState),
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
        switch (_fitMode) {
          case EmbyFitMode.cover:
            // 填满屏幕、居中裁剪，不拉伸
            return FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: maxW,
                height: hForWidth,
                child: texture,
              ),
            );
          case EmbyFitMode.original:
            // 原始比例：宽优先铺满，高度受限时 contain，不拉伸
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
          default:
            // 固定比例框内 contain（16:9 / 4:3 / 1:1 / 9:16），不拉伸
            final double boxRatio = _fitModeBoxRatio();
            return Center(
              child: AspectRatio(
                aspectRatio: boxRatio,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: 100,
                    height: 100 / ratio,
                    child: texture,
                  ),
                ),
              ),
            );
        }
      },
    );
  }

  double _fitModeBoxRatio() {
    switch (_fitMode) {
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
    final Duration total = videoState.duration;
    final Duration pos = videoState.position;
    final double totalMs = total.inMilliseconds.toDouble();
    final double maxMs = totalMs > 0 ? totalMs : 1.0;
    final double value =
        (_dragValue ?? (pos.inMilliseconds.toDouble() / maxMs).clamp(0.0, 1.0))
            .clamp(0.0, 1.0);
    // [QBSenHook] v7.5.5: 极细进度条 + 控制按钮同一排、无背景、半透明精致样式
    return Row(
      children: [
        Text(
          _formatDuration(_dragValue != null
              ? Duration(milliseconds: (_dragValue! * maxMs).round())
              : pos),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontSize: 11,
            shadows: const [Shadow(color: Colors.black54, blurRadius: 3)],
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              activeTrackColor: Colors.white.withValues(alpha: 0.9),
              inactiveTrackColor: Colors.white.withValues(alpha: 0.25),
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
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontSize: 11,
            shadows: const [Shadow(color: Colors.black54, blurRadius: 3)],
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          icon: Icon(
            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: Colors.white.withValues(alpha: 0.9),
            size: 30,
          ),
          onPressed: () => _togglePlayPause(),
        ),
        _miniChip('${videoState.playbackRate.toStringAsFixed(2)}x',
            () => _cyclePlaybackRate(videoState)),
        const SizedBox(width: 6),
        _miniChip(_fitMode.label, _cycleFitMode),
        const SizedBox(width: 6),
        _miniChip(_orientationLabel(), _cycleOrientation),
        const SizedBox(width: 6),
        _miniIcon(Icons.audiotrack_rounded,
            () => EmbyTrackMenu.showAudioTracks(context, videoState)),
        const SizedBox(width: 4),
        _miniIcon(Icons.subtitles_rounded,
            () => EmbyTrackMenu.showSubtitleTracks(context, videoState)),
      ],
    );
  }

  /// [QBSenHook] v7.5.5: 紧凑文字按钮（无背景、半透明、带阴影）
  Widget _miniChip(String label, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: 13,
            fontWeight: FontWeight.w500,
            shadows: const [Shadow(color: Colors.black54, blurRadius: 3)],
          ),
        ),
      ),
    );
  }

  /// [QBSenHook] v7.5.5: 紧凑图标按钮（无背景、半透明）
  Widget _miniIcon(IconData icon, VoidCallback onTap) {
    return IconButton(
      icon: Icon(icon, color: Colors.white.withValues(alpha: 0.9), size: 20),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 34),
      onPressed: onTap,
    );
  }
}
