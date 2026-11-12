import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../storage/local_store.dart';
import 'kugou_config.dart';

/// 酷狗登录态 / 设备标识（对应 `.local/kugou_cookie.json`）。
///
/// 说明：
/// - `dfid` 是设备指纹，**每个请求都必须带**，未登录也能用（走 60 秒试听）；
/// - `userid` + `token` 存在时视为已登录，能解锁全曲与高音质；
/// - 该文件不入库（`.gitignore` 已忽略 `.local/`），凭证只在本地流转。
@immutable
class KugouSession {
  const KugouSession({
    this.cookie = '',
    this.dfid = '',
    this.userid = '',
    this.token = '',
    this.nickname = '',
    this.baseUrl = KugouConfig.defaultBaseUrl,
    this.sourceFile,
  });

  final String cookie;
  final String dfid;
  final String userid;
  final String token;
  final String nickname;
  final String baseUrl;

  /// 登录态来源文件，未落盘时为 null。
  final String? sourceFile;

  bool get isLoggedIn =>
      userid.isNotEmpty && token.isNotEmpty && cookie.isNotEmpty;

  /// 实际下发给接口的 cookie 头：优先使用文件里的完整 cookie 串。
  ///
  /// 统一规整为 `k=v;k=v` 的紧凑格式：服务端 `cookieToJson` 只按 `;` 切分，
  /// 若留 `; ` 这种分隔会产生带前导空格的键名，导致 token/userid 取不到值，
  /// 上游随即返回 20002 / 20010（表现为「HTTP 502」）。
  String get cookieHeader {
    if (cookie.isNotEmpty) {
      final List<String> normalized = cookie
          .split(';')
          .map((String item) => item.trim())
          .where((String item) => item.isNotEmpty && item.contains('='))
          .toList();
      if (normalized.isNotEmpty) {
        return normalized.join(';');
      }
    }
    final List<String> parts = <String>[];
    if (dfid.isNotEmpty) {
      parts.add('dfid=$dfid');
    }
    if (userid.isNotEmpty) {
      parts.add('userid=$userid');
    }
    if (token.isNotEmpty) {
      parts.add('token=$token');
    }
    return parts.join(';');
  }

  KugouSession copyWith({
    String? cookie,
    String? dfid,
    String? userid,
    String? token,
    String? nickname,
    String? baseUrl,
    String? sourceFile,
  }) {
    return KugouSession(
      cookie: cookie ?? this.cookie,
      dfid: dfid ?? this.dfid,
      userid: userid ?? this.userid,
      token: token ?? this.token,
      nickname: nickname ?? this.nickname,
      baseUrl: baseUrl ?? this.baseUrl,
      sourceFile: sourceFile ?? this.sourceFile,
    );
  }

  static const KugouSession guest = KugouSession();

  /// 从本地文件恢复登录态；文件缺失或解析失败时返回 [guest]（不抛异常，
  /// 未登录仍可浏览/试听，避免拖垮启动流程）。
  static Future<KugouSession> load() async {
    for (final String path in KugouConfig.cookieFileCandidates) {
      final File file = File(path);
      try {
        if (!await file.exists()) {
          continue;
        }
        final Object? decoded = jsonDecode(await file.readAsString());
        if (decoded is! Map<String, dynamic>) {
          continue;
        }
        return _fromJson(decoded, path);
      } on Object catch (error) {
        debugPrint('读取酷狗登录态失败($path): $error');
      }
    }
    return guest.copyWith(baseUrl: KugouConfig.baseUrl);
  }

  static KugouSession _fromJson(Map<String, dynamic> json, String path) {
    String str(String key) {
      final Object? value = json[key];
      return value == null ? '' : value.toString();
    }

    final String fileBase = str('base_url');
    return KugouSession(
      cookie: str('cookie'),
      dfid: str('dfid'),
      userid: str('userid'),
      token: str('token'),
      nickname: str('nickname'),
      baseUrl: fileBase.isNotEmpty ? fileBase : KugouConfig.baseUrl,
      sourceFile: path,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'cookie': cookie,
        'dfid': dfid,
        'userid': userid,
        'token': token,
        'nickname': nickname,
        'base_url': baseUrl,
        'saved_at': DateTime.now().toIso8601String(),
      };

  /// 把当前登录态写回 `.local/kugou_cookie.json`（扫码登录成功后调用）。
  ///
  /// 目录与 [LocalStore] 保持一致，保证 dev / 打包两种情况都命中同一份文件。
  Future<void> persist() async {
    final File file = LocalStore.fileOf('kugou_cookie.json');
    try {
      final Directory dir = file.parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(toJson()),
        flush: true,
      );
    } on Object catch (error) {
      debugPrint('写入酷狗登录态失败: $error');
    }
  }

  /// 退出登录：清掉本地 cookie 文件，仅保留 dfid 继续游客可用。
  static Future<void> clearPersisted() async {
    for (final String path in KugouConfig.cookieFileCandidates) {
      final File file = File(path);
      try {
        if (await file.exists()) {
          await file.delete();
        }
      } on Object catch (error) {
        debugPrint('清除酷狗登录态失败($path): $error');
      }
    }
  }
}
