import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show ColorScheme, Theme;
import 'package:nipaplay/player_menu/player_menu_models.dart';
import 'package:nipaplay/player_menu/player_menu_pane_controllers.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_audio_tracks_pane.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_danmaku_offset_pane.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_jellyfin_quality_pane.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_playback_info_pane.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_playback_rate_pane.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_playlist_pane.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_seek_step_pane.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_subtitle_list_pane.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_subtitle_settings_pane.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_subtitle_tracks_pane.dart';
import 'package:nipaplay/utils/app_accent_color.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';

/// Renders the canonical full player-menu pane inside a large-screen host.
///
/// Pane widgets retain their existing data loading and playback operations.
/// Their shared adaptive primitives switch to television focus surfaces while
/// this host is mounted under [NipaplayLargeScreenModeScope].
class NipaplayLargeScreenPlayerMenuPaneHost extends StatelessWidget {
  const NipaplayLargeScreenPlayerMenuPaneHost({
    super.key,
    required this.paneId,
    required this.videoState,
  });

  final PlayerMenuPaneId paneId;
  final VideoPlayerState videoState;

  @override
  Widget build(BuildContext context) {
    final materialTheme = Theme.of(context);
    final brightness = materialTheme.brightness;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppAccentColors.current,
      brightness: brightness,
    );
    return CupertinoTheme(
      data: CupertinoThemeData(
        brightness: brightness,
        primaryColor: AppAccentColors.current,
        scaffoldBackgroundColor: CupertinoColors.transparent,
        textTheme: CupertinoTextThemeData(
          textStyle: TextStyle(color: colorScheme.onSurface),
          navLargeTitleTextStyle: TextStyle(
            color: colorScheme.onSurface,
            fontSize: 28,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      child: KeyedSubtree(
        key: ValueKey<PlayerMenuPaneId>(paneId),
        child: _buildPane(),
      ),
    );
  }

  Widget _buildPane() {
    switch (paneId) {
      case PlayerMenuPaneId.subtitleTracks:
        return CupertinoSubtitleTracksPane(videoState: videoState);
      case PlayerMenuPaneId.subtitleSettings:
        return ChangeNotifierProvider(
          create: (_) => SubtitleSettingsPaneController(videoState: videoState),
          child: const CupertinoSubtitleSettingsPane(),
        );
      case PlayerMenuPaneId.subtitleList:
        return CupertinoSubtitleListPane(videoState: videoState);
      case PlayerMenuPaneId.audioTracks:
        return CupertinoAudioTracksPane(videoState: videoState);
      // [QBSenHook] 已移除弹幕相关面板
      case PlayerMenuPaneId.danmakuSettings:
      case PlayerMenuPaneId.danmakuTracks:
      case PlayerMenuPaneId.danmakuList:
      case PlayerMenuPaneId.danmakuOffset:
        return const SizedBox.shrink();
      case PlayerMenuPaneId.playbackRate:
        return ChangeNotifierProvider(
          create: (_) => PlaybackRatePaneController(videoState: videoState),
          child: const CupertinoPlaybackRatePane(),
        );
      case PlayerMenuPaneId.seekStep:
        return ChangeNotifierProvider(
          create: (_) => SeekStepPaneController(videoState: videoState),
          child: const CupertinoSeekStepPane(),
        );
      case PlayerMenuPaneId.playbackInfo:
        return CupertinoPlaybackInfoPane(videoState: videoState);
      case PlayerMenuPaneId.playlist:
        return CupertinoPlaylistPane(videoState: videoState);
      case PlayerMenuPaneId.jellyfinQuality:
        return CupertinoJellyfinQualityPane(videoState: videoState);
    }
  }
}
