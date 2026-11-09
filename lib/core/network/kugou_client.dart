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
/// 统一处理三件容易踩坑的事（见 docs/API联调记录.md）：
/// 1. 每个请求都带 `dfid` cookie，漏带会返回 error_code 152；
/// 2. 追加毫秒时间戳，绕开服务端 2 分钟结果缓存；
/// 3. 把 `status != 1` 或带 `errcode` 的响应统一收敛成 [KugouApiException]。
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
  }) async {
    final Uri uri = buildUri(path, query);
    final Map<String, String> headers = <String, String>{
      'Accept': 'application/json',
    };
    final String cookie = session.cookieHeader;
    if (cookie.isNotEmpty) {
      headers['Cookie'] = cookie;
    }

    http.Response response;
    try {
      response = await _http
          .get(uri, headers: headers)
          .timeout(KugouConfig.requestTimeout);
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

    if (response.statusCode != 200) {
      throw KugouApiException(
        'HTTP ${response.statusCode}',
        path: path,
        code: response.statusCode,
      );
    }

    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on Object catch (error) {
      throw KugouApiException('响应解析失败：$error', path: path);
    }

    if (decoded is! Map<String, dynamic>) {
      throw KugouApiException('响应结构异常（非 JSON 对象）', path: path);
    }

    _throwIfFailed(decoded, path);
    if (requireData && decoded['data'] == null) {
      throw KugouApiException('响应缺少 data 字段', path: path);
    }
    return decoded;
  }

  void _throwIfFailed(Map<String, dynamic> json, String path) {
    final Object? errcode = json['errcode'] ?? json['error_code'];
    final bool hasErr = errcode != null && errcode.toString() != '0';
    final bool badStatus = json.containsKey('status') &&
        json['status'] != null &&
        json['status'].toString() != '1';

    if (!hasErr && !badStatus) {
      return;
    }

    final int? code = int.tryParse('${errcode ?? json['status']}');
    final String raw = '${json['error_msg'] ?? json['msg'] ?? ''}';
    throw KugouApiException(
      _friendlyMessage(code, raw),
      path: path,
      code: code,
    );
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
