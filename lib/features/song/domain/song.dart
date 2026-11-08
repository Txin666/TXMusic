/// 领域实体：歌曲。
///
/// 骨架期字段仅覆盖 UI 需要的部分；DTO 与 Entity 分离规则见开发文档 §3.3：
/// `data/` 里是 SongDto，映射到本类后再进入 UI。
class Song {
  const Song({
    required this.id,
    required this.title,
    required this.artist,
    this.album = '',
    this.duration = const Duration(minutes: 4),
    this.coverUrl,
    this.hash = '',
    this.isVip = false,
  });

  final String id;
  final String title;
  final String artist;
  final String album;
  final Duration duration;

  /// 真实接口返回的封面地址；骨架期为空，UI 走渐变占位。
  final String? coverUrl;

  /// 酷狗歌曲 hash（后续 `/song/url` 解析需要）。
  final String hash;

  final bool isVip;
}
