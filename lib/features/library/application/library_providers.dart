import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/kugou_providers.dart';
import '../../song/domain/song.dart';
import '../data/kugou_collect_api.dart';
import '../data/library_repository.dart';
import 'liked_songs_providers.dart';

/// 收藏 + 最近播放状态。
@immutable
class LibraryState {
  const LibraryState({
    this.favorites = const <Song>[],
    this.recent = const <Song>[],
    this.isLoading = true,
  });

  final List<Song> favorites;
  final List<Song> recent;
  final bool isLoading;

  bool isFavorite(String hash) =>
      favorites.any((Song song) => song.hash == hash);

  LibraryState copyWith({
    List<Song>? favorites,
    List<Song>? recent,
    bool? isLoading,
  }) {
    return LibraryState(
      favorites: favorites ?? this.favorites,
      recent: recent ?? this.recent,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// 音乐库编排：启动即从本地恢复，收藏 / 最近播放随操作落盘。
class LibraryController extends Notifier<LibraryState> {
  final LibraryRepository _repository = const LibraryRepository();

  @override
  LibraryState build() {
    // 登录态下「本机收藏」只是服务器「我喜欢」的镜像：服务器一变（含播放页 /
    // 迷你播放条 / 托盘任意入口的收藏与取消），这里立刻跟上，
    // 托盘面板、本机收藏区、各处心形不会再各说各话。
    ref.listen<AsyncValue<LikedSongsSnapshot>>(likedSongsProvider, (
      AsyncValue<LikedSongsSnapshot>? previous,
      AsyncValue<LikedSongsSnapshot> next,
    ) {
      final LikedSongsSnapshot? remote = next.asData?.value;
      if (remote != null) {
        unawaited(_mirrorRemote(remote));
      }
    });
    Future<void>.microtask(_restore);
    return const LibraryState();
  }

  /// 把本机收藏对齐到服务器快照（hash 集合不同才落盘，避免无意义写入）。
  Future<void> _mirrorRemote(LikedSongsSnapshot remote) async {
    if (!ref.read(kugouSessionProvider).isLoggedIn) {
      return;
    }
    final Set<String> remoteHashes = remote.songs
        .map((Song song) => song.hash)
        .where((String hash) => hash.isNotEmpty)
        .toSet();
    final Set<String> localHashes = state.favorites
        .map((Song song) => song.hash)
        .toSet();
    if (remoteHashes.length == localHashes.length &&
        remoteHashes.containsAll(localHashes)) {
      return;
    }
    final List<Song> next = await _repository.replaceFavorites(remote.songs);
    state = state.copyWith(favorites: next);
  }

  Future<void> _restore() async {
    final List<Song> favorites = await _repository.loadFavorites();
    final List<Song> recent = await _repository.loadRecent();
    state = LibraryState(
      favorites: favorites,
      recent: recent,
      isLoading: false,
    );
  }

  Future<void> refresh() => _restore();

  /// 收藏 / 取消收藏。
  ///
  /// 登录态下**服务器为准**：先写「我喜欢」（未收藏则收藏、已收藏则取消），
  /// 再把本机镜像校正成服务器结果，所以迷你播放条 / 托盘 / 列表页的心形
  /// 与服务器、「我的音乐 → 我喜欢」始终一致；未登录时退回纯本机收藏。
  /// 服务器写入失败会抛 [KugouApiException]，由调用方提示。
  Future<void> toggleFavorite(Song song) async {
    final bool syncToServer =
        ref.read(kugouSessionProvider).isLoggedIn && song.hash.isNotEmpty;
    if (syncToServer) {
      final bool liked = await ref
          .read(likedSongsProvider.notifier)
          .toggle(song);
      if (liked == state.isFavorite(song.hash)) {
        return;
      }
      final List<Song> favorites = await _repository.toggleFavorite(song);
      state = state.copyWith(favorites: favorites);
      return;
    }
    final List<Song> favorites = await _repository.toggleFavorite(song);
    state = state.copyWith(favorites: favorites);
  }

  Future<void> recordPlayed(Song song) async {
    final List<Song> recent = await _repository.pushRecent(song);
    state = state.copyWith(recent: recent);
  }

  Future<void> clearRecent() async {
    await _repository.clearRecent();
    state = state.copyWith(recent: const <Song>[]);
  }
}

final NotifierProvider<LibraryController, LibraryState> libraryProvider =
    NotifierProvider<LibraryController, LibraryState>(LibraryController.new);

/// 收藏状态快速查询（播放条 / 列表页共用）。
final Provider<bool Function(String hash)> isFavoriteProvider =
    Provider<bool Function(String hash)>((Ref ref) {
      final LibraryState state = ref.watch(libraryProvider);
      if (!ref.watch(kugouSessionProvider).isLoggedIn) {
        return state.isFavorite;
      }
      // 服务器为主；列表还在拉取时先用本机镜像顶一下，避免心形闪烁。
      final LikedSongsSnapshot? remote = ref
          .watch(likedSongsProvider)
          .asData
          ?.value;
      if (remote == null) {
        return state.isFavorite;
      }
      return remote.has;
    });
