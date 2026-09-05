
// lib/models/external_player_session/potplayer_session_stub.dart
// [QBSenHook] v7.5.4: Web 平台占位实现。
// potplayer_session.dart 依赖 dart:ffi（仅 Windows 可用），web 编译会失败；
// 此 stub 用于条件导入（if dart.library.html），web 上 PotPlayer 不会被使用。

import 'package:flutter/foundation.dart';
import 'package:nipaplay/constants/media_extensions.dart';
import 'package:nipaplay/models/danmaku/danmaku_item.dart';
import 'package:nipaplay/models/danmaku/style.dart';
import 'package:nipaplay/models/external_player_session/session.dart';

/// Web 平台的 PotPlayer 占位实现：任何调用都抛出 [UnsupportedError]。
class PotPlayerSession extends ChangeNotifier
    implements ExternalPlayerLaunchSession {
  factory PotPlayerSession({
    required String playerPath,
    required String mediaPath,
    required Duration duration,
    Duration initialPosition = Duration.zero,
    List<String> extraArgs = const <String>[],
    DanmakuItemSet? initialDanmakuSet,
  }) {
    throw UnsupportedError('PotPlayerSession 仅支持 Windows 平台');
  }

  PotPlayerSession._();

  @override
  ExternalPlayerType get type => ExternalPlayerType.potPlayer;
  @override
  String get playerPath => throw UnsupportedError('不支持');
  @override
  String get mediaPath => throw UnsupportedError('不支持');
  @override
  int get processId => 0;
  @override
  String? get ipcPath => null;
  @override
  Duration get duration => Duration.zero;
  @override
  Duration? get position => Duration.zero;
  @override
  bool? get isPaused => false;
  @override
  double? get fraction => null;
  @override
  bool get isClosed => true;

  @override
  Future<void> launch() async => throw UnsupportedError('不支持');
  @override
  void terminate() {}
  @override
  void togglePause() {}
  @override
  void seekToFraction(double fraction) {}
  @override
  bool seekToPosition(Duration target) => false;
  @override
  Future<bool> refreshDanmaku(DanmakuItemSet danmakuSet, DanmakuStyle style) async =>
      false;
}
