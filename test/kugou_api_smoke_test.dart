import 'package:flutter_test/flutter_test.dart';
import 'package:txmusic/core/network/kugou_client.dart';
import 'package:txmusic/core/network/kugou_session.dart';
import 'package:txmusic/features/player/data/song_url_resolver.dart';
import 'package:txmusic/features/song/data/kugou_song_api.dart';
import 'package:txmusic/features/song/domain/song.dart';

/// 真实接口冒烟测试：需要本机 KuGouMusicApi 在 `localhost:3000` 运行，
/// 且 `.local/kugou_cookie.json` 里是**已登录**的凭证——音源接口对游客态
/// 一律回 `errcode 20028`，未登录跑 `/song/url` 这条会失败。
///
/// 运行：`flutter test test/kugou_api_smoke_test.dart`
void main() {
  late KugouClient client;

  setUpAll(() async {
    final KugouSession session = await KugouSession.load();
    client = KugouClient(session: session);
  });

  tearDownAll(() => client.dispose());

  test('dfid/登录态可从 .local 恢复', () async {
    final KugouSession session = await KugouSession.load();
    expect(
      session.dfid,
      isNotEmpty,
      reason: '缺少 dfid，检查 .local/kugou_cookie.json',
    );
    expect(session.cookieHeader, contains('dfid='));
  });

  test('/search/song 返回可映射的歌曲', () async {
    final KugouSongApi api = KugouSongApi(client);
    final List<Song> songs = await api.search('晴天 周杰伦', pageSize: 5);
    expect(songs, isNotEmpty);
    final Song first = songs.first;
    expect(first.hash, isNotEmpty);
    expect(first.title, isNotEmpty);
    expect(first.duration.inSeconds, greaterThan(0));
  });

  test('/song/url 解析出可播放 mp3 地址', () async {
    final KugouSongApi api = KugouSongApi(client);
    final List<Song> songs = await api.search('晴天 周杰伦', pageSize: 5);
    final Song song = songs.firstWhere(
      (Song item) => item.hash.isNotEmpty && item.albumId.isNotEmpty,
      orElse: () => songs.first,
    );

    final ResolvedAudio audio = await SongUrlResolver(client).resolve(song);
    expect(audio.isValid, isTrue);
    expect(audio.url.toString(), contains('http'));
    expect(audio.duration.inSeconds, greaterThan(0));
  });
}
