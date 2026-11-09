import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/kugou_client.dart';
import '../../../core/network/kugou_providers.dart';
import '../../artist/domain/artist.dart';
import '../../playlist/domain/playlist.dart';
import '../../song/data/kugou_song_api.dart';
import '../../song/domain/song.dart';
import '../data/fake_search_data.dart';

/// 搜索结果聚合（歌曲走真实 `/search/song`，歌单/歌手暂留骨架）。
class SearchState {
  const SearchState({
    this.keyword = '',
    this.history = FakeSearchData.history,
    this.songs = const <Song>[],
    this.playlists = const <Playlist>[],
    this.artists = const <Artist>[],
    this.isLoading = false,
    this.errorMessage,
  });

  final String keyword;
  final List<String> history;
  final List<Song> songs;
  final List<Playlist> playlists;
  final List<Artist> artists;
  final bool isLoading;
  final String? errorMessage;

  bool get isEmptyResult =>
      keyword.isNotEmpty &&
      !isLoading &&
      errorMessage == null &&
      songs.isEmpty &&
      playlists.isEmpty &&
      artists.isEmpty;

  SearchState copyWith({
    String? keyword,
    List<String>? history,
    List<Song>? songs,
    List<Playlist>? playlists,
    List<Artist>? artists,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return SearchState(
      keyword: keyword ?? this.keyword,
      history: history ?? this.history,
      songs: songs ?? this.songs,
      playlists: playlists ?? this.playlists,
      artists: artists ?? this.artists,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// 搜索页编排：真实接口 + 请求竞态保护。
///
/// TODO(api): 补 `/search/playlist`、`/artist/search` 聚合；
/// TODO(storage): 历史记录落 Hive。
class SearchPageController extends Notifier<SearchState> {
  int _requestId = 0;

  @override
  SearchState build() => const SearchState();

  void updateKeyword(String value) {
    state = state.copyWith(keyword: value);
  }

  /// 发起搜索；同一关键字重复提交会被忽略（避免重复请求）。
  Future<void> search(String keyword) async {
    final String key = keyword.trim();
    if (key.isEmpty) {
      clear();
      return;
    }
    if (state.isLoading && state.keyword == key) {
      return;
    }

    final List<String> history = <String>[
      key,
      ...state.history.where((String item) => item != key),
    ].take(10).toList(growable: false);

    final int request = ++_requestId;
    state = state.copyWith(
      keyword: key,
      history: history,
      songs: const <Song>[],
      isLoading: true,
      clearError: true,
    );

    try {
      final KugouSongApi api = ref.read(kugouSongApiProvider);
      final List<Song> songs = await api.search(key);
      if (request != _requestId) {
        return;
      }
      state = state.copyWith(
        songs: songs,
        isLoading: false,
        clearError: true,
      );
    } on KugouApiException catch (error) {
      if (request != _requestId) {
        return;
      }
      state = state.copyWith(
        isLoading: false,
        songs: const <Song>[],
        errorMessage: error.message,
      );
    } on Object catch (error) {
      if (request != _requestId) {
        return;
      }
      state = state.copyWith(
        isLoading: false,
        songs: const <Song>[],
        errorMessage: '搜索失败：$error',
      );
    }
  }

  void clear() {
    _requestId++;
    state = SearchState(keyword: '', history: state.history);
  }

  void clearHistory() {
    state = state.copyWith(history: const <String>[]);
  }
}

final searchPageControllerProvider =
    NotifierProvider<SearchPageController, SearchState>(SearchPageController.new);
