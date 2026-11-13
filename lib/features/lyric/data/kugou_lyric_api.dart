import 'dart:convert';

import '../../../core/network/json_utils.dart';
import '../../../core/network/kugou_client.dart';
import '../../song/domain/song.dart';
import '../domain/lyric_line.dart';

/// 歌词文档：解析后的逐行歌词 + 原始文本。
class LyricDocument {
  const LyricDocument({this.lines = const <LyricLine>[], this.raw = ''});

  final List<LyricLine> lines;
  final String raw;

  bool get isEmpty => lines.isEmpty;

  static const LyricDocument empty = LyricDocument();

  /// LRC 文本 → 逐行歌词。
  ///
  /// 兼容一行多时间标签（`[00:12.00][01:20.00]歌词`）、毫秒 2/3 位、
  /// 以及 `[ti:]` `[ar:]` 这类元信息行。
  static LyricDocument parse(String lrc) {
    final List<LyricLine> lines = <LyricLine>[];
    final RegExp tag = RegExp(r'\[(\d{1,2}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
    for (final String rawLine in lrc.split(RegExp(r'\r\n|\r|\n'))) {
      final Iterable<RegExpMatch> matches = tag.allMatches(rawLine);
      if (matches.isEmpty) {
        continue;
      }
      final String text = rawLine.replaceAll(tag, '').trim();
      if (text.isEmpty) {
        continue;
      }
      for (final RegExpMatch match in matches) {
        final int minutes = int.tryParse(match.group(1) ?? '0') ?? 0;
        final int seconds = int.tryParse(match.group(2) ?? '0') ?? 0;
        final String rawMs = match.group(3) ?? '0';
        final int millis =
            int.tryParse(rawMs.padRight(3, '0').substring(0, 3)) ?? 0;
        lines.add(
          LyricLine(
            Duration(minutes: minutes, seconds: seconds, milliseconds: millis),
            text,
          ),
        );
      }
    }
    lines.sort((LyricLine a, LyricLine b) => a.time.compareTo(b.time));
    return LyricDocument(lines: lines, raw: lrc);
  }
}

/// 歌词接口：`/search/lyric` 取候选 → `/lyric` 取正文。
class KugouLyricApi {
  KugouLyricApi(this._client);

  final KugouClient _client;

  Future<LyricDocument> load(Song song) async {
    if (song.hash.isEmpty) {
      return LyricDocument.empty;
    }
    String id = '';
    String accessKey = '';
    try {
      final Map<String, dynamic> search = await _client.getJson(
        '/search/lyric',
        query: <String, dynamic>{
          'hash': song.hash,
          'keywords': '${song.title} ${song.artist}'.trim(),
        },
      );
      final Object? candidates =
          search['candidates'] ??
          JsonUtils.asMap(search['data'])?['candidates'];
      final List<Map<String, dynamic>> list = JsonUtils.asMapList(candidates);
      if (list.isEmpty) {
        return LyricDocument.empty;
      }
      id = JsonUtils.str(list.first['id']);
      accessKey = JsonUtils.str(list.first['accesskey']);
    } on KugouApiException {
      return LyricDocument.empty;
    }
    if (id.isEmpty || accessKey.isEmpty) {
      return LyricDocument.empty;
    }

    final Map<String, dynamic> json;
    try {
      json = await _client.getJson(
        '/lyric',
        query: <String, dynamic>{
          'id': id,
          'accesskey': accessKey,
          'decode': 'true',
          'fmt': 'lrc',
          'charset': 'utf8',
        },
      );
    } on KugouApiException {
      return LyricDocument.empty;
    }
    final Map<String, dynamic>? data = JsonUtils.asMap(json['data']);
    final String text = JsonUtils.str(
      json['decodeContent'] ??
          data?['decodeContent'] ??
          json['content'] ??
          data?['content'],
    );
    if (text.isEmpty) {
      return LyricDocument.empty;
    }
    // 实测 `/lyric?decode=true` 的 `content` 仍是 base64 串（`decodeContent`
    // 也可能缺失），这里做兜底解码，否则播放页拿不到逐行歌词。
    return LyricDocument.parse(decodeIfBase64(text));
  }

  static final RegExp _base64Pattern = RegExp(r'^[A-Za-z0-9+/=\s]+$');

  /// 疑似 base64 的歌词正文 → 明文 LRC；已是明文时原样返回。
  static String decodeIfBase64(String raw) {
    final String text = raw.trim();
    if (text.isEmpty || text.contains('[')) {
      return text;
    }
    if (!_base64Pattern.hasMatch(text)) {
      return text;
    }
    try {
      final String decoded = utf8.decode(
        base64Decode(text.replaceAll(RegExp(r'\s'), '')),
        allowMalformed: true,
      );
      return decoded.trim().isEmpty ? text : decoded;
    } on Object {
      return text;
    }
  }
}
