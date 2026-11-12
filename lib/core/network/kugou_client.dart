import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'kugou_config.dart';
import 'kugou_session.dart';

/// 接口异常：区分网络层失败与业务层错误码，UI 只需展示 [message]。
class KugouApiException implements Exception {
  const KugouApiException(this.message, {this.path, this.code});

  final String message;
  final String? path;
  final int? code;

  @override
  String toString() =>
      'KugouApiException(${path ?? '-'} code=$code): $message';
}

/// KuGouMusicApi 访问客户端。
///
/// 统一处理四件容易踩坑的事（见 docs/API联调记录.md）：
/// 1. 每个请求都带 `dfid` cookie，漏带会返回 error_code 152；
/// 2. 追加毫秒时间戳，绕开服务端 2 分钟结果缓存；
/// 3. 部分接口（实测 `/search/complex`）响应体前后会拼一段 HTML 注释
///    （`<!--KG_TAG_RES_START-->` / `<!--KG_TAG_RES_END-->`），先剥离再解析；
/// 4. 把失败响应统一收敛成 [KugouApiException]，成功码兼容 `1` 与 `200`
///    两套（`/lyric` 返回 `status=200`、`errcode=200`）。
class KugouClient {
  KugouClient({
    KugouSession? session,
    http.Client? httpClient,
    String? baseUrl,
  })  : session = session ?? KugouSession.guest,
        _http = httpClient ?? http.Client(),
        _baseUrl = baseUrl ?? (session?.baseUrl ?? KugouConfig.baseUrl);

  final http.Client _http;
  final String _baseUrl;
  /// 当前登录态（可在运行期替换，例如扫码登录成功后）。
  KugouSession session;

  String get baseUrl => _baseUrl;

  Uri buildUri(String path, [Map<String, dynamic>? query]) {
    final Map<String, String> params = <String, String>{};
    query?.forEach((String key, dynamic value) {
      if (value == null) {
        return;
      }
      params[key] = value.toString();
    });
    params['timestamp'] = KugouConfig.cacheBuster;
    return Uri.parse('$_baseUrl$path').replace(queryParameters: params);
  }

