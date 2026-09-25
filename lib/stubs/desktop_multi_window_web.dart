/// Web stub for desktop_multi_window — all features are no-ops on web.
library desktop_multi_window;

import 'package:flutter/widgets.dart';

/// Stub WindowController — no-op on web.
class WindowController with ChangeNotifier {
  int get viewId => -1;
  bool get isClosed => true;
  bool get isFullscreen => false;
  dynamic get pointer => null;
  dynamic get flutterView => null;
  Future<void> setSize(Size size) async {}
  Future<void> setPosition(Offset position) async {}
  Future<void> close() async {}
  Future<void> show() async {}
  Future<void> hide() async {}
  Future<void> setTitle(String title) async {}
  Future<void> setPreventClose(bool prevent) async {}
  Future<void> setMinimumSize(Size size) async {}
  Future<void> setAspectRatio(double ratio) async {}
  Future<void> setFullscreen(bool fullscreen) async {}
  Future<void> startDragging([Offset? globalPosition]) async {}
  Future<void> updateDragging([Offset? globalPosition]) async {}
  Future<void> endDragging([Offset? globalPosition]) async {}
}

/// Stub DesktopTooltipWindowController — no-op on web.
class DesktopTooltipWindowController {
  int get viewId => -1;
  bool get isClosed => true;
  bool get ready => true;
  dynamic get flutterView => null;
  Future<void> close() async {}
  Future<void> updatePosition(Rect rect) async {}
}

/// Stub DesktopPopupWindowController — no-op on web.
class DesktopPopupWindowController {
  int get viewId => -1;
  bool get isClosed => true;
  bool get ready => true;
  dynamic get flutterView => null;
  Future<void> close() async {}
}

/// Stub DesktopTooltipWindow widget — just returns child on web.
class DesktopTooltipWindow extends StatelessWidget {
  final dynamic controller;
  final Widget child;
  const DesktopTooltipWindow({super.key, required this.controller, required this.child});

  @override
  Widget build(BuildContext context) => child;
}

/// Stub DesktopPopupWindow widget — just returns child on web.
class DesktopPopupWindow extends StatelessWidget {
  final dynamic controller;
  final Widget child;
  const DesktopPopupWindow({super.key, required this.controller, required this.child});

  @override
  Widget build(BuildContext context) => child;
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

  static Future<WindowController> createWindow({
    String? title,
    Size? size,
    Size? minimumSize,
    bool frameless = false,
    double? aspectRatio,
    Widget Function(BuildContext context, WindowController controller)? builder,
    void Function()? onClosed,
  }) async {
    throw UnsupportedError('DesktopMultiWindow is not available on web');
  }

  static Future<DesktopTooltipWindowController> createTooltipWindow(
    BuildContext context, {
    required Widget Function(BuildContext context, Widget? child) builder,
  }) async {
    throw UnsupportedError('DesktopMultiWindow is not available on web');
  }

  static Future<DesktopPopupWindowController> createPopupWindow(
    BuildContext context, {
    required Widget Function(BuildContext context, Widget? child) builder,
  }) async {
    throw UnsupportedError('DesktopMultiWindow is not available on web');
  }

  static void detachTransientView(dynamic controller) {}

  static void attachTransientView(dynamic controller, dynamic view) {}

  static Widget inheritTransientViewContext(
      BuildContext context, Widget child) {
    return child;
  }
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
