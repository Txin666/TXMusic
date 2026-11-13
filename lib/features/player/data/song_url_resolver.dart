import '../../../core/network/kugou_client.dart';
import '../../song/domain/song.dart';

/// 解析后的可播放音源。
class ResolvedAudio {
  const ResolvedAudio({
    required this.url,
    required this.backups,
    required this.duration,
  });

  final Uri url;
  final List<Uri> backups;

  /// 服务端返回的 `timeLength`（秒），与歌曲元信息可能略有差异，以它为准。
  final Duration duration;

  bool get isValid => url.toString().isNotEmpty;
}

/// `/song/url` 音源解析器。
///
/// 关键参数（联调记录 §2）：
/// - `hash`：歌曲 FileHash；
/// - `album_id`：专辑 ID，缺失时部分曲目解析失败；
/// - `free_part=1`：不带会直接 errcode 20028；
/// - `quality`：128 / 320 / flac，未登录会被强制降级。
class SongUrlResolver {
  SongUrlResolver(this._client);

  final KugouClient _client;

  Future<ResolvedAudio> resolve(Song song, {String quality = '128'}) async {
    if (!song.canResolve) {
      throw const KugouApiException('该歌曲缺少 hash，无法解析音源');
    }
    final Map<String, dynamic> json = await _client.getJson(
      '/song/url',
      query: <String, dynamic>{
        'hash': song.hash,
        if (song.albumId.isNotEmpty) 'album_id': song.albumId,
        'free_part': '1',
        'quality': quality,
      },
    );

    Map<String, dynamic> source = json;
    List<Uri> merged = _collectUris(source);

    // 付费曲兜底：`/song/url` 拿不到直链时会带回 auth 凭证，
    // 此时用 `/song/url/auth` 换一次正式音源（概念版会员态可成功）。
    if (merged.isEmpty) {
      final String auth = '${source['auth'] ?? ''}'.trim();
      if (auth.isNotEmpty) {
        source = await _client.getJson(
          '/song/url/auth',
          query: <String, dynamic>{
            'hash': song.hash,
            if (song.albumId.isNotEmpty) 'album_id': song.albumId,
            'auth': auth,
            'quality': quality,
          },
        );
        merged = _collectUris(source);
      }
    }

    if (merged.isEmpty) {
      throw const KugouApiException('该歌曲无可用音源（可能为付费曲）');
    }

    final int seconds = _int(source['timeLength']);
    return ResolvedAudio(
      url: merged.first,
      backups: merged.skip(1).toList(growable: false),
      duration: seconds > 0 ? Duration(seconds: seconds) : song.duration,
    );
  }

  static List<Uri> _collectUris(Map<String, dynamic> json) {
    return <Uri>[..._uriList(json['url']), ..._uriList(json['backupUrl'])];
  }

  static List<Uri> _uriList(Object? raw) {
    if (raw is! List) {
      return const <Uri>[];
    }
    return raw
        .whereType<String>()
        .where((String item) => item.startsWith('http'))
        .map(Uri.parse)
        .toList(growable: false);
  }

  static int _int(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse('${value ?? ''}') ?? 0;
  }
}
