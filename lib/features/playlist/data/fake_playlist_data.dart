import '../domain/playlist.dart';

/// 骨架期假数据：歌单。
///
/// TODO(api): 接入 `/plist/list`、`/plist/detail` 等接口后替换为 PlaylistRepository。
class FakePlaylists {
  const FakePlaylists._();

  static const List<Playlist> all = <Playlist>[
    Playlist(
      id: 'p001',
      title: '深夜地铁通勤歌单',
      creator: 'TX 编辑部',
      description: '适合夜晚通勤的松弛感，一点合成器一点回声。',
      songIds: <String>['s001', 's003', 's007', 's009', 's002'],
      playCount: 1286000,
      tags: <String>['夜晚', '通勤', '合成器'],
    ),
    Playlist(
      id: 'p002',
      title: '写代码时的白噪音替代',
      creator: 'TX 编辑部',
      description: '无人声、节奏稳定，适合长时间专注。',
      songIds: <String>['s004', 's008', 's006', 's010'],
      playCount: 934500,
      tags: <String>['专注', '器乐'],
    ),
    Playlist(
      id: 'p003',
      title: '周末公路旅行',
      creator: '林彻',
      description: '沿海公路与夏日隧道，一路向前。',
      songIds: <String>['s006', 's008', 's001', 's012', 's005'],
      playCount: 621300,
      tags: <String>['旅行', '摇滚'],
    ),
    Playlist(
      id: 'p004',
      title: '失眠者的凌晨三点',
      creator: '陈屿',
      description: '凌晨三点的房间，灯还亮着。',
      songIds: <String>['s007', 's009', 's003', 's011'],
      playCount: 452800,
      tags: <String>['治愈', '失眠'],
    ),
    Playlist(
      id: 'p005',
      title: '中文独立摇滚新声',
      creator: 'TX 编辑部',
      description: '未名乐队、沉舟等新声代的代表作品。',
      songIds: <String>['s004', 's008', 's011', 's012'],
      playCount: 317600,
      tags: <String>['独立', '摇滚'],
    ),
    Playlist(
      id: 'p006',
      title: '玻璃海边的午后',
      creator: '何夕',
      description: '阳光落在海面上，慢一点也没关系。',
      songIds: <String>['s010', 's005', 's002', 's012'],
      playCount: 205900,
      tags: <String>['午后', '民谣'],
    ),
  ];

  static Playlist byId(String id) => all.firstWhere(
        (Playlist playlist) => playlist.id == id,
        orElse: () => all.first,
      );
}
