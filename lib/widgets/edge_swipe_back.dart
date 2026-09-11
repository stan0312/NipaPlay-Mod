import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// [QBSenHook] v8.5: 统一"速度感应"的左缘右滑返回手势。
///
/// 相比 v8.3 的 GestureDetector 实现（位移 40px 兜底导致慢速快进被误判为返回），
/// v8.5 改用 Listener 纯速度判定：
/// - 不参与手势竞技场：慢速滑动（快进快退/拖动进度条）完全不受影响；
/// - 只有"快速向右滑动"（速度 > [minVelocity]）才触发返回。
/// 触发条件：起手位置在屏幕左缘 [edgeWidth] 内，且松手时整体滑动速度 > [minVelocity]。
class EdgeSwipeBack extends StatelessWidget {
  final Widget child;
  final VoidCallback? onBack;
  final double edgeWidth;
  final double minVelocity;

  const EdgeSwipeBack({
    super.key,
    required this.child,
    this.onBack,
    this.edgeWidth = 90,
    this.minVelocity = 500,
  });

  @override
  Widget build(BuildContext context) {
    return _EdgeSwipeBackGesture(
      onBack: onBack ?? () => Navigator.maybePop(context),
      edgeWidth: edgeWidth,
      minVelocity: minVelocity,
      overlay: false,
      child: child,
    );
  }
}

/// [QBSenHook] v8.5: 叠放在 Stack 顶层的左缘返回窄条（Listener 版）。
/// 用于页面自身存在横向手势的场景（如刷片页左右滑快进快退），
/// 不拦截指针、不参与手势竞争，仅快速右滑时触发返回。
class EdgeSwipeBackOverlay extends StatelessWidget {
  final VoidCallback? onBack;
  final double edgeWidth;
  final double minVelocity;

  const EdgeSwipeBackOverlay({
    super.key,
    this.onBack,
    this.edgeWidth = 90,
    this.minVelocity = 500,
  });

  @override
  Widget build(BuildContext context) {
    return _EdgeSwipeBackGesture(
      onBack: onBack ?? () => Navigator.maybePop(context),
      edgeWidth: edgeWidth,
      minVelocity: minVelocity,
      overlay: true,
      child: null,
    );
  }
}

class _EdgeSwipeBackGesture extends StatefulWidget {
  final VoidCallback onBack;
  final double edgeWidth;
  final double minVelocity;
  final bool overlay;
  final Widget? child;

  const _EdgeSwipeBackGesture({
    required this.onBack,
    required this.edgeWidth,
    required this.minVelocity,
    required this.overlay,
    this.child,
  });

  @override
  State<_EdgeSwipeBackGesture> createState() => _EdgeSwipeBackGestureState();
}

class _EdgeSwipeBackGestureState extends State<_EdgeSwipeBackGesture> {
  double? _startX;
  Duration? _downTime;
  double _totalDx = 0;

  void _onPointerDown(PointerDownEvent e) {
    _startX = e.localPosition.dx;
    _downTime = e.timeStamp;
    _totalDx = 0;
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (_startX == null) return;
    _totalDx = e.localPosition.dx - _startX!;
  }

  void _onPointerUp(PointerUpEvent e) {
    final double? s = _startX;
    final Duration? t = _downTime;
    _startX = null;
    _downTime = null;
    if (s == null || t == null || s > widget.edgeWidth) return;
    final elapsedMs = (e.timeStamp - t).inMilliseconds;
    if (elapsedMs <= 0) return;
    // 整体平均速度（px/s）：快滑才返回
    final velocity = _totalDx * 1000 / elapsedMs;
    if (velocity > widget.minVelocity) {
      widget.onBack();
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget listener = Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: (_) {
        _startX = null;
        _downTime = null;
      },
      child: widget.child,
    );
    if (widget.overlay) {
      return Positioned(
        left: 0,
        top: 0,
        bottom: 0,
        width: widget.edgeWidth,
        child: listener,
      );
    }
    return listener;
  }
}
