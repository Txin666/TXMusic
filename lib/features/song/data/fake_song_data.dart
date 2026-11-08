import '../domain/song.dart';

/// 骨架期假数据：歌曲目录。
///
/// TODO(api): 接入 `services/api/modules/song_api.dart` 后，由
/// `song/domain/song_repository.dart` 提供真实数据，本文件仅保留给离线开发/测试使用。
class FakeSongs {
  const FakeSongs._();

  static const List<Song> all = <Song>[
    Song(
      id: 's001',
      title: '城市夜航',
      artist: '林彻',
      album: '城市夜航',
      duration: Duration(minutes: 4, seconds: 12),
      hash: 'hash_s001',
    ),
    Song(
      id: 's002',
      title: '晚风里的信号',
      artist: '苏白',
      album: '晚风集',
      duration: Duration(minutes: 3, seconds: 48),
      hash: 'hash_s002',
    ),
    Song(
      id: 's003',
      title: '雨天限定',
      artist: '陈屿',
      album: '雨天限定',
      duration: Duration(minutes: 4, seconds: 5),
      hash: 'hash_s003',
    ),
    Song(
      id: 's004',
      title: '回声岛',
      artist: '未名乐队',
      album: '回声岛',
      duration: Duration(minutes: 5, seconds: 20),
      hash: 'hash_s004',
    ),
    Song(
      id: 's005',
      title: '出租屋的灯',
      artist: '苏白',
      album: '晚风集',
      duration: Duration(minutes: 3, seconds: 56),
      hash: 'hash_s005',
    ),
    Song(
      id: 's006',
      title: '沿海公路',
      artist: '林彻',
      album: '城市夜航',
      duration: Duration(minutes: 4, seconds: 30),
      hash: 'hash_s006',
    ),
    Song(
      id: 's007',
      title: '失眠协议',
      artist: '陈屿',
      album: '失眠协议',
      duration: Duration(minutes: 3, seconds: 34),
      hash: 'hash_s007',
      isVip: true,
    ),
    Song(
      id: 's008',
      title: '夏日隧道',
      artist: '未名乐队',
      album: '夏日隧道',
      duration: Duration(minutes: 4, seconds: 46),
      hash: 'hash_s008',
    ),
    Song(
      id: 's009',
      title: '深夜便利店',
      artist: '何夕',
      album: '深夜便利店',
      duration: Duration(minutes: 3, seconds: 22),
      hash: 'hash_s009',
    ),
    Song(
      id: 's010',
      title: '玻璃海',
      artist: '何夕',
      album: '玻璃海',
      duration: Duration(minutes: 4, seconds: 58),
      hash: 'hash_s010',
    ),
    Song(
      id: 's011',
      title: '光年之外的你',
      artist: '沉舟',
      album: '光年',
      duration: Duration(minutes: 4, seconds: 21),
      hash: 'hash_s011',
      isVip: true,
    ),
    Song(
      id: 's012',
      title: '无声告白',
      artist: '沉舟',
      album: '光年',
      duration: Duration(minutes: 3, seconds: 41),
      hash: 'hash_s012',
    ),
  ];

  static Song byId(String id) => all.firstWhere(
        (Song song) => song.id == id,
        orElse: () => all.first,
      );

  static List<Song> byIds(Iterable<String> ids) =>
      ids.map(byId).toList(growable: false);

  /// 取一段连续切片，越界自动回绕，便于假数据复用到不同页面。
  static List<Song> slice(int start, int count) {
    final List<Song> result = <Song>[];
    for (int i = 0; i < count; i++) {
      result.add(all[(start + i) % all.length]);
    }
    return result;
  }
}
