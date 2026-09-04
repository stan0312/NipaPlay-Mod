import 'package:flutter/cupertino.dart';
import 'package:nipaplay/app/app_page_ids.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/app/adaptive_app_page_content.dart';
import 'package:nipaplay/app/app_page_component.dart';
import 'package:nipaplay/l10n/app_localizations.dart';

class AppPageAvailability {
  const AppPageAvailability({
    required this.showWebDAV,
    required this.showDownloader,
    this.showExternalPlayerConsole = false,
  });

  final bool showWebDAV;
  final bool showDownloader;
  final bool showExternalPlayerConsole;
}

class UnifiedAppPage {
  const UnifiedAppPage({
    required this.id,
    required this.titleBuilder,
    required this.phoneIcon,
    required this.phoneActiveIcon,
    required this.phoneSymbol,
    required this.phoneActiveSymbol,
    required this.components,
    this.actionIds = const <String>[],
  });

  final String id;
  final String Function(AppLocalizations localizations) titleBuilder;
  final IconData phoneIcon;
  final IconData phoneActiveIcon;
  final String phoneSymbol;
  final String phoneActiveSymbol;
  final List<AppPageComponent> components;
  final List<String> actionIds;

  String title(AppLocalizations localizations) => titleBuilder(localizations);

  Widget build(BuildContext context, AppDisplaySurface surface) {
    return AppDisplaySurfaceScope(
      surface: surface,
      child: KeyedSubtree(
        key: PageStorageKey<String>('app-page-$id'),
        child: AdaptiveAppPageContent(
          components: components,
        ),
      ),
    );
  }
}

List<UnifiedAppPage> buildUnifiedAppPages(
    {required AppPageAvailability availability}) {
  const commonActions = <String>[
    AppActionIds.toggleTheme,
    AppActionIds.settings,
  ];

  // [QBSenHook] v7.3: 只保留媒体库 tab。去掉"视频播放"和"个人中心"tab，
  // 打开 App 即进媒体库；个人中心/设置统一从媒体库右上角设置入口进入。
  return <UnifiedAppPage>[
    UnifiedAppPage(
      id: AppPageIds.mediaLibrary,
      titleBuilder: (localizations) => localizations.tabMediaLibrary,
      phoneIcon: CupertinoIcons.collections,
      phoneActiveIcon: CupertinoIcons.collections_solid,
      phoneSymbol: 'rectangle.stack',
      phoneActiveSymbol: 'rectangle.stack.fill',
      components: const [
        AppPageComponent(
          id: 'media-library',
          type: AppPageComponentType.mediaLibrary,
        ),
      ],
      actionIds: commonActions,
    ),
  ];
}

int appPageIndexById(List<UnifiedAppPage> pages, String? pageId) {
  if (pageId == null) return -1;
  return pages.indexWhere((page) => page.id == pageId);
}

String effectiveAppPageId(
  List<UnifiedAppPage> pages,
  String? requestedPageId,
) {
  if (appPageIndexById(pages, requestedPageId) >= 0) {
    return requestedPageId!;
  }
  return pages.isEmpty ? AppPageIds.home : pages.first.id;
}
