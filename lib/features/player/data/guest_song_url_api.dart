import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/network/kugou_client.dart';

/// 游客态音源信息。
class GuestSong {
  const GuestSong({
    required this.url,
    required this.bitRate,
    required this.duration,
    required this.privilege,
    required this.vipPrivilege,
    required this.fileName,
  });

  final String url;
  final int bitRate;
  final Duration duration;
  final int privilege;
  final int vipPrivilege;
  final String fileName;

  bool get hasUrl => url.startsWith('http');
}

/// 未登录（游客）取源兜底链路。
///
/// 上游 KuGouMusicApi 的 `/song/url`、`/song/url/new` 对游客一律回
/// `errcode 20028`（本次请求需要验证），补 `free_part` / `album_audio_id`
/// 都解不开，属服务端策略收紧。
/// 但 `m.kugou.com` 的旧播放信息接口仍然对游客下发 128k 直链，
/// 所以未登录时改走这条链路，保住「不登录也能听」的体验。
class GuestSongUrlApi {
  GuestSongUrlApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String _endpoint = 'https://m.kugou.com/app/i/getSongInfo.php';
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  Future<GuestSong> fetch(String hash) async {
    if (hash.isEmpty) {
      throw const KugouApiException('该歌曲缺少 hash，无法解析音源');
    }
    final Uri uri = Uri.parse(_endpoint).replace(
      queryParameters: <String, String>{'cmd': 'playInfo', 'hash': hash},
    );
    final http.Response response;
    try {
      response = await _client
          .get(uri, headers: <String, String>{
            'User-Agent': _userAgent,
            'Referer': 'https://m.kugou.com/',
            'Accept': 'application/json, text/plain, */*',
          })
          .timeout(const Duration(seconds: 15));
    } on Object catch (error) {
      throw KugouApiException('游客态取源请求失败：$error', path: '/app/i/getSongInfo.php');
    }
    if (response.statusCode != 200) {
      throw KugouApiException(
        '游客态取源失败（HTTP ${response.statusCode}）',
        path: '/app/i/getSongInfo.php',
      );
    }
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } on Object {
      throw const KugouApiException(
        '游客态取源返回内容无法解析',
        path: '/app/i/getSongInfo.php',
      );
    }
    return GuestSong(
      url: '${json['url'] ?? ''}',
      bitRate: _int(json['bitRate']),
      duration: Duration(seconds: _int(json['timeLength'])),
      privilege: _int(json['privilege']),
      vipPrivilege: _int(json['128privilege']),
      fileName: '${json['fileName'] ?? ''}',
    );
  }

  static int _int(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse('${value ?? ''}') ?? 0;
  }
}
