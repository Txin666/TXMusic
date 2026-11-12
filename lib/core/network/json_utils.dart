/// 接口 JSON 取值工具。
///
/// 酷狗接口同一语义字段在不同接口里命名完全不一样（`hash` / `FileHash` /
/// `hash_128`，`songname` / `audio_name` / `filename`），且大量字段藏在
/// `base` / `audio_info` / `album_info` 等嵌套层里。这里统一做一次收敛，
/// 让 data 层映射代码不必到处写 `as Map<String, dynamic>`。
class JsonUtils {
  const JsonUtils._();

  /// 常见嵌套层：取值时按顺序向下钻。
  static const List<String> nestedKeys = <String>[
    'base',
    'audio_info',
    'album_info',
    'albuminfo',
    'deprecated',
    'trans_param',
    'privilege_download',
    // `user_history` 把歌曲塞在 `songs[].info` 里，放最后避免通用名误命中
    'info',
  ];

  static Map<String, dynamic>? asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map<String, dynamic>(
        (Object? key, Object? item) => MapEntry<String, dynamic>('$key', item),
      );
    }
    return null;
  }

  /// 把 `List<dynamic>` 收敛成 `List<Map<String, dynamic>>`，过滤脏数据。
  static List<Map<String, dynamic>> asMapList(Object? value) {
    if (value is! List) {
      return const <Map<String, dynamic>>[];
    }
    final List<Map<String, dynamic>> result = <Map<String, dynamic>>[];
    for (final Object? item in value) {
      final Map<String, dynamic>? map = asMap(item);
      if (map != null) {
        result.add(map);
      }
    }
    return result;
  }

  /// 按候选键取值，支持向下钻一层嵌套（`base` / `audio_info` / ...）。
  static Object? pick(Map<String, dynamic> json, List<String> keys) {
    for (final String key in keys) {
      final Object? value = json[key];
      if (value != null && '$value'.isNotEmpty) {
        return value;
      }
    }
    for (final String nest in nestedKeys) {
      final Map<String, dynamic>? child = asMap(json[nest]);
      if (child == null) {
        continue;
      }
      for (final String key in keys) {
        final Object? value = child[key];
        if (value != null && '$value'.isNotEmpty) {
          return value;
        }
      }
    }
    return null;
  }

  static String str(Object? value, {String fallback = ''}) {
    if (value == null) {
      return fallback;
    }
    final String text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  static int integer(Object? value, {int fallback = 0}) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    final String text = str(value);
    if (text.isEmpty) {
      return fallback;
    }
    return int.tryParse(text) ?? double.tryParse(text)?.toInt() ?? fallback;
  }

  /// 时长：不同接口给秒或毫秒，> 36000 一律按毫秒处理（一首歌不可能 10 小时内）。
  static Duration duration(Object? value) {
    final int raw = integer(value);
    if (raw <= 0) {
      return Duration.zero;
    }
    if (raw > 36000) {
      return Duration(milliseconds: raw);
    }
    return Duration(seconds: raw);
  }

  /// 封面模板串补全尺寸：`http://imge.kugou.com/stdmusic/{size}/x.jpg`。
  static String? cover(Object? value, {int size = 480}) {
    final String raw = str(value);
    if (raw.isEmpty) {
      return null;
    }
    return raw
        .replaceAll('{size}', '$size')
        .replaceFirst('http://', 'https://');
  }
}
