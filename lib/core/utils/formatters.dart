/// 展示层格式化工具（见开发文档 §3.2 core/utils/formatters.dart）。
class Formatters {
  const Formatters._();

  /// Duration → `mm:ss`（超过 1 小时则 `h:mm:ss`）。
  static String duration(Duration d) {
    final int totalSeconds = d.inSeconds;
    final int hours = totalSeconds ~/ 3600;
    final int minutes = (totalSeconds % 3600) ~/ 60;
    final int seconds = totalSeconds % 60;
    final String mm = minutes.toString().padLeft(2, '0');
    final String ss = seconds.toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$mm:$ss';
    }
    return '$minutes:$ss';
  }

  /// 播放次数：12345 → 1.2万。
  static String playCount(int count) {
    if (count >= 100000000) {
      return '${(count / 100000000).toStringAsFixed(1)}亿';
    }
    if (count >= 10000) {
      return '${(count / 10000).toStringAsFixed(1)}万';
    }
    return '$count';
  }

  /// 日期 → `yyyy-MM-dd`（禁止在 strftime 格式串中使用中文，故此处直接拼接）。
  static String date(DateTime time) {
    final String m = time.month.toString().padLeft(2, '0');
    final String d = time.day.toString().padLeft(2, '0');
    return '${time.year}-$m-$d';
  }

  /// 相对时间：刚刚 / N 分钟前 / N 小时前 / N 天前。
  static String relative(DateTime time, {DateTime? now}) {
    final DateTime base = now ?? DateTime.now();
    final Duration diff = base.difference(time);
    if (diff.inMinutes < 1) {
      return '刚刚';
    }
    if (diff.inHours < 1) {
      return '${diff.inMinutes} 分钟前';
    }
    if (diff.inDays < 1) {
      return '${diff.inHours} 小时前';
    }
    if (diff.inDays < 30) {
      return '${diff.inDays} 天前';
    }
    return date(time);
  }
}
