import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../network/kugou_config.dart';

/// 轻量本地 JSON 存储：收藏 / 最近播放 / 搜索历史都落在 `.local/` 下，
/// 与酷狗登录态同目录（`.gitignore` 已忽略），不引入额外数据库依赖。
class LocalStore {
  const LocalStore._();

  static Directory? _cachedDir;

  /// `.local/` 目录：优先跟随已有 login cookie 的目录，保证 dev / 打包两种情况
  /// 都能命中同一份用户数据。
  static Directory _dir() {
    final Directory? cached = _cachedDir;
    if (cached != null) {
      return cached;
    }

    final List<String> cookiePaths = KugouConfig.cookieFileCandidates;
    for (final String path in cookiePaths) {
      final File file = File(path);
      if (file.existsSync()) {
        final Directory dir = file.parent;
        _cachedDir = dir;
        return dir;
      }
    }
    for (final String path in cookiePaths) {
      final Directory dir = File(path).parent;
      if (dir.existsSync()) {
        _cachedDir = dir;
        return dir;
      }
    }

    final Directory fallback = Directory(
      '${Directory.current.path}${Platform.pathSeparator}.local',
    );
    if (!fallback.existsSync()) {
      fallback.createSync(recursive: true);
    }
    _cachedDir = fallback;
    return fallback;
  }

  static File fileOf(String name) =>
      File('${_dir().path}${Platform.pathSeparator}$name');

  /// 读取 JSON 对象；文件不存在或损坏时返回空 Map（调用方按空态处理）。
  static Future<Map<String, dynamic>> readJson(String name) async {
    final File file = fileOf(name);
    try {
      if (!await file.exists()) {
        return <String, dynamic>{};
      }
      final Object? decoded = jsonDecode(await file.readAsString());
      final Map<String, dynamic>? map = decoded is Map<String, dynamic>
          ? decoded
          : (decoded is Map
                ? decoded.map<String, dynamic>(
                    (Object? key, Object? value) =>
                        MapEntry<String, dynamic>('$key', value),
                  )
                : null);
      return map ?? <String, dynamic>{};
    } on Object catch (error) {
      debugPrint('读取本地数据失败($name): $error');
      return <String, dynamic>{};
    }
  }

  static Future<void> writeJson(String name, Map<String, dynamic> data) async {
    final File file = fileOf(name);
    try {
      final Directory dir = file.parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      await file.writeAsString(jsonEncode(data), flush: true);
    } on Object catch (error) {
      debugPrint('写入本地数据失败($name): $error');
    }
  }

  static Future<void> delete(String name) async {
    try {
      final File file = fileOf(name);
      if (await file.exists()) {
        await file.delete();
      }
    } on Object catch (error) {
      debugPrint('删除本地数据失败($name): $error');
    }
  }
}
