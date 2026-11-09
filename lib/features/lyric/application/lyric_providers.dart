import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/kugou_providers.dart';
import '../../song/domain/song.dart';
import '../data/kugou_lyric_api.dart';
import '../domain/lyric_line.dart';

/// 歌词缓存键：hash 定位音源，歌名/歌手用于 `/search/lyric` 的候选匹配。
///
/// 用 record 而不是拼字符串，天然具备值相等，Riverpod family 缓存才不会失效。
typedef LyricKey = ({String hash, String title, String artist});

LyricKey lyricKeyOf(Song song) =>
    (hash: song.hash, title: song.title, artist: song.artist);

/// 歌词文档（逐行 + 原文）。
final lyricDocumentProvider = FutureProvider.family<LyricDocument, LyricKey>((
  Ref ref,
  LyricKey key,
) {
  return ref.watch(kugouLyricApiProvider).load(
        Song(
          id: key.hash,
          title: key.title,
          artist: key.artist,
          hash: key.hash,
        ),
      );
});

/// 仅逐行歌词，供歌词视图直接消费。
final lyricLinesProvider = FutureProvider.family<List<LyricLine>, LyricKey>((
  Ref ref,
  LyricKey key,
) async {
  final LyricDocument document =
      await ref.watch(lyricDocumentProvider(key).future);
  return document.lines;
});
