import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// [QBSenHook] v8.0: 图片磁盘缓存（上限 2GB，超出后按最久未用清理）。
/// 缓存 key 为图片 URL 的 base64url 文件名，写入时记录访问时间（文件修改时间）。
class ImageDiskCache {
  static const int maxCacheBytes = 2 * 1024 * 1024 * 1024; // 2GB

  static Directory? _cacheDir;
  static bool _checkedOnce = false;

  static Future<Directory> _dir() async {
    if (_cacheDir != null) return _cacheDir!;
    final base = await getApplicationSupportDirectory();
    final dir = Directory(
        '${base.path}${Platform.pathSeparator}image_cache');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cacheDir = dir;
    return dir;
  }

  static String _fileKey(String url) {
    // base64url 编码做文件名，避免 URL 中的特殊字符导致文件名非法
    final encoded = base64Url.encode(utf8.encode(url));
    return encoded.length > 180 ? encoded.substring(0, 180) : encoded;
  }

  /// 命中缓存则返回文件，否则 null。
  static Future<File?> getFile(String url) async {
    try {
      final dir = await _dir();
      final f = File('${dir.path}${Platform.pathSeparator}${_fileKey(url)}.img');
      if (await f.exists()) {
        try {
          // 刷新访问时间（作为 LRU 依据）
          final now = DateTime.now();
          await f.setLastModified(now);
        } catch (_) {}
        return f;
      }
    } catch (_) {}
    return null;
  }

  /// 写入缓存（不阻塞调用方：由调用方 unawaited）。
  static Future<void> put(String url, List<int> bytes) async {
    try {
      final dir = await _dir();
      final f = File('${dir.path}${Platform.pathSeparator}${_fileKey(url)}.img');
      await f.writeAsBytes(bytes, flush: false);
      await _enforceLimit();
    } catch (_) {}
  }

  /// 超出 2GB 时按修改时间从旧到新删除，直到低于上限。
  static Future<void> _enforceLimit() async {
    try {
      final dir = await _dir();
      final files = dir.listSync(followLinks: false).whereType<File>().toList();
      var total = 0;
      for (final f in files) {
        try {
          total += await f.length();
        } catch (_) {}
      }
      if (total <= maxCacheBytes) return;
      files.sort((a, b) {
        try {
          return a.lastModifiedSync().compareTo(b.lastModifiedSync());
        } catch (_) {
          return 0;
        }
      });
      for (final f in files) {
        if (total <= maxCacheBytes) break;
        try {
          final len = await f.length();
          await f.delete();
          total -= len;
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// 当前缓存占用字节数。
  static Future<int> sizeBytes() async {
    try {
      final dir = await _dir();
      if (!await dir.exists()) return 0;
      var total = 0;
      for (final f in dir.listSync(followLinks: false).whereType<File>()) {
        try {
          total += await f.length();
        } catch (_) {}
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// 一键清空缓存。
  static Future<void> clear() async {
    try {
      final dir = await _dir();
      if (await dir.exists()) {
        for (final f in dir.listSync(followLinks: false).whereType<File>()) {
          try {
            await f.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}
