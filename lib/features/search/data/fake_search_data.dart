/// 骨架期假数据：搜索历史与热搜。
///
/// TODO(storage): 搜索历史需落 Hive（`core/constants/storage_keys.dart` 新增 key），
/// 当前仅内存态，重启即丢（见文档 §8）。
class FakeSearchData {
  const FakeSearchData._();

  static const List<String> history = <String>[
    '城市夜航',
    '未名乐队',
    '深夜通勤',
    '雨天限定',
  ];

  static const List<String> hotKeywords = <String>[
    '每日推荐',
    '飙升榜',
    '独立摇滚',
    '苏白 晚风集',
    '深夜收听',
    '沿海公路',
    '玻璃海',
    '新歌速递',
  ];
}
