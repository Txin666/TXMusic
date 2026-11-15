import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'kugou_config.dart';
import 'kugou_device_identity.dart';

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
    this.guid = '',
    this.sourceFile,
  });

  final String cookie;
  final String dfid;
  final String userid;
  final String token;
  final String nickname;
  final String baseUrl;

  /// 设备 GUID（32 位十六进制）。播放上报要靠它（`KUGOU_API_GUID`），
  /// 缺了会被服务端直接判 400，听歌时长自然不累加。
  final String guid;

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
    final List<String> parts = <String>[];
    if (cookie.isNotEmpty) {
      parts.addAll(
        cookie
            .split(';')
            .map((String item) => item.trim())
            .where((String item) => item.isNotEmpty && item.contains('=')),
      );
    }
    if (parts.isEmpty) {
      if (dfid.isNotEmpty) {
        parts.add('dfid=$dfid');
      }
      if (userid.isNotEmpty) {
        parts.add('userid=$userid');
      }
      if (token.isNotEmpty) {
        parts.add('token=$token');
      }
    }
    // 设备标识兜底：本地服务的注入中间件在未配置 KUGOU_API_GUID 环境变量时
    // 下发的是空值，等于没补，这里由客户端自己补齐，保证播放上报能过校验。
    if (guid.isNotEmpty &&
        !parts.any((String item) => item.startsWith('KUGOU_API_GUID='))) {
      parts.add('KUGOU_API_GUID=${guid.replaceAll('-', '')}');
      final String mid = KugouDeviceIdentity.midOf(guid);
      if (mid.isNotEmpty &&
          !parts.any((String item) => item.startsWith('KUGOU_API_MID='))) {
        parts.add('KUGOU_API_MID=$mid');
      }
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
    String? guid,
    String? sourceFile,
  }) {
    return KugouSession(
      cookie: cookie ?? this.cookie,
      dfid: dfid ?? this.dfid,
      userid: userid ?? this.userid,
      token: token ?? this.token,
      nickname: nickname ?? this.nickname,
      baseUrl: baseUrl ?? this.baseUrl,
      guid: guid ?? this.guid,
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
        final KugouSession session = _fromJson(decoded, path);
        if (session.guid.isEmpty) {
          // 老文件没有设备标识：补一个并写回，避免每次启动都换指纹。
          final KugouSession fixed = session.copyWith(
            guid: KugouDeviceIdentity.generateGuid(),
          );
          await fixed.persist();
          return fixed;
        }
        return session;
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

    // 服务端口由内嵌服务在启动时动态分配，文件里存的 base_url 可能已过期，
    // 一律以当前运行地址为准。
    return KugouSession(
      cookie: str('cookie'),
      dfid: str('dfid'),
      userid: str('userid'),
      token: str('token'),
      nickname: str('nickname'),
      baseUrl: KugouConfig.baseUrl,
      guid: str('guid'),
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
    'guid': guid,
    'saved_at': DateTime.now().toIso8601String(),
  };

  /// 把当前登录态写回用户数据目录（扫码登录成功后调用）。
  ///
  /// 目标位置由 [KugouConfig.primaryCookieFile] 决定：默认写
  /// `%APPDATA%\TXMusic\kugou_cookie.json`，程序装在只读目录时也能落盘。
  Future<void> persist() async {
    final File file = File(KugouConfig.primaryCookieFile);
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
