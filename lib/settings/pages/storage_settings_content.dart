import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/services/danmaku_cache_manager.dart';
import 'package:nipaplay/services/file_picker_service.dart';
import 'package:nipaplay/services/image_disk_cache.dart';
import 'package:nipaplay/settings/adaptive_settings_scope.dart';
import 'package:nipaplay/settings/adaptive_settings_widgets.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dropdown.dart';
import 'package:nipaplay/utils/image_cache_manager.dart';
import 'package:nipaplay/utils/settings_storage.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';

class StorageSettingsContent extends StatefulWidget {
  const StorageSettingsContent({super.key});

  @override
  State<StorageSettingsContent> createState() => _StorageSettingsContentState();
}

class _StorageSettingsContentState extends State<StorageSettingsContent> {
  bool _clearOnLaunch = false;
  bool _isLoading = true;
  bool _isClearing = false;
  bool _isClearingImageCache = false;
  // [QBSenHook] v8.0: 图片磁盘缓存占用（上限 2GB）
  int _diskCacheBytes = 0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isPhoneLayout = AdaptiveSettingsScope.isPhoneLayout(context);

    if (_isLoading) {
      return AdaptiveSettingsPage(
        children: const [
          Center(child: CircularProgressIndicator()),
        ],
      );
    }

    return AdaptiveSettingsPage(
      children: [
        AdaptiveSettingsSection(
          children: [
            AdaptiveSettingsTile<bool>.toggle(
              title: l10n.clearDanmakuCacheOnLaunchTitle,
              subtitle: isPhoneLayout
                  ? l10n.clearDanmakuCacheOnLaunchSubtitle
                  : l10n.clearDanmakuCacheOnLaunchSubtitleNipaplay,
              icon: Ionicons.refresh_outline,
              phoneIcon: cupertino.CupertinoIcons.refresh_circled,
              value: _clearOnLaunch,
              onChanged: _updateClearOnLaunch,
            ),
            AdaptiveSettingsTile<void>.card(
              title: l10n.clearDanmakuCacheNow,
              subtitle: _isClearing
                  ? l10n.clearingInProgress
                  : (isPhoneLayout
                      ? l10n.clearDanmakuCacheManualHint
                      : l10n.clearDanmakuCacheManualHintNipaplay),
              icon: Ionicons.trash_bin_outline,
              phoneIcon: cupertino.CupertinoIcons.trash,
              enabled: !_isClearing,
              isDestructive: true,
              onTap: () => _clearDanmakuCache(showSnack: true),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AdaptiveSettingsSection(
          children: [
            Consumer<VideoPlayerState>(
              builder: (context, videoState, child) {
                final currentPath =
                    (videoState.screenshotSaveDirectory ?? '').trim();
                final updatedMessage =
                    context.l10n.screenshotSaveLocationUpdated;
                return AdaptiveSettingsTile<void>.card(
                  title: context.l10n.screenshotSaveLocation,
                  subtitle: currentPath.isEmpty
                      ? context.l10n.defaultDownloadDir
                      : currentPath,
                  icon: Icons.camera_alt_outlined,
                  phoneIcon: cupertino.CupertinoIcons.camera,
                  onTap: () async {
                    final selected = await FilePickerService().pickDirectory(
                      initialDirectory:
                          currentPath.isEmpty ? null : currentPath,
                    );
                    if (selected == null || selected.trim().isEmpty) return;
                    await videoState.setScreenshotSaveDirectory(selected);
                    if (!mounted) return;
                    AdaptiveSnackBar.show(
                      this.context,
                      message: updatedMessage,
                      type: AdaptiveSnackBarType.success,
                    );
                  },
                );
              },
            ),
            if (defaultTargetPlatform == TargetPlatform.iOS)
              Consumer<VideoPlayerState>(
                builder: (context, videoState, child) {
                  return AdaptiveSettingsTile<ScreenshotSaveTarget>.dropdown(
                    title: context.l10n.screenshotDefaultSaveTarget,
                    subtitle: context.l10n.screenshotDefaultSaveTargetMessage,
                    icon: Icons.save_alt,
                    phoneIcon: cupertino.CupertinoIcons.photo_on_rectangle,
                    items: [
                      DropdownMenuItemData(
                        title: ScreenshotSaveTarget.ask.label,
                        value: ScreenshotSaveTarget.ask,
                        isSelected: videoState.screenshotSaveTarget ==
                            ScreenshotSaveTarget.ask,
                        description: context.l10n.screenshotSaveAskDescription,
                      ),
                      DropdownMenuItemData(
                        title: ScreenshotSaveTarget.photos.label,
                        value: ScreenshotSaveTarget.photos,
                        isSelected: videoState.screenshotSaveTarget ==
                            ScreenshotSaveTarget.photos,
                        description:
                            context.l10n.screenshotSavePhotosDescription,
                      ),
                      DropdownMenuItemData(
                        title: ScreenshotSaveTarget.file.label,
                        value: ScreenshotSaveTarget.file,
                        isSelected: videoState.screenshotSaveTarget ==
                            ScreenshotSaveTarget.file,
                        description: context.l10n.screenshotSaveFileDescription,
                      ),
                    ],
                    onChanged: videoState.setScreenshotSaveTarget,
                  );
                },
              ),
            AdaptiveSettingsTile<void>.card(
              // [QBSenHook] v8.0: 显示磁盘图片缓存占用 + 一键清理（上限 2GB）
              title: l10n.clearImageCache,
              subtitle: _isClearingImageCache
                  ? l10n.clearingInProgress
                  : (_diskCacheBytes > 0
                      ? '当前图片缓存占用：${_formatCacheBytes(_diskCacheBytes)}（上限 2GB）'
                      : l10n.clearImageCacheHint),
              icon: Ionicons.trash_outline,
              phoneIcon: cupertino.CupertinoIcons.trash,
              enabled: !_isClearingImageCache,
              isDestructive: true,
              onTap: _confirmClearImageCache,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _loadSettings() async {
    final value = await SettingsStorage.loadBool(
      SettingsKeys.clearDanmakuCacheOnLaunch,
      defaultValue: false,
    );
    // [QBSenHook] v8.0: 查询图片磁盘缓存占用
    var diskBytes = 0;
    try {
      diskBytes = await ImageDiskCache.sizeBytes();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _clearOnLaunch = value;
      _diskCacheBytes = diskBytes;
      _isLoading = false;
    });
  }

  // [QBSenHook] v8.0: 字节 -> 可读大小
  String _formatCacheBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    const units = ['KB', 'MB', 'GB'];
    var v = bytes.toDouble();
    var u = -1;
    while (v >= 1024 && u < units.length - 1) {
      v /= 1024;
      u++;
    }
    return u < 0 ? '$bytes B' : '${v.toStringAsFixed(1)} ${units[u]}';
  }

  Future<void> _updateClearOnLaunch(bool value) async {
    final enabledMessage = context.l10n.enabledClearOnLaunchSnack;
    setState(() {
      _clearOnLaunch = value;
    });
    await SettingsStorage.saveBool(
      SettingsKeys.clearDanmakuCacheOnLaunch,
      value,
    );
    if (value) {
      await _clearDanmakuCache(showSnack: false);
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: enabledMessage,
        type: AdaptiveSnackBarType.info,
      );
    }
  }

  Future<void> _clearDanmakuCache({required bool showSnack}) async {
    if (_isClearing) return;
    final successMessage = context.l10n.danmakuCacheCleared;
    final failedMessage = context.l10n.clearDanmakuCacheFailed;
    setState(() {
      _isClearing = true;
    });
    try {
      await DanmakuCacheManager.clearAllCache();
      if (!mounted || !showSnack) return;
      AdaptiveSnackBar.show(
        context,
        message: successMessage,
        type: AdaptiveSnackBarType.success,
      );
    } catch (e) {
      if (!mounted || !showSnack) return;
      AdaptiveSnackBar.show(
        context,
        message: failedMessage('$e'),
        type: AdaptiveSnackBarType.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isClearing = false;
        });
      }
    }
  }

  Future<void> _confirmClearImageCache() async {
    var confirmed = false;
    await AdaptiveAlertDialog.show(
      context: context,
      title: context.l10n.confirmClearCacheTitle,
      message: context.l10n.confirmClearImageCacheContent,
      actions: [
        AlertAction(
          title: context.l10n.cancel,
          style: AlertActionStyle.cancel,
          onPressed: () {},
        ),
        AlertAction(
          title: context.l10n.confirm,
          style: AlertActionStyle.destructive,
          onPressed: () {
            confirmed = true;
          },
        ),
      ],
    );

    if (!mounted || !confirmed) return;
    await _clearImageCache();
  }

  Future<void> _clearImageCache() async {
    if (_isClearingImageCache) return;
    final successMessage = context.l10n.imageCacheCleared;
    final failedMessage = context.l10n.clearImageCacheFailed;
    setState(() {
      _isClearingImageCache = true;
    });
    try {
      await ImageCacheManager.instance.clearCache();
      // [QBSenHook] v8.0: 一并清理图片磁盘缓存（2GB 上限目录）
      await ImageDiskCache.clear();
      var diskBytes = 0;
      try {
        diskBytes = await ImageDiskCache.sizeBytes();
      } catch (_) {}
      if (mounted) {
        setState(() => _diskCacheBytes = diskBytes);
      }
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: successMessage,
        type: AdaptiveSnackBarType.success,
      );
    } catch (e) {
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: failedMessage('$e'),
        type: AdaptiveSnackBarType.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isClearingImageCache = false;
        });
      }
    }
  }
}
