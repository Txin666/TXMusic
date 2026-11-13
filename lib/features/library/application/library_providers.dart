import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../song/domain/song.dart';
import '../data/library_repository.dart';

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
    Future<void>.microtask(_restore);
    return const LibraryState();
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

  Future<void> toggleFavorite(Song song) async {
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
      return state.isFavorite;
    });
