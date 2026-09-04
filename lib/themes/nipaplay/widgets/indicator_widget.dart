import 'package:flutter/material.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';

// [QBSenHook] v7.5.4: 亮度/音量指示器 —— 白色半透明磨砂风格
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
            child: Container(
              width: 58,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.28),
                  width: 0.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Icon(
                    getIcon(videoState),
                    color: Colors.white.withValues(alpha: 0.95),
                    size: 20,
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: globals.isDesktopOrTablet
                        ? MediaQuery.of(context).size.height * 0.28
                        : MediaQuery.of(context).size.height * 0.5,
                    child: RotatedBox(
                      quarterTurns: 3,
                      child: SizedBox(
                        height: 6,
                        child: LinearProgressIndicator(
                          value: getValue(videoState),
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.25),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white.withValues(alpha: 0.95),
                          ),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.all(5),
                    child: Text(
                      "${(getValue(videoState) * 100).toInt()}%",
                      locale: const Locale("zh-Hans", "zh"),
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          decoration: TextDecoration.none),
                    ),
                  )
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
