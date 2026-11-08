import '../domain/album.dart';

/// 骨架期假数据：专辑。
///
/// TODO(api): 接入 `/album/detail`、`/album/songs` 后替换为 AlbumRepository。
class FakeAlbums {
  const FakeAlbums._();

  static const List<Album> all = <Album>[
    Album(
      id: 'a001',
      title: '城市夜航',
      artist: '林彻',
      releaseDate: '2026-03-18',
      songIds: <String>['s001', 's006'],
      playCount: 862000,
    ),
    Album(
      id: 'a002',
      title: '晚风集',
      artist: '苏白',
      releaseDate: '2025-11-02',
      songIds: <String>['s002', 's005'],
      playCount: 541200,
    ),
    Album(
      id: 'a003',
      title: '雨天限定',
      artist: '陈屿',
      releaseDate: '2026-06-09',
      songIds: <String>['s003', 's007'],
      playCount: 498700,
    ),
    Album(
      id: 'a004',
      title: '回声岛',
      artist: '未名乐队',
      releaseDate: '2026-01-25',
      songIds: <String>['s004', 's008'],
      playCount: 372100,
    ),
    Album(
      id: 'a005',
      title: '玻璃海',
      artist: '何夕',
      releaseDate: '2025-08-30',
      songIds: <String>['s009', 's010'],
      playCount: 288400,
    ),
    Album(
      id: 'a006',
      title: '光年',
      artist: '沉舟',
      releaseDate: '2026-09-12',
      songIds: <String>['s011', 's012'],
      playCount: 156800,
    ),
  ];

  static Album byId(String id) => all.firstWhere(
        (Album album) => album.id == id,
        orElse: () => all.first,
      );

  static List<Album> byIds(Iterable<String> ids) =>
      ids.map(byId).toList(growable: false);
}
