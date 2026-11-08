import '../domain/lyric_line.dart';

/// 骨架期假歌词（用于播放详情页与桌面歌词占位）。
///
/// TODO(api): 接入 `/krc/get` 或 `/search/lyric` 后由 `lyric/domain/lyric_repository.dart`
/// 提供真实歌词，并配合 `core/utils/lrc_parser.dart` 解析时间轴。
class FakeLyricData {
  const FakeLyricData._();

  static const List<LyricLine> lines = <LyricLine>[
    LyricLine(Duration(seconds: 0), 'TX Music · 正在播放'),
    LyricLine(Duration(seconds: 8), '霓虹把街区切成两半'),
    LyricLine(Duration(seconds: 14), '我在中间慢慢走'),
    LyricLine(Duration(seconds: 21), '风从高架桥下面穿过'),
    LyricLine(Duration(seconds: 27), '把白天的声音都吹散'),
    LyricLine(Duration(seconds: 34), '城市的夜航 还在继续'),
    LyricLine(Duration(seconds: 41), '路灯替我说了晚安'),
    LyricLine(Duration(seconds: 48), '如果明天依旧拥挤'),
    LyricLine(Duration(seconds: 55), '就把这首歌留在耳边'),
    LyricLine(Duration(seconds: 62), '—— 骨架期示例歌词 ——'),
  ];

  /// 二分查找当前应高亮的行索引（与文档 §9.3 领域层纯函数约定一致）。
  static int indexAt(List<LyricLine> lines, Duration position) {
    if (lines.isEmpty) {
      return -1;
    }
    int low = 0;
    int high = lines.length - 1;
    int result = 0;
    while (low <= high) {
      final int mid = (low + high) ~/ 2;
      if (lines[mid].time <= position) {
        result = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return result;
  }
}
