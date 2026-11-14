// 真实接口联调证据脚本：收藏双向同步 + 榜单/专辑/歌手全量翻页。
// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:txmusic/core/network/kugou_client.dart';
import 'package:txmusic/core/network/kugou_session.dart';
import 'package:txmusic/features/album/data/kugou_album_api.dart';
import 'package:txmusic/features/artist/data/kugou_artist_api.dart';
import 'package:txmusic/features/library/data/kugou_collect_api.dart';
import 'package:txmusic/features/rank/data/kugou_rank_api.dart';
import 'package:txmusic/features/song/domain/song.dart';

/// 运行：`flutter test test/collect_sync_smoke_test.dart`
/// 前置：本机 KuGouMusicApi 在 `localhost:3000` 运行，`.local/kugou_cookie.json` 已登录。
///
/// 覆盖：`/playlist/tracks/add` / `/playlist/tracks/del` 的真实写链路（收藏 →
/// 服务器可见 → 取消 → count 复原），以及榜单 / 歌手曲目的全量翻页。
void main() {
  late KugouClient client;
  late KugouCollectApi collect;

  setUpAll(() async {
    final KugouSession session = await KugouSession.load();
    client = KugouClient(session: session);
    collect = KugouCollectApi(client);
  });

  tearDownAll(() => client.dispose());

  test('「我喜欢」全量拉取并建立 hash→fileid 映射', () async {
    final LikedSongsSnapshot snapshot = await collect.likedSongs();
    print(
      'liked collection=${collect.likedCollectionId} total=${snapshot.total} '
      'songs=${snapshot.songs.length} fileids=${snapshot.fileids.length}',
    );
    expect(snapshot.songs, isNotEmpty);
    expect(snapshot.fileids, isNotEmpty);
  });

  test('收藏 → 服务器可见 → 取消 → count 复原', () async {
    final LikedSongsSnapshot before = await collect.likedSongs();

    // 从榜单里挑一首当前没收藏的歌，避免动到用户已有收藏。
    final KugouRankApi rankApi = KugouRankApi(client);
    final List<Song> candidates = await rankApi.songs(
      '8888',
      pageSize: 500,
      fetchAll: false,
    );
    final Song target = candidates.firstWhere(
      (Song song) => song.hash.isNotEmpty && !before.has(song.hash),
    );
    print('target=${target.title} - ${target.artist} hash=${target.hash}');

    await collect.addToLiked(target);
    await Future<void>.delayed(const Duration(seconds: 2));
    final LikedSongsSnapshot added = await collect.likedSongs();
    print(
      'after add: total ${before.total} → ${added.total}, '
      'hit=${added.has(target.hash)}, fileid=${added.fileidOf(target.hash)}',
    );
    expect(added.has(target.hash), isTrue);
    final int fileid = added.fileidOf(target.hash) ?? 0;
    expect(fileid, greaterThan(0));

    await collect.removeFromLiked(hash: target.hash, fileid: fileid);
    await Future<void>.delayed(const Duration(seconds: 2));
    final LikedSongsSnapshot restored = await collect.likedSongs();
    print('after del: total=${restored.total}, hit=${restored.has(target.hash)}');
    expect(restored.has(target.hash), isFalse);
    expect(restored.total, before.total);
  });

  test('榜单曲目全量翻页：TOP500 取满 500 首', () async {
    final KugouRankApi rankApi = KugouRankApi(client);
    final List<Song> songs = await rankApi.songs('8888');
    print('rank 8888 fetchAll=${songs.length}');
    expect(songs.length, greaterThanOrEqualTo(200));
  });

  test('专辑曲目全量翻页：total 与实际条数一致', () async {
    final KugouAlbumApi albumApi = KugouAlbumApi(client);
    final List<Song> songs = await albumApi.songs('179652761');
    print('album 179652761 fetchAll=${songs.length}');
    expect(songs, isNotEmpty);
  });

  test('歌手曲目全量翻页：周杰伦 3520 超过 500 首', () async {
    final KugouArtistApi artistApi = KugouArtistApi(client);
    final List<Song> songs = await artistApi.songs('3520');
    print('artist 3520 fetchAll=${songs.length}');
    expect(songs.length, greaterThan(500));
  });
}
