import 'package:flutter/material.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';

// [QBSenHook] v7.5.4: 亮度/音量指示器 —— 白色半透明磨砂风格
// [QBSenHook] v8.0: 改为"极细一条、无背景"——去掉卡片背景/边框/阴影，
// 只保留一条极细竖线 + 小图标 + 百分比文字。
class IndicatorWidget extends StatelessWidget {
  final bool Function(VideoPlayerState) isVisible;
  final double Function(VideoPlayerState) getValue;
  final IconData Function(VideoPlayerState) getIcon;

  const IndicatorWidget({
    super.key,
    required this.isVisible,
    required this.getValue,
    required this.getIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        return IgnorePointer(
          child: AnimatedOpacity(
            opacity: isVisible(videoState) ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 150),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  getIcon(videoState),
                  color: Colors.white.withValues(alpha: 0.9),
                  size: 16,
                  shadows: const [
                    Shadow(color: Colors.black54, blurRadius: 4),
                  ],
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: globals.isDesktopOrTablet
                      ? MediaQuery.of(context).size.height * 0.28
                      : MediaQuery.of(context).size.height * 0.42,
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: SizedBox(
                      width: 3,
                      child: LinearProgressIndicator(
                        value: getValue(videoState),
                        backgroundColor:
                            Colors.white.withValues(alpha: 0.22),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white.withValues(alpha: 0.95),
                        ),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.all(2),
                  child: Text(
                    "${(getValue(videoState) * 100).toInt()}%",
                    locale: const Locale("zh-Hans", "zh"),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      decoration: TextDecoration.none,
                      shadows: const [
                        Shadow(color: Colors.black54, blurRadius: 3),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
