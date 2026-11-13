import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/kugou_client.dart';
import '../../../core/network/kugou_providers.dart';
import '../../album/domain/album.dart';
import '../../artist/domain/artist.dart';
import '../../playlist/domain/playlist.dart';
import '../../song/domain/song.dart';
import '../data/kugou_search_api.dart';
import '../data/search_history_repository.dart';

/// 搜索结果聚合：全部来自真实 `/search/complex`（歌曲 + 歌单 + 歌手 + 专辑）。
class SearchState {
  const SearchState({
    this.keyword = '',
    this.history = const <String>[],
    this.songs = const <Song>[],
    this.playlists = const <Playlist>[],
    this.artists = const <Artist>[],
    this.albums = const <Album>[],
    this.isLoading = false,
    this.errorMessage,
    this.notice,
  });

  final String keyword;
  final List<String> history;
  final List<Song> songs;
  final List<Playlist> playlists;
  final List<Artist> artists;
  final List<Album> albums;
  final bool isLoading;
  final String? errorMessage;

  /// 降级提示（如分区接口不可用，仅展示单曲），有值时才展示。
  final String? notice;

  bool get isEmptyResult =>
      keyword.isNotEmpty &&
      !isLoading &&
      errorMessage == null &&
      songs.isEmpty &&
      playlists.isEmpty &&
      artists.isEmpty &&
      albums.isEmpty;

  SearchState copyWith({
    String? keyword,
    List<String>? history,
    List<Song>? songs,
    List<Playlist>? playlists,
    List<Artist>? artists,
    List<Album>? albums,
    bool? isLoading,
    String? errorMessage,
    String? notice,
    bool clearError = false,
    bool clearResults = false,
  }) {
    return SearchState(
      keyword: keyword ?? this.keyword,
      history: history ?? this.history,
      songs: clearResults ? const <Song>[] : (songs ?? this.songs),
      playlists: clearResults
          ? const <Playlist>[]
          : (playlists ?? this.playlists),
      artists: clearResults ? const <Artist>[] : (artists ?? this.artists),
      albums: clearResults ? const <Album>[] : (albums ?? this.albums),
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      notice: clearResults ? notice : (notice ?? this.notice),
    );
  }
}

/// 搜索页编排：真实搜索接口 + 历史落盘 + 请求竞态保护。
///
/// - 结果：`KugouSearchApi.bundle`（以 `/search` 单曲为主，`/search/complex`
///   仅作分区补充，失败静默降级为只有单曲，分区数据为空时 UI 隐藏分区）；
/// - 历史：`SearchHistoryRepository`（`.local/search_history.json`）。
class SearchPageController extends Notifier<SearchState> {
  static const SearchHistoryRepository _history = SearchHistoryRepository();

  int _requestId = 0;

  @override
  SearchState build() {
    Future<void>.microtask(_restoreHistory);
    return const SearchState();
  }

  Future<void> _restoreHistory() async {
    try {
      final List<String> history = await _history.load();
      state = state.copyWith(history: history);
    } on Object {
      // 历史读取失败不阻塞搜索，静默降级为空历史。
    }
  }

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

    final int request = ++_requestId;
    state = state.copyWith(
      keyword: key,
      isLoading: true,
      clearResults: true,
      clearError: true,
    );
    unawaited(_remember(key));

    try {
      final SearchBundle bundle = await ref
          .read(kugouSearchApiProvider)
          .bundle(key);
      if (request != _requestId) {
        return;
      }
      state = state.copyWith(
        songs: bundle.songs,
        playlists: bundle.playlists,
        artists: bundle.artists,
        albums: bundle.albums,
        isLoading: false,
        clearError: true,
        notice: bundle.partitionsFailed
            ? '歌单 / 专辑 / 歌手分区接口本次请求失败，已降级只展示单曲结果'
            : null,
      );
    } on KugouApiException catch (error) {
      if (request != _requestId) {
        return;
      }
      state = state.copyWith(
        isLoading: false,
        clearResults: true,
        errorMessage: error.message,
      );
    } on Object catch (error) {
      if (request != _requestId) {
        return;
      }
      state = state.copyWith(
        isLoading: false,
        clearResults: true,
        errorMessage: '搜索失败：$error',
      );
    }
  }

  /// 历史落盘：失败不影响搜索结果。
  Future<void> _remember(String key) async {
    try {
      final List<String> history = await _history.push(key);
      state = state.copyWith(history: history);
    } on Object {
      // 忽略写入异常，历史仅作辅助信息。
    }
  }

  void clear() {
    _requestId++;
    state = SearchState(keyword: '', history: state.history);
  }

  void clearHistory() {
    state = state.copyWith(history: const <String>[]);
    unawaited(_history.clear());
  }
}

final searchPageControllerProvider =
    NotifierProvider<SearchPageController, SearchState>(
      SearchPageController.new,
    );

/// 热搜关键词（真实 `/search/hot/detail`），搜索页空态展示。
final FutureProvider<List<String>> hotKeywordsProvider =
    FutureProvider<List<String>>(
      (Ref ref) => ref.watch(kugouSearchApiProvider).hotKeywords(),
    );
