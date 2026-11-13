import 'package:flutter/foundation.dart';

import '../../album/domain/album.dart';
import '../../playlist/domain/playlist.dart';
import '../../song/domain/song.dart';

/// 「我的音乐」页的用户维度数据快照。
///
/// 四个分区分别对应四种上游能力：
/// - [createdPlaylists] 我创建的歌单（`/user/playlist` 里自建部分）
/// - [collectedPlaylists] 我收藏的歌单（`/user/playlist` 里他人创建部分）
/// - [likedSongs] 我的喜欢（歌单体系里的「我喜欢」列表曲目）
/// - [albums] 我收藏 / 已购的专辑（`/user/purchased/albums`）
///
/// 云歌单（cloudlist）在概念版（lite）登录态下会被上游直接拒绝
/// （`error_code=30227`），此时对应分区为单列降级：`items` 为空、
/// `*Error` 带上人话原因，页面据此展示提示条而不是整页报错。
@immutable
class MyMusicLibrary {
  const MyMusicLibrary({
    this.createdPlaylists = const <Playlist>[],
    this.collectedPlaylists = const <Playlist>[],
    this.likedSongs = const <Song>[],
    this.albums = const <Album>[],
    this.playlistsError,
    this.likedError,
    this.albumsError,
    this.isLoggedIn = false,
  });

  final List<Playlist> createdPlaylists;
  final List<Playlist> collectedPlaylists;
  final List<Song> likedSongs;
  final List<Album> albums;

  /// 歌单分区降级原因（我创建 / 我收藏共用一条，因为同一次请求）。
  final String? playlistsError;

  /// 「我的喜欢」降级原因。
  final String? likedError;

  /// 收藏专辑降级原因。
  final String? albumsError;

  /// 当前是否为已登录态；未登录时不发请求，页面直接提示去登录。
  final bool isLoggedIn;

  bool get hasPlaylistsError => playlistsError != null;

  static const MyMusicLibrary empty = MyMusicLibrary();

  MyMusicLibrary copyWith({
    List<Playlist>? createdPlaylists,
    List<Playlist>? collectedPlaylists,
    List<Song>? likedSongs,
    List<Album>? albums,
    String? playlistsError,
    String? likedError,
    String? albumsError,
    bool? isLoggedIn,
  }) {
    return MyMusicLibrary(
      createdPlaylists: createdPlaylists ?? this.createdPlaylists,
      collectedPlaylists: collectedPlaylists ?? this.collectedPlaylists,
      likedSongs: likedSongs ?? this.likedSongs,
      albums: albums ?? this.albums,
      playlistsError: playlistsError ?? this.playlistsError,
      likedError: likedError ?? this.likedError,
      albumsError: albumsError ?? this.albumsError,
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
    );
  }
}
