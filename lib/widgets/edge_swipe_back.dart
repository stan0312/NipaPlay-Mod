import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// [QBSenHook] v8.3: 统一"好滑"的左缘右滑返回手势。
///
/// 相比系统边缘手势（约 20pt 触发带）：触发区更宽（默认 90px）、
/// 速度要求更低（120px/s），并增加位移 40px 兜底——慢慢拖也能返回。
/// 触发条件：起手位置在屏幕左缘 [edgeWidth] 内，且
/// 松手向右速度 > [minVelocity] 或累计右移距离 > [minDistance]。
class EdgeSwipeBack extends StatelessWidget {
  final Widget child;
  final VoidCallback? onBack;
  final double edgeWidth;
  final double minVelocity;
  final double minDistance;

  const EdgeSwipeBack({
    super.key,
    required this.child,
    this.onBack,
    this.edgeWidth = 90,
    this.minVelocity = 120,
    this.minDistance = 40,
  });

  @override
  Widget build(BuildContext context) {
    return _EdgeSwipeBackGesture(
      onBack: onBack ?? () => Navigator.maybePop(context),
      edgeWidth: edgeWidth,
      minVelocity: minVelocity,
      minDistance: minDistance,
      overlay: false,
      child: child,
    );
  }
}

/// [QBSenHook] v8.3: 叠放在 Stack 顶层的左缘返回窄条。
/// 用于页面自身存在横向手势的场景（如刷片页左右滑快进快退），
/// 上层窄条优先命中，不与内层手势竞争。
class EdgeSwipeBackOverlay extends StatelessWidget {
  final VoidCallback? onBack;
  final double edgeWidth;
  final double minVelocity;
  final double minDistance;

  const EdgeSwipeBackOverlay({
    super.key,
    this.onBack,
    this.edgeWidth = 90,
    this.minVelocity = 120,
    this.minDistance = 40,
  });

  @override
  Widget build(BuildContext context) {
    return _EdgeSwipeBackGesture(
      onBack: onBack ?? () => Navigator.maybePop(context),
      edgeWidth: edgeWidth,
      minVelocity: minVelocity,
      minDistance: minDistance,
      overlay: true,
      child: null,
    );
  }
}

class _EdgeSwipeBackGesture extends StatefulWidget {
  final VoidCallback onBack;
  final double edgeWidth;
  final double minVelocity;
  final double minDistance;
  final bool overlay;
  final Widget? child;

  const _EdgeSwipeBackGesture({
    required this.onBack,
    required this.edgeWidth,
    required this.minVelocity,
    required this.minDistance,
    required this.overlay,
    this.child,
  });

  @override
  State<_EdgeSwipeBackGesture> createState() => _EdgeSwipeBackGestureState();
}

class _EdgeSwipeBackGestureState extends State<_EdgeSwipeBackGesture> {
  double? _startX;
  double _dx = 0;

  void _onStart(DragStartDetails d) {
    _startX = d.localPosition.dx;
    _dx = 0;
  }

  void _onUpdate(DragUpdateDetails d) {
    _dx += d.delta.dx;
  }

  void _onEnd(DragEndDetails d) {
    final double? s = _startX;
    _startX = null;
    if (s == null || s > widget.edgeWidth) return;
    final double v = d.primaryVelocity ?? 0;
    if (v > widget.minVelocity || _dx > widget.minDistance) {
      widget.onBack();
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget gesture = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: _onStart,
      onHorizontalDragUpdate: _onUpdate,
      onHorizontalDragEnd: _onEnd,
      onHorizontalDragCancel: () => _startX = null,
      child: widget.child,
    );
    if (widget.overlay) {
      return Positioned(
        left: 0,
        top: 0,
        bottom: 0,
        width: widget.edgeWidth,
        child: gesture,
      );
    }
    return gesture;
  }
}
