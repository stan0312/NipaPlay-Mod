/// Web stub for desktop_multi_window — all features are no-ops on web.
library desktop_multi_window;

import 'package:flutter/widgets.dart';

/// Stub WindowController — no-op on web.
class WindowController {
  int get viewId => -1;
  bool get isClosed => true;
  void get pointer => null;
  Future<void> setSize(Size size) async {}
  Future<void> setPosition(Offset position) async {}
  Future<void> close() async {}
  Future<void> show() async {}
  Future<void> hide() async {}
  Future<void> setTitle(String title) async {}
  Future<void> setPreventClose(bool prevent) async {}
  void startDragging(Offset globalPosition) {}
  void updateDragging(Offset globalPosition) {}
  void endDragging(Offset globalPosition) {}
}

/// Stub DesktopTooltipWindowController — no-op on web.
class DesktopTooltipWindowController {
  int get viewId => -1;
  Future<void> close() async {}
}

/// Stub DesktopMultiWindow — all static methods return safe defaults on web.
class DesktopMultiWindow {
  static bool get isSupported => false;
  static bool get supportsTooltipWindows => false;

  static bool isSecondaryWindow(BuildContext context) => false;

  static WindowController? maybeControllerOf(BuildContext context) => null;

  static WindowController controllerOf(BuildContext context) {
    throw UnsupportedError('DesktopMultiWindow is not available on web');
  }

  static Future<WindowController> createWindow(
    Map<String, dynamic> args,
  ) async {
    throw UnsupportedError('DesktopMultiWindow is not available on web');
  }

  static Future<DesktopTooltipWindowController> createTooltipWindow(
    BuildContext context, {
    required Widget Function(BuildContext context, Widget? child) builder,
  }) async {
    throw UnsupportedError('DesktopMultiWindow is not available on web');
  }

  static void detachTransientView(DesktopTooltipWindowController controller) {}
}

/// Stub DesktopMultiWindowHost — just returns child on web.
class DesktopMultiWindowHost extends StatelessWidget {
  final Widget child;
  const DesktopMultiWindowHost({super.key, required this.child});

  @override
  Widget build(BuildContext context) => child;
}

/// Stub DesktopTransientWindowPlacement enum.
enum DesktopTransientWindowPlacement { above, below, left, right, center }

/// Stub runDesktopMultiWindowApp — just calls runApp on web.
void runDesktopMultiWindowApp(Widget app) {
  runApp(app);
}
