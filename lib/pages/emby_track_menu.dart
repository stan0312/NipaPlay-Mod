import 'package:flutter/cupertino.dart';
import 'package:nipaplay/player_abstraction/player_data_models.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/utils/video_player_state.dart';

/// [QBSenHook] v7.5.4: Emby 原生音轨/字幕选择菜单（全屏播放页 + 抖音刷片页共用）
class EmbyTrackMenu {
  const EmbyTrackMenu._();

  /// 音轨选择
  static Future<void> showAudioTracks(
    BuildContext context,
    VideoPlayerState videoState,
  ) async {
    final audio = videoState.player.mediaInfo.audio ?? [];
    final current = videoState.player.activeAudioTracks;

    await CupertinoBottomSheet.show<void>(
      context: context,
      title: '音轨',
      heightRatio: 0.6,
      child: Builder(
        builder: (sheetContext) {
          if (audio.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(28),
              child: Center(
                child: Text('无可用音轨', style: TextStyle(fontSize: 15)),
              ),
            );
          }
          return ListView.separated(
            itemCount: audio.length,
            separatorBuilder: (_, __) => Container(
              height: 0.5,
              margin: const EdgeInsets.only(left: 18),
              color: CupertinoDynamicColor.resolve(
                CupertinoColors.separator,
                sheetContext,
              ),
            ),
            itemBuilder: (context, index) {
              final track = audio[index];
              final isSelected = current.contains(index);
              return _TrackTile(
                label: _audioLabel(track, index),
                isSelected: isSelected,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  videoState.player.activeAudioTracks = [index];
                },
              );
            },
          );
        },
      ),
    );
  }

  /// 字幕选择
  static Future<void> showSubtitleTracks(
    BuildContext context,
    VideoPlayerState videoState,
  ) async {
    final subtitles = videoState.player.mediaInfo.subtitle ?? [];
    final current = videoState.player.activeSubtitleTracks;

    await CupertinoBottomSheet.show<void>(
      context: context,
      title: '字幕',
      heightRatio: 0.6,
      child: Builder(
        builder: (sheetContext) {
          if (subtitles.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(28),
              child: Center(
                child: Text('无可用字幕', style: TextStyle(fontSize: 15)),
              ),
            );
          }
          return ListView.separated(
            itemCount: subtitles.length + 2, // 字幕样式入口 + 关闭字幕 + 轨道
            separatorBuilder: (_, __) => Container(
              height: 0.5,
              margin: const EdgeInsets.only(left: 18),
              color: CupertinoDynamicColor.resolve(
                CupertinoColors.separator,
                sheetContext,
              ),
            ),
            itemBuilder: (context, index) {
              if (index == 0) {
                // [QBSenHook] v7.5.4: 字幕样式入口
                return _TrackTile(
                  label: '字幕样式…',
                  isSelected: false,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _showSubtitleStyleSheet(context, videoState);
                  },
                );
              }
              if (index == 1) {
                final off = current.isEmpty;
                return _TrackTile(
                  label: '关闭字幕',
                  isSelected: off,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    videoState.player.activeSubtitleTracks = [];
                  },
                );
              }
              final track = subtitles[index - 2];
              final isSelected = current.contains(index - 2);
              return _TrackTile(
                label: _subtitleLabel(track, index - 2),
                isSelected: isSelected,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  videoState.player.activeSubtitleTracks = [index - 2];
                },
              );
            },
          );
        },
      ),
    );
  }

  static String _audioLabel(PlayerAudioStreamInfo track, int index) {
    final codecName = track.codec.name;
    if (track.title != null && track.title!.isNotEmpty) {
      return '${track.title}${codecName != null && codecName.isNotEmpty ? ' · $codecName' : ''}';
    }
    if (track.language != null && track.language!.isNotEmpty) {
      return '${track.language}${codecName != null && codecName.isNotEmpty ? ' · $codecName' : ''}';
    }
    return '音轨 ${index + 1}${codecName != null && codecName.isNotEmpty ? ' · $codecName' : ''}';
  }

  static String _subtitleLabel(PlayerSubtitleStreamInfo track, int index) {
    if (track.title != null && track.title!.isNotEmpty) return track.title!;
    if (track.language != null && track.language!.isNotEmpty) {
      return track.language!;
    }
    return '字幕 ${index + 1}';
  }

  /// [QBSenHook] v7.5.4: 字幕样式面板（字号/位置/延迟/不透明度）
  static Future<void> _showSubtitleStyleSheet(
    BuildContext context,
    VideoPlayerState videoState,
  ) async {
    await CupertinoBottomSheet.show<void>(
      context: context,
      title: '字幕样式',
      heightRatio: 0.7,
      child: _SubtitleStylePane(videoState: videoState),
    );
  }
}

