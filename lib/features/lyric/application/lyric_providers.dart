import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/fake_lyric_data.dart';
import '../domain/lyric_line.dart';

/// 歌词（骨架期所有歌曲共用一份示例歌词）。
/// TODO(api): 按 songId 请求 `/krc/get`，并以 `autoDispose` 释放，避免缓存膨胀。
final lyricLinesProvider = Provider.family<List<LyricLine>, String>(
  (Ref ref, String songId) => FakeLyricData.lines,
);
