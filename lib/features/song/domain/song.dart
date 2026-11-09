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
    this.albumId = '',
    this.duration = const Duration(minutes: 4),
    this.coverUrl,
    this.hash = '',
    this.isVip = false,
  });

  final String id;
  final String title;
  final String artist;
  final String album;

  /// 酷狗专辑 ID：`/song/url` 需要同时带 hash + albumId 才能稳定取到音源。
  final String albumId;

  final Duration duration;

  /// 真实接口返回的封面地址；骨架期为空，UI 走渐变占位。
  final String? coverUrl;

  /// 酷狗歌曲 hash（后续 `/song/url` 解析需要）。
  final String hash;

  final bool isVip;

  bool get canResolve => hash.isNotEmpty;

  Song copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    String? albumId,
    Duration? duration,
    String? coverUrl,
    String? hash,
    bool? isVip,
  }) {
    return Song(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      albumId: albumId ?? this.albumId,
      duration: duration ?? this.duration,
      coverUrl: coverUrl ?? this.coverUrl,
      hash: hash ?? this.hash,
      isVip: isVip ?? this.isVip,
    );
  }
}
