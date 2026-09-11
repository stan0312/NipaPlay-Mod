import 'dart:convert';
import 'package:nipaplay/utils/settings_storage.dart';

/// [QBSenHook] v8.5: 刷片播放记录。
///
/// 每次"返回上一层 / 退出软件"时把当前刷片列表的入口与最后播放的视频记一条。
/// 长按抖音按钮可列出历史记录，选择后恢复到对应分类/文件夹、从上次视频继续刷。
class SwipePlayRecord {
  final String sourceId; // 媒体库/文件夹 id
  final String sourceName; // 显示名
  final bool folderMode; // 来源模式：true=文件夹模式，false=视频陈列
  final String sortName; // SwipeSort.name
  final bool sortAscending;
  final String lastItemId; // 最后播放的视频 id
  final String lastItemName;
  final DateTime time;

  const SwipePlayRecord({
    required this.sourceId,
    required this.sourceName,
    required this.folderMode,
    required this.sortName,
    required this.sortAscending,
    required this.lastItemId,
    required this.lastItemName,
    required this.time,
  });

  static const String _storageKey = 'swipe_play_records';
  static const int _maxRecords = 20;

  Map<String, dynamic> toJson() => {
        'sourceId': sourceId,
        'sourceName': sourceName,
        'folderMode': folderMode,
        'sortName': sortName,
        'sortAscending': sortAscending,
        'lastItemId': lastItemId,
        'lastItemName': lastItemName,
        'time': time.toIso8601String(),
      };

  factory SwipePlayRecord.fromJson(Map<String, dynamic> json) {
    return SwipePlayRecord(
      sourceId: json['sourceId'] as String? ?? '',
      sourceName: json['sourceName'] as String? ?? '',
      folderMode: json['folderMode'] as bool? ?? false,
      sortName: json['sortName'] as String? ?? 'dateCreated',
      sortAscending: json['sortAscending'] as bool? ?? false,
      lastItemId: json['lastItemId'] as String? ?? '',
      lastItemName: json['lastItemName'] as String? ?? '',
      time: DateTime.tryParse(json['time'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  /// 读取全部记录（新的在前）。
  static Future<List<SwipePlayRecord>> loadRecords() async {
    final raw = await SettingsStorage.loadString(_storageKey);
    if (raw.isEmpty) return [];
    try {
      final list = json.decode(raw);
      if (list is! List) return [];
      final records = list
          .whereType<Map>()
          .map((e) => SwipePlayRecord.fromJson(
              Map<String, dynamic>.from(e as Map)))
          .toList();
      records.sort((a, b) => b.time.compareTo(a.time));
      return records;
    } catch (_) {
      return [];
    }
  }

  /// 记录一条；[QBSenHook] v8.5: 同一视频（lastItemId）去重——只保留最后一次播放该视频的记录，新的在前。
  static Future<void> saveRecord({
    required String sourceId,
    required String sourceName,
    required bool folderMode,
    required String sortName,
    required bool sortAscending,
    required String lastItemId,
    required String lastItemName,
  }) async {
    if (sourceId.isEmpty || lastItemId.isEmpty) return;
    final records = await loadRecords();
    records.removeWhere((r) => r.lastItemId == lastItemId);
    records.insert(
      0,
      SwipePlayRecord(
        sourceId: sourceId,
        sourceName: sourceName,
        folderMode: folderMode,
        sortName: sortName,
        sortAscending: sortAscending,
        lastItemId: lastItemId,
        lastItemName: lastItemName,
        time: DateTime.now(),
      ),
    );
    if (records.length > _maxRecords) {
      records.removeRange(_maxRecords, records.length);
    }
    await SettingsStorage.saveString(
        _storageKey, json.encode(records.map((e) => e.toJson()).toList()));
  }
}
