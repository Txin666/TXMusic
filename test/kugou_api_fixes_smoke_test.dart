// 该文件是真实接口联调证据脚本，需要把实际返回打印出来供人工核对。
// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:txmusic/core/network/kugou_client.dart';
import 'package:txmusic/core/network/kugou_session.dart';
import 'package:txmusic/features/lyric/data/kugou_lyric_api.dart';
import 'package:txmusic/features/playlist/data/kugou_playlist_api.dart';
import 'package:txmusic/features/playlist/domain/playlist.dart';
import 'package:txmusic/features/search/data/kugou_search_api.dart';
import 'package:txmusic/features/song/data/kugou_song_api.dart';
import 'package:txmusic/features/song/domain/song.dart';

/// 真实接口适配验证：需要本机 KuGouMusicApi 在 `localhost:3000` 运行，
/// 且 `.local/kugou_cookie.json` 存在（dfid/cookie 必须带上，否则 152）。
///
/// 运行：`flutter test test/kugou_api_fixes_smoke_test.dart`
///
/// 覆盖四处实测修复：
/// 1. 响应体 HTML 注释前缀剥离（`/search/complex`）；
/// 2. 搜索链路以 `/search` 为主、complex 失败自动降级；
/// 3. `/lyric` base64 兜底解码；4. 歌单 global_collection_id 约束与降级。
void main() {
  late KugouClient client;

  setUpAll(() async {
    final KugouSession session = await KugouSession.load();
    client = KugouClient(session: session);
  });

  tearDownAll(() => client.dispose());

  test('sanitizeBody 剥离 HTML 注释与 BOM', () {
    const String raw =
        '\uFEFF<!--KG_TAG_RES_START-->\n{"status":1,"data":{}}\n<!--KG_TAG_RES_END-->';
    final String clean = KugouClient.sanitizeBody(raw);
    expect(clean, '{"status":1,"data":{}}');
    expect(KugouClient.sanitizeBody('<!--A--><!--B-->{"a":1}'), '{"a":1}');
    expect(KugouClient.sanitizeBody('{"a":1}'), '{"a":1}');
  });

  test('/search/complex 注释前缀已剥离：解析成功但业务码为 152', () async {
    try {
      await client.getJson(
        '/search/complex',
        query: <String, dynamic>{'keywords': '晴天', 'page': 1, 'pagesize': 5},
      );
      // 若服务端某天恢复可用，走到这里也算通过。
      print('[complex] 接口恢复可用，未触发 152');
    } on KugouApiException catch (error) {
      // 关键点：报的是业务码 152，而不是"响应解析失败"。
      print('[complex] code=${error.code} message=${error.message}');
      expect(error.message, isNot(contains('响应解析失败')));
      expect(error.code, 152);
    }
  });

  test('搜索链路降级：单曲正常返回，分区缺失不报错', () async {
    final SearchBundle bundle = await KugouSearchApi(client)
        .bundle('晴天 周杰伦', pageSize: 10);
    print(
      '[search] songs=${bundle.songs.length} '
      'playlists=${bundle.playlists.length} '
      'artists=${bundle.artists.length} '
      'albums=${bundle.albums.length} '
      'partitionsAvailable=${bundle.partitionsAvailable}',
    );
    expect(bundle.songs, isNotEmpty);
    expect(bundle.songs.first.title, isNotEmpty);
    expect(bundle.songs.first.hash, isNotEmpty);
    // 分区接口可用与否都不能影响单曲结果；不可用时 partitionsAvailable
    // 为 false，搜索页据此隐藏分区并展示降级提示。
    expect(
      bundle.partitionsAvailable,
      bundle.playlists.isNotEmpty ||
          bundle.artists.isNotEmpty ||
          bundle.albums.isNotEmpty,
    );
  });

  test('/search 直接取单曲可用', () async {
    final List<Song> songs = await KugouSearchApi(client)
        .searchSongs('稻香', pageSize: 5);
    expect(songs, isNotEmpty);
    print('[searchSongs] ${songs.map((Song s) => s.title).take(3).toList()}');
  });

  test('歌词：/lyric 的 base64 content 已兜底解码为 LRC', () async {
    final List<Song> songs = await KugouSongApi(client)
        .search('晴天 周杰伦', pageSize: 5);
    final Song song = songs.first;

    final LyricDocument doc = await KugouLyricApi(client).load(song);
    print(
      '[lyric] hash=${song.hash} lines=${doc.lines.length} '
      'firstLines=${doc.lines.take(3).map((dynamic l) => l.text).toList()}',
    );
    expect(doc.lines, isNotEmpty, reason: '播放页需要逐行歌词');
    expect(doc.lines.first.text, isNotEmpty);
    expect(doc.raw, contains('['));
  });

  test('complex 抛错时自动降级为纯单曲（不把整页打成错误）', () async {
    final SearchBundle bundle = await _BrokenComplexSearchApi(client)
        .bundle('晴天 周杰伦', pageSize: 5);
    print(
      '[degrade] songs=${bundle.songs.length} '
      'partitionsAvailable=${bundle.partitionsAvailable}',
    );
    expect(bundle.songs, isNotEmpty);
    expect(bundle.playlists, isEmpty);
    expect(bundle.artists, isEmpty);
    expect(bundle.albums, isEmpty);
    expect(bundle.partitionsAvailable, isFalse);
  });

  test('decodeIfBase64 直接单测：base64 → LRC', () {
    const String lrc = '[00:01.00]第一行\n[00:03.50]第二行';
    final String encoded = base64Encode(utf8.encode(lrc));
    expect(KugouLyricApi.decodeIfBase64(encoded), lrc);
    expect(KugouLyricApi.decodeIfBase64(lrc), lrc);
    expect(KugouLyricApi.decodeIfBase64(''), '');
  });

  test('歌单链路：global_collection_id 可用，specialid 降级为空', () async {
    final KugouPlaylistApi api = KugouPlaylistApi(client);
    final List<Playlist> lists = await api.topPlaylists(pageSize: 10);
    expect(lists, isNotEmpty);

    final Iterable<Playlist> withCollection = lists.where(
      (Playlist p) => p.hasCollectionId,
    );
    print(
      '[playlist] total=${lists.length} '
      'withCollection=${withCollection.length} '
      'sampleIds=${lists.take(3).map((Playlist p) => p.id).toList()}',
    );
    expect(
      withCollection,
      isNotEmpty,
      reason: '/top/playlist 应返回 global_collection_id',
    );

    final Playlist target = withCollection.first;
    final Playlist? detail = await api.detail(target.collectionId);
    print(
      '[playlist/detail] id=${target.collectionId} '
      'title=${detail?.title} songCount=${detail?.songCount}',
    );
    expect(detail, isNotNull);
    expect(detail!.title, isNotEmpty);

    final List<Song> tracks = await api.songs(
      target.collectionId,
      pageSize: 10,
    );
    print(
      '[playlist/track/all] tracks=${tracks.length} '
      'first=${tracks.isEmpty ? null : tracks.first.title}',
    );
    expect(tracks, isNotEmpty);

    // specialid 形态：必须降级而不是抛错。
    const String specialId = '123456789';
    expect(await api.detail(specialId), isNull);
    expect(await api.songs(specialId), isEmpty);
  });
}

/// 让 `/search/complex` 必定失败，用于验证搜索降级路径。
class _BrokenComplexSearchApi extends KugouSearchApi {
  _BrokenComplexSearchApi(super.client);

  @override
  Future<SearchBundle> complex(
    String keyword, {
    int page = 1,
    int pageSize = 20,
  }) async {
    throw const KugouApiException('参数错误', path: '/search/complex', code: 152);
  }
}
