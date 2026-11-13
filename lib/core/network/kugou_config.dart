import 'dart:io';

/// KuGouMusicApi 本地服务配置（文档 §5 数据层 / API 联调记录）。
///
/// 约定：
/// - 服务地址默认 `http://localhost:3000`，可用环境变量 `KUGOU_API_BASE_URL` 覆盖；
/// - 登录态与 dfid 持久化在工程根目录 `.local/kugou_cookie.json`（已 gitignore），
///   也可用环境变量 `KUGOU_COOKIE_FILE` 指向其它路径；
/// - 所有请求必须带 `dfid` cookie，否则接口返回 error_code 152。
class KugouConfig {
  const KugouConfig._();

  static const String defaultBaseUrl = 'http://localhost:3000';

  /// 单次 HTTP 请求超时：/song/url 解析较慢，给足余量。
  static const Duration requestTimeout = Duration(seconds: 20);

  /// 服务端有 2 分钟结果缓存，统一追加毫秒时间戳规避（联调记录 §2）。
  static String get cacheBuster =>
      DateTime.now().millisecondsSinceEpoch.toString();

  static String get baseUrl {
    final String? fromEnv = Platform.environment['KUGOU_API_BASE_URL'];
    if (fromEnv != null && fromEnv.trim().isNotEmpty) {
      return fromEnv.trim().replaceAll(RegExp(r'/+$'), '');
    }
    return defaultBaseUrl;
  }

  /// cookie 文件候选路径：环境变量 → 当前目录 → 逐级向上（兼容 flutter run
  /// 从工程根目录启动、以及从 build 目录启动两种情况）。
  static List<String> get cookieFileCandidates {
    final List<String> candidates = <String>[];
    final String? fromEnv = Platform.environment['KUGOU_COOKIE_FILE'];
    if (fromEnv != null && fromEnv.trim().isNotEmpty) {
      candidates.add(fromEnv.trim());
    }
    Directory dir = Directory.current;
    // build\windows\x64\runner\Debug 距工程根有 5 层，留足余量。
    for (int depth = 0; depth < 9; depth++) {
      candidates.add(
        '${dir.path}${Platform.pathSeparator}.local'
        '${Platform.pathSeparator}kugou_cookie.json',
      );
      final Directory parent = dir.parent;
      if (parent.path == dir.path) {
        break;
      }
      dir = parent;
    }
    return candidates;
  }

  /// 写入 cookie 的首选路径（候选列表中第一个可写位置）。
  static String get primaryCookieFile => cookieFileCandidates.last;
}