class _SubtitleStylePane extends StatefulWidget {
  final VideoPlayerState videoState;

  const _SubtitleStylePane({required this.videoState});

  @override
  State<_SubtitleStylePane> createState() => _SubtitleStylePaneState();
}

class _SubtitleStylePaneState extends State<_SubtitleStylePane> {
  double _scale = 1.0;
  double _position = 1.0;
  double _delay = 0.0;
  double _opacity = 1.0;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      final vs = widget.videoState;
      _scale = vs.subtitleScale;
      _position = vs.subtitlePosition;
      _delay = vs.subtitleDelaySeconds.clamp(-30.0, 30.0).toDouble();
      _opacity = vs.subtitleOpacity;
      _loaded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final labelColor = CupertinoDynamicColor.resolve(
      CupertinoColors.label,
      context,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        children: [
          _SliderRow(
            label: '字号',
            value: _scale,
            min: 0.6,
            max: 3.0,
            display: '${_scale.toStringAsFixed(2)}x',
            labelColor: labelColor,
            onChanged: (v) {
              setState(() => _scale = v);
              widget.videoState.setSubtitleScale(v);
            },
          ),
          _SliderRow(
            label: '位置',
            value: _position,
            min: 0.0,
            max: 1.0,
            display: '${(_position * 100).round()}%',
            labelColor: labelColor,
            onChanged: (v) {
              setState(() => _position = v);
              widget.videoState.setSubtitlePosition(v);
            },
          ),
          _SliderRow(
            label: '延迟',
            value: _delay,
            min: -30.0,
            max: 30.0,
            display: '${_delay.toStringAsFixed(1)}s',
            labelColor: labelColor,
            onChanged: (v) {
              setState(() => _delay = v);
              widget.videoState.setSubtitleDelaySeconds(v);
            },
          ),
          _SliderRow(
            label: '不透明度',
            value: _opacity,
            min: 0.0,
            max: 1.0,
            display: '${(_opacity * 100).round()}%',
            labelColor: labelColor,
            onChanged: (v) {
              setState(() => _opacity = v);
              widget.videoState.setSubtitleOpacity(v);
            },
          ),
          const SizedBox(height: 12),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            color: CupertinoDynamicColor.resolve(
              CupertinoColors.systemGrey5,
              context,
            ),
            borderRadius: BorderRadius.circular(10),
            onPressed: () {
              setState(() {
                _scale = 1.0;
                _position = 1.0;
                _delay = 0.0;
                _opacity = 1.0;
              });
              final vs = widget.videoState;
              vs.setSubtitleScale(1.0);
              vs.setSubtitlePosition(1.0);
              vs.setSubtitleDelaySeconds(0.0);
              vs.setSubtitleOpacity(1.0);
            },
            child: const Text('重置为默认', style: TextStyle(fontSize: 14)),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final String display;
  final Color labelColor;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.labelColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(label,
              style: TextStyle(fontSize: 14, color: labelColor)),
        ),
        Expanded(
          child: CupertinoSlider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 48,
          child: Text(
            display,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 13, color: CupertinoColors.systemGrey),
          ),
        ),
      ],
    );
  }
}

class _TrackTile extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _TrackTile({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final labelColor = CupertinoDynamicColor.resolve(
      CupertinoColors.label,
      context,
    );
    final accent = CupertinoDynamicColor.resolve(
      CupertinoColors.activeBlue,
      context,
    );
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      onPressed: onTap,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                color: isSelected ? accent : labelColor,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          if (isSelected)
            const Icon(CupertinoIcons.check_mark, size: 18, color: CupertinoColors.activeBlue),
        ],
      ),
    );
  }
}
