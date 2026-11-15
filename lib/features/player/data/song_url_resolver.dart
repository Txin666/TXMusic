import '../../../core/network/kugou_client.dart';
import '../../song/domain/song.dart';
import 'guest_song_url_api.dart';

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
/// - `free_part=1`：必带；但未登录时上游对任何参数组合都回 20028（实测）；
/// - `quality`：128 / 320 / flac，未登录会被强制降级。
class SongUrlResolver {
  SongUrlResolver(this._client, {GuestSongUrlApi? guest})
    : _guest = guest ?? GuestSongUrlApi();

  final KugouClient _client;
  final GuestSongUrlApi _guest;

  Future<ResolvedAudio> resolve(Song song, {String quality = '128'}) async {
    if (!song.canResolve) {
      throw const KugouApiException('该歌曲缺少 hash，无法解析音源');
    }
    // 游客态：上游 `/song/url`、`/song/url/new` 一律回 20028「本次请求需要验证」，
    // 补 free_part / album_audio_id 也解不开。但 m.kugou.com 的旧播放信息接口
    // 对游客仍下发 128k 直链，所以未登录时改走这条兜底链路。
    if (!_client.session.isLoggedIn) {
      return _resolveAsGuest(song);
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

  /// 游客态取源：m.kugou.com 旧接口只给 128k，会员/版权曲会返回空 url。
  Future<ResolvedAudio> _resolveAsGuest(Song song) async {
    final GuestSong guest = await _guest.fetch(song.hash);
    if (!guest.hasUrl) {
      if (guest.vipPrivilege != 0 || guest.privilege >= 10) {
        throw const KugouApiException(
          '这首歌未登录时只提供试听/无版权，登录酷狗账号后再试',
        );
      }
      throw const KugouApiException('这首歌暂时取不到可用音源，换一首或登录后再试');
    }
    return ResolvedAudio(
      url: Uri.parse(guest.url),
      backups: const <Uri>[],
      duration: guest.duration.inSeconds > 0 ? guest.duration : song.duration,
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
