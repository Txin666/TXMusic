import '../../album/domain/album.dart';
import '../../artist/domain/artist.dart';
import '../../playlist/domain/playlist.dart';
import '../../song/data/fake_song_data.dart';
import '../../song/domain/song.dart';
import '../domain/discover_banner.dart';
import '../../album/data/fake_album_data.dart';
import '../../artist/data/fake_artist_data.dart';
import '../../playlist/data/fake_playlist_data.dart';

/// 骨架期假数据：发现/推荐页。
///
/// TODO(api): 接入 `/everyday/recommend`、`/homepage/daily`、`/top/playlist` 等接口后，
/// 改为 `discover/domain/discover_repository.dart` + `AsyncNotifierProvider`（见文档 §9.2）。
class FakeDiscoverData {
  const FakeDiscoverData._();

  static const List<DiscoverBanner> banners = <DiscoverBanner>[
    DiscoverBanner(
      id: 'b001',
      title: '每日推荐 · 11 月 8 日',
      subtitle: '根据你的口味生成 30 首新歌',
      tag: '每日更新',
      targetRoute: '/rank/r001',
    ),
    DiscoverBanner(
      id: 'b002',
      title: '独立摇滚新声计划',
      subtitle: '未名乐队 / 沉舟 / 更多新声代',
      tag: '专题',
      targetRoute: '/playlist/p005',
    ),
    DiscoverBanner(
      id: 'b003',
      title: '深夜收听榜上线',
      subtitle: '凌晨三点还在听的，都在这里',
      tag: '榜单',
      targetRoute: '/rank/r005',
    ),
  ];

  static List<Playlist> get recommendedPlaylists => FakePlaylists.all;

  static List<Album> get recommendedAlbums => FakeAlbums.all;

  static List<Artist> get recommendedArtists => FakeArtists.all;

  static List<Song> get newSongs => FakeSongs.slice(1, 6);

  static List<Song> get dailyMix => FakeSongs.slice(4, 5);
}