  /// GET 请求并返回 `data` 层之前的完整 JSON（部分接口数据挂在顶层）。
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, dynamic>? query,
    bool requireData = false,
    bool lenient = false,
  }) async {
    final Uri uri = buildUri(path, query);
    final http.Response response = await _send(
      () => _http.get(uri, headers: _headers()),
      path: path,
    );
    return _decode(
      response,
      path: path,
      requireData: requireData,
      lenient: lenient,
    );
  }

  /// POST 请求（JSON body）。
  ///
  /// 概念版青年任务（每日领 VIP / 听歌上报）都是 POST，故单独提供；
  /// 复用与 GET 完全一致的 cookie、时间戳与错误码收敛逻辑。
  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    bool requireData = false,
    bool lenient = false,
  }) async {
    final Uri uri = buildUri(path, query);
    final Map<String, String> headers = _headers()
      ..['Content-Type'] = 'application/json; charset=utf-8';
    final http.Response response = await _send(
      () => _http.post(
        uri,
        headers: headers,
        body: jsonEncode(body ?? const <String, dynamic>{}),
      ),
      path: path,
    );
    return _decode(
      response,
      path: path,
      requireData: requireData,
      lenient: lenient,
    );
  }

  /// 公共请求头：`dfid` / `userid` / `token` 全在 cookie 里，漏带会返回 152。
  Map<String, String> _headers() {
    final Map<String, String> headers = <String, String>{
      'Accept': 'application/json',
    };
    final String cookie = session.cookieHeader;
    if (cookie.isNotEmpty) {
      headers['Cookie'] = cookie;
    }
    return headers;
  }

  /// 发出请求并把网络层异常收敛成 [KugouApiException]。
  Future<http.Response> _send(
    Future<http.Response> Function() run, {
    required String path,
  }) async {
    try {
      return await run().timeout(KugouConfig.requestTimeout);
    } on TimeoutException {
      throw KugouApiException('请求超时，检查 KuGouMusicApi 服务是否在运行', path: path);
    } on SocketException catch (error) {
      throw KugouApiException(
        '无法连接本地服务 $_baseUrl（${error.osError?.message ?? '连接被拒绝'}）',
        path: path,
      );
    } on Object catch (error) {
      throw KugouApiException('网络异常：$error', path: path);
    }
  }

  /// 状态码 / 响应体 / 业务错误码的统一解析。
  Map<String, dynamic> _decode(
    http.Response response, {
    required String path,
    required bool requireData,
    required bool lenient,
  }) {
    final String body = sanitizeBody(
      utf8.decode(response.bodyBytes, allowMalformed: true),
    );

    if (response.statusCode != 200) {
      // KuGouMusicApi 把上游业务失败统一折叠成 HTTP 502，
      // 真实错误码只留在 body 里（如 `{"status":0,"error_code":131001}` 已领）。
      // 因此先解析 body，能解析成对象就按业务码处理，解析不出来才报 HTTP 错误。
      final Object? failure = body.isEmpty ? null : _tryDecodeJson(body);
      if (failure is Map<String, dynamic>) {
        if (!lenient) {
          _throwIfFailed(failure, path);
        }
        if (requireData && failure['data'] == null) {
          throw KugouApiException('响应缺少 data 字段', path: path);
        }
        if (lenient) {
          return failure;
        }
      }
      throw KugouApiException(
        'HTTP ${response.statusCode}',
        path: path,
        code: response.statusCode,
      );
    }

    if (body.isEmpty) {
      throw KugouApiException('响应体为空', path: path);
    }

    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on Object catch (error) {
      final String head = body.length > 60 ? '${body.substring(0, 60)}…' : body;
      throw KugouApiException('响应解析失败：$error（响应开头：$head）', path: path);
    }

    if (decoded is! Map<String, dynamic>) {
      throw KugouApiException('响应结构异常（非 JSON 对象）', path: path);
    }

    if (!lenient) {
      _throwIfFailed(decoded, path);
    }
    if (requireData && decoded['data'] == null) {
      throw KugouApiException('响应缺少 data 字段', path: path);
    }
    return decoded;
  }

  /// 响应体清洗：部分接口会在 JSON 前后拼 HTML 注释标记
  /// （实测 `/search/complex` 返回 `<!--KG_TAG_RES_START-->{...}<!--KG_TAG_RES_END-->`），
  /// 直接 `jsonDecode` 会抛 FormatException 并让整页报错，这里先剥离注释与 BOM。
  static String sanitizeBody(String body) {
    String text = body.replaceFirst('\uFEFF', '').trim();
    // 头部可能连续出现多段注释。
    while (text.startsWith('<!--')) {
      final int end = text.indexOf('-->');
      if (end < 0) {
        break;
      }
      text = text.substring(end + 3).trimLeft();
    }
    // 尾部同理。
    while (text.endsWith('-->')) {
      final int start = text.lastIndexOf('<!--');
      if (start < 0) {
        break;
      }
      text = text.substring(0, start).trimRight();
    }
    // 兜底：正文内部残留的注释也去掉（只删注释，不改动数据）。
    if (text.contains('<!--')) {
      text = text.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '').trim();
    }
    return text;
  }

  /// 宽松解析：失败返回 null，交给调用方决定报什么错。
  static Object? _tryDecodeJson(String body) {
    try {
      return jsonDecode(body);
    } on Object {
      return null;
    }
  }

  void _throwIfFailed(Map<String, dynamic> json, String path) {
    final Object? errcode = json['errcode'] ?? json['error_code'];
    final Object? status = json['status'];
    final bool hasErr = !_isOkErrorCode(errcode);
    final bool badStatus = !_isOkStatus(status);

    if (!hasErr && !badStatus) {
      return;
    }

    final Object? rawCode = hasErr ? errcode : status;
    final int? code = int.tryParse('$rawCode');
    final String raw = '${json['error_msg'] ?? json['errmsg'] ?? json['msg'] ?? ''}';
    throw KugouApiException(
      _friendlyMessage(code, raw),
      path: path,
      code: code,
    );
  }

  /// 成功码：`errcode` / `error_code` 用 `0`，部分接口用 `200`（`/lyric`）。
  static bool _isOkErrorCode(Object? value) {
    if (value == null) {
      return true;
    }
    final String text = value.toString().trim();
    return text.isEmpty || text == '0' || text == '200';
  }

  /// 成功码：`status` 用 `1`，`/lyric`、`/search/lyric` 用 `200`。
  static bool _isOkStatus(Object? value) {
    if (value == null) {
      return true;
    }
    final String text = value.toString().trim();
    return text.isEmpty || text == '1' || text == '200';
  }

  /// 常见错误码翻译成人话，未知码保留原始信息方便排查。
  String _friendlyMessage(int? code, String raw) {
    switch (code) {
      case 152:
        return '缺少 dfid 设备标识，请先执行 /register/dev 初始化';
      case 20028:
        return '需要 free_part=1 参数，或该曲目无版权/需付费';
      case 20010:
        return '歌曲 hash 无效';
      case 20002:
        return '参数无效或登录态与平台不匹配（概念版需重登）';
      case 131001:
        return '今日 VIP 已领取，明天再来';
      case 304003:
        return '领取日期非法（上游要求次日日期）';
      case 502:
        return '版权受限或无可用音源（付费曲）';
      default:
        return raw.isEmpty ? '接口返回失败（code=$code）' : raw;
    }
  }

  /// 未登录时初始化设备标识，返回服务端下发的 dfid。
  Future<String> registerDev() async {
    final Map<String, dynamic> json = await getJson(
      '/register/dev',
      requireData: true,
    );
    final Object? data = json['data'];
    if (data is Map<String, dynamic>) {
      final Object? dfid = data['dfid'] ?? data['DFID'] ?? data['deviceid'];
      if (dfid != null && dfid.toString().isNotEmpty) {
        session = session.copyWith(dfid: dfid.toString());
        return dfid.toString();
      }
    }
    throw const KugouApiException('/register/dev 未返回 dfid');
  }

  void dispose() => _http.close();

  @visibleForTesting
  void debugOverrideSession(KugouSession value) => session = value;
}
