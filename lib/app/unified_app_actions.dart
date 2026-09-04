import 'package:nipaplay/app/app_page_ids.dart';

enum UnifiedAppActionKind {
  command,
  openView,
}

class UnifiedAppActionDefinition {
  const UnifiedAppActionDefinition.command({required this.id})
      : kind = UnifiedAppActionKind.command,
        targetViewId = null;

  const UnifiedAppActionDefinition.openView({
    required this.id,
    required this.targetViewId,
  }) : kind = UnifiedAppActionKind.openView;

  final String id;
  final UnifiedAppActionKind kind;
  final String? targetViewId;
}

const List<UnifiedAppActionDefinition> unifiedAppActions =
    <UnifiedAppActionDefinition>[
  // [QBSenHook] v7.5: 搜索与抖音刷片为 command，在 CupertinoAppPageActions 中
  // 直接 push 对应页面（EmbySearchPage / EmbySwipePage）。
  UnifiedAppActionDefinition.command(id: AppActionIds.search),
  UnifiedAppActionDefinition.command(id: AppActionIds.swipe),
  UnifiedAppActionDefinition.command(id: AppActionIds.toggleTheme),
  UnifiedAppActionDefinition.openView(
    id: AppActionIds.settings,
    targetViewId: AppPageIds.settings,
  ),
];

UnifiedAppActionDefinition? unifiedAppActionById(String id) {
  for (final action in unifiedAppActions) {
    if (action.id == id) return action;
  }
  return null;
}
