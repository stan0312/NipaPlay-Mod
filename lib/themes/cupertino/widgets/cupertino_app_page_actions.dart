import 'dart:async';

import 'package:flutter/material.dart' show ThemeMode, MaterialPageRoute;
import 'package:nipaplay/app/app_page_ids.dart';
import 'package:nipaplay/app/unified_app_actions.dart';
import 'package:nipaplay/app/unified_app_view_presenter.dart';
import 'package:nipaplay/pages/emby_search_page.dart';
import 'package:nipaplay/pages/emby_swipe_page.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_glass_button_group.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_page_actions_scope.dart';
import 'package:nipaplay/utils/theme_notifier.dart';
import 'package:provider/provider.dart';

class CupertinoAppPageActions extends StatelessWidget {
  const CupertinoAppPageActions({
    super.key,
    required this.actionIds,
  });

  final List<String> actionIds;

  @override
  Widget build(BuildContext context) {
    final controller = CupertinoPageActionsScope.maybeOf(context);
    if (controller == null) return _buildActions(context, const []);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => _buildActions(context, controller.actions),
    );
  }

  Widget _buildActions(
    BuildContext context,
    List<CupertinoPageAction> pageActions,
  ) {
    if (actionIds.isEmpty && pageActions.isEmpty) {
      return const SizedBox.shrink();
    }

    // [QBSenHook] v7.5: 顶部统一控件组。按 actionIds 的顺序渲染，
    // 让搜索、抖音刷片、夜间模式、设置同排、图标同大小（44）。
    final List<CupertinoGlassButtonGroupItem> items = [];
    for (final action in pageActions) {
      items.add(
        CupertinoGlassButtonGroupItem(
          label: action.label,
          icon: action.icon,
          onPressed: action.onPressed,
        ),
      );
    }
    for (final id in actionIds) {
      if (id == AppActionIds.search) {
        items.add(
          CupertinoGlassButtonGroupItem(
            label: '搜索',
            icon: CupertinoIcons.search,
            onPressed: () => _performAction(context, AppActionIds.search),
          ),
        );
      } else if (id == AppActionIds.swipe) {
        items.add(
          CupertinoGlassButtonGroupItem(
            label: '抖音刷片',
            icon: CupertinoIcons.play_rectangle_fill,
            onPressed: () => _performAction(context, AppActionIds.swipe),
          ),
        );
      } else if (id == AppActionIds.toggleTheme) {
        items.add(
          CupertinoGlassButtonGroupItem(
            label: '切换深浅模式',
            icon: CupertinoTheme.brightnessOf(context) == Brightness.dark
                ? CupertinoIcons.sun_max_fill
                : CupertinoIcons.moon_fill,
            onPressed: () => _performAction(context, AppActionIds.toggleTheme),
          ),
        );
      } else if (id == AppActionIds.settings) {
        items.add(
          CupertinoGlassButtonGroupItem(
            label: '设置',
            icon: CupertinoIcons.gear_alt_fill,
            onPressed: () => _performAction(context, AppActionIds.settings),
          ),
        );
      }
    }

    return CupertinoGlassButtonGroup(
      buttonSize: 44,
      items: items,
    );
  }

  void _toggleTheme(BuildContext context) {
    final notifier = context.read<ThemeNotifier>();
    notifier.themeMode = CupertinoTheme.brightnessOf(context) == Brightness.dark
        ? ThemeMode.light
        : ThemeMode.dark;
  }

  void _performAction(BuildContext context, String actionId) {
    final action = unifiedAppActionById(actionId);
    if (action == null) return;

    switch (action.kind) {
      case UnifiedAppActionKind.command:
        if (action.id == AppActionIds.toggleTheme) {
          _toggleTheme(context);
        } else if (action.id == AppActionIds.search) {
          // [QBSenHook] v7.5: 顶部搜索入口 → 全屏 Emby 搜索页
          unawaited(
            Navigator.of(context).push(
              CupertinoPageRoute<void>(
                builder: (_) => const EmbySearchPage(),
              ),
            ),
          );
        } else if (action.id == AppActionIds.swipe) {
          // [QBSenHook] v7.5.4: 顶部抖音刷片入口 → 刷片页（Material 路由，
          // 排除左缘右滑返回，避免与亮度/音量边缘手势冲突）
          unawaited(
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const EmbySwipePage(),
              ),
            ),
          );
        }
        return;
      case UnifiedAppActionKind.openView:
        final targetViewId = action.targetViewId;
        if (targetViewId != null) {
          unawaited(
            UnifiedAppViewPresenter.show<void>(
              context,
              viewId: targetViewId,
            ),
          );
        }
        return;
    }
  }
}
