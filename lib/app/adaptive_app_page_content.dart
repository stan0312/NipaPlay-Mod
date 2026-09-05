import 'package:flutter/widgets.dart';
import 'package:nipaplay/app/app_page_component.dart';
import 'package:nipaplay/media_library/adaptive_media_library_page.dart';
import 'package:nipaplay/pages/emby_folder_browser_page.dart';
import 'package:nipaplay/settings/unified_settings_page.dart';
import 'package:nipaplay/widgets/desktop_player_page_slot.dart';

class AdaptiveAppPageContent extends StatelessWidget {
  const AdaptiveAppPageContent({
    super.key,
    required this.components,
  });

  final List<AppPageComponent> components;

  @override
  Widget build(BuildContext context) {
    const controls = UnifiedAppControlRegistry();
    final children = components
        .map(
          (component) => KeyedSubtree(
            key: ValueKey<String>('app-component-${component.id}'),
            child: controls.build(context, component),
          ),
        )
        .toList(growable: false);

    if (children.isEmpty) return const SizedBox.shrink();
    if (children.length == 1) return children.single;
    return Column(
      children: [
        for (final child in children) Expanded(child: child),
      ],
    );
  }
}

class UnifiedAppControlRegistry {
  const UnifiedAppControlRegistry();

  Widget build(BuildContext context, AppPageComponent component) {
    return switch (component.type) {
      // [QBSenHook] 已移除首页推荐流 / WebDAV / 种子下载 / 弹幕控制台
      AppPageComponentType.homeFeed => const SizedBox.shrink(),
      AppPageComponentType.playback => const DesktopPlayerPageSlot(),
      AppPageComponentType.webdavBrowser => const SizedBox.shrink(),
      // [QBSenHook] v7.6: 初始界面直接为文件夹方式浏览页（不再用媒体库方式浏览）
      AppPageComponentType.mediaLibrary => const EmbyFolderBrowserPage(),
      AppPageComponentType.torrentTasks => const SizedBox.shrink(),
      // [QBSenHook] account 页直接显示设置（个人中心已替换为设置）
      AppPageComponentType.account => const UnifiedSettingsPage(),
      AppPageComponentType.externalPlayerConsole => const SizedBox.shrink(),
    };
  }
}
