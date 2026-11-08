/// 领域实体：歌词行（骨架期仅逐行，逐字 KRC 解析见 `core/utils/lrc_parser.dart`）。
class LyricLine {
  const LyricLine(this.time, this.text);

  final Duration time;
  final String text;
}
