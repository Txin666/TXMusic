import '../domain/artist.dart';

/// 骨架期假数据：歌手。
///
/// TODO(api): 接入 `/artist/audios`、`/artist/album` 后替换为 ArtistRepository。
class FakeArtists {
  const FakeArtists._();

  static const List<Artist> all = <Artist>[
    Artist(
      id: 'ar001',
      name: '林彻',
      bio: '独立唱作人，作品以城市夜景与公路意象为主。',
      songIds: <String>['s001', 's006'],
      albumIds: <String>['a001'],
      fansCount: 386000,
    ),
    Artist(
      id: 'ar002',
      name: '苏白',
      bio: '民谣歌手，擅长用极简编曲讲述日常。',
      songIds: <String>['s002', 's005'],
      albumIds: <String>['a002'],
      fansCount: 254000,
    ),
    Artist(
      id: 'ar003',
      name: '陈屿',
      bio: '电子与流行的混合体，热衷雨声采样。',
      songIds: <String>['s003', 's007'],
      albumIds: <String>['a003'],
      fansCount: 198000,
    ),
    Artist(
      id: 'ar004',
      name: '未名乐队',
      bio: '四人独立摇滚乐队，2024 年成立于杭州。',
      songIds: <String>['s004', 's008'],
      albumIds: <String>['a004'],
      fansCount: 143000,
    ),
    Artist(
      id: 'ar005',
      name: '何夕',
      bio: '把便利店和深夜写成歌的创作者。',
      songIds: <String>['s009', 's010'],
      albumIds: <String>['a005'],
      fansCount: 121000,
    ),
    Artist(
      id: 'ar006',
      name: '沉舟',
      bio: '氛围流行组合，主题多为光与时间。',
      songIds: <String>['s011', 's012'],
      albumIds: <String>['a006'],
      fansCount: 96800,
    ),
  ];

  static Artist byId(String id) => all.firstWhere(
        (Artist artist) => artist.id == id,
        orElse: () => all.first,
      );

  static Artist byName(String name) => all.firstWhere(
        (Artist artist) => artist.name == name,
        orElse: () => all.first,
      );
}
