import 'package:flutter/foundation.dart';

/// 领域实体：歌曲。
///
/// 字段全部来自真实接口（搜索 / 歌单 / 专辑 / 歌手 / 榜单 / 每日推荐共用，
/// 各来源差异由 `data/song_mappers.dart` 收敛）。
@immutable
class Song {
  const Song({
    required this.id,
    required this.title,
    required this.artist,
    this.artistId = '',
    this.album = '',
    this.albumId = '',
    this.duration = Duration.zero,
    this.coverUrl,
    this.hash = '',
    this.isVip = false,
    this.privilege = 0,
  });

  final String id;
  final String title;
  final String artist;

  /// 歌手 ID：详情页跳转 `/artist/:id` 用（无则为空）。
  final String artistId;

  final String album;

  /// 酷狗专辑 ID：`/song/url` 需要同时带 hash + albumId 才能稳定取到音源。
  final String albumId;

  final Duration duration;

  /// 接口返回的封面地址（已补全 `{size}`）；为空时 UI 走渐变占位。
  final String? coverUrl;

  /// 酷狗歌曲 hash（`/song/url` 解析必需）。
  final String hash;

  final bool isVip;

  /// 原始版权标记（0/8 通常不可播，8 为会员曲）。
  final int privilege;

  bool get canResolve => hash.isNotEmpty;

  Song copyWith({
    String? id,
    String? title,
    String? artist,
    String? artistId,
    String? album,
    String? albumId,
    Duration? duration,
    String? coverUrl,
    String? hash,
    bool? isVip,
    int? privilege,
  }) {
    return Song(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      artistId: artistId ?? this.artistId,
      album: album ?? this.album,
      albumId: albumId ?? this.albumId,
      duration: duration ?? this.duration,
      coverUrl: coverUrl ?? this.coverUrl,
      hash: hash ?? this.hash,
      isVip: isVip ?? this.isVip,
      privilege: privilege ?? this.privilege,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'title': title,
    'artist': artist,
    'artistId': artistId,
    'album': album,
    'albumId': albumId,
    'durationMs': duration.inMilliseconds,
    'coverUrl': coverUrl,
    'hash': hash,
    'isVip': isVip,
    'privilege': privilege,
  };

  static Song? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final String hash = '${raw['hash'] ?? ''}';
    if (hash.isEmpty) {
      return null;
    }
    return Song(
      id: '${raw['id'] ?? hash}',
      title: '${raw['title'] ?? '未知歌曲'}',
      artist: '${raw['artist'] ?? '未知歌手'}',
      artistId: '${raw['artistId'] ?? ''}',
      album: '${raw['album'] ?? ''}',
      albumId: '${raw['albumId'] ?? ''}',
      duration: Duration(
        milliseconds: int.tryParse('${raw['durationMs'] ?? 0}') ?? 0,
      ),
      coverUrl: raw['coverUrl']?.toString(),
      hash: hash,
      isVip: raw['isVip'] == true,
      privilege: int.tryParse('${raw['privilege'] ?? 0}') ?? 0,
    );
  }
}
