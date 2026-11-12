import 'lyric_line.dart';

/// 歌词高亮行定位（域层纯函数，供播放详情页消费）。
class LyricIndex {
  const LyricIndex._();

  /// 二分查找当前应高亮的行索引；歌词为空返回 -1，未到第一行返回 0。
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
