import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../network/kugou_config.dart';

/// 轻量本地 JSON 存储：收藏 / 最近播放 / 搜索历史都落在 `.local/` 下，
/// 与酷狗登录态同目录（`.gitignore` 已忽略），不引入额外数据库依赖。
class LocalStore {
  const LocalStore._();

  static Directory? _cachedDir;

  /// 数据目录：已有 cookie 的目录优先（升级前后落在同一处，不会突然变游客）；
  /// 全新安装则用 `%APPDATA%\TXMusic`，保证程序装在 `C:\Program Files`
  /// 这类只读目录时也能正常写盘。
  static Directory _dir() {
    final Directory? cached = _cachedDir;
    if (cached != null) {
      return cached;
    }

    for (final String path in KugouConfig.cookieFileCandidates) {
      final File file = File(path);
      if (file.existsSync()) {
        final Directory dir = file.parent;
        _cachedDir = dir;
        return dir;
      }
    }

    final Directory data = Directory(KugouConfig.dataDirectoryPath);
    if (!data.existsSync()) {
      try {
        data.createSync(recursive: true);
      } on Object catch (error) {
        debugPrint('创建用户数据目录失败(${data.path}): $error');
      }
    }
    _cachedDir = data;
    return data;
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
