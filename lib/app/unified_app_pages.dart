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

  return <UnifiedAppPage>[
    UnifiedAppPage(
      id: AppPageIds.video,
      titleBuilder: (localizations) => localizations.tabVideoPlay,
      phoneIcon: CupertinoIcons.play_rectangle,
      phoneActiveIcon: CupertinoIcons.play_rectangle_fill,
      phoneSymbol: 'play.rectangle',
      phoneActiveSymbol: 'play.rectangle.fill',
      components: const [
        AppPageComponent(id: 'playback', type: AppPageComponentType.playback),
      ],
    ),
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
    UnifiedAppPage(
      id: AppPageIds.account,
      titleBuilder: (localizations) => localizations.tabAccount,
      phoneIcon: CupertinoIcons.person_crop_circle,
      phoneActiveIcon: CupertinoIcons.person_crop_circle_fill,
      phoneSymbol: 'person.crop.circle',
      phoneActiveSymbol: 'person.crop.circle.fill',
      components: const [
        AppPageComponent(id: 'account', type: AppPageComponentType.account),
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
