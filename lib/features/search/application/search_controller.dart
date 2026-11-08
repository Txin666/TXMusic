import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../artist/data/fake_artist_data.dart';
import '../../artist/domain/artist.dart';
import '../../playlist/data/fake_playlist_data.dart';
import '../../playlist/domain/playlist.dart';
import '../../song/data/fake_song_data.dart';
import '../../song/domain/song.dart';
import '../data/fake_search_data.dart';

/// 搜索结果聚合（骨架期在内存中做名称匹配，不请求接口）。
class SearchState {
  const SearchState({
    this.keyword = '',
    this.history = FakeSearchData.history,
    this.songs = const <Song>[],
    this.playlists = const <Playlist>[],
    this.artists = const <Artist>[],
  });

  final String keyword;
  final List<String> history;
  final List<Song> songs;
  final List<Playlist> playlists;
  final List<Artist> artists;

  bool get isEmptyResult =>
      keyword.isNotEmpty &&
      songs.isEmpty &&
      playlists.isEmpty &&
      artists.isEmpty;

  SearchState copyWith({
    String? keyword,
    List<String>? history,
    List<Song>? songs,
    List<Playlist>? playlists,
    List<Artist>? artists,
  }) {
    return SearchState(
      keyword: keyword ?? this.keyword,
      history: history ?? this.history,
      songs: songs ?? this.songs,
      playlists: playlists ?? this.playlists,
      artists: artists ?? this.artists,
    );
  }
}

/// 搜索页编排。
/// TODO(api): 接入 `/search/song`、`/search/playlist`、`/artist/search`，
/// 并做 300ms 防抖 + 分页（文档 §5 搜索模块）。
/// TODO(storage): 历史记录落 Hive。
class SearchPageController extends Notifier<SearchState> {
  @override
  SearchState build() => const SearchState();

  void updateKeyword(String value) {
    state = state.copyWith(keyword: value);
  }

  void search(String keyword) {
    final String key = keyword.trim();
    if (key.isEmpty) {
      clear();
      return;
    }
    final String lower = key.toLowerCase();
    final List<String> history = <String>[
      key,
      ...state.history.where((String item) => item != key),
    ].take(10).toList(growable: false);

    state = SearchState(
      keyword: key,
      history: history,
      songs: FakeSongs.all
          .where((Song song) =>
              song.title.toLowerCase().contains(lower) ||
              song.artist.toLowerCase().contains(lower) ||
              song.album.toLowerCase().contains(lower))
          .toList(growable: false),
      playlists: FakePlaylists.all
          .where((Playlist playlist) =>
              playlist.title.toLowerCase().contains(lower) ||
              playlist.creator.toLowerCase().contains(lower))
          .toList(growable: false),
      artists: FakeArtists.all
          .where((Artist artist) => artist.name.toLowerCase().contains(lower))
          .toList(growable: false),
    );
  }

  void clear() {
    state = SearchState(keyword: '', history: state.history);
  }

  void clearHistory() {
    state = state.copyWith(history: const <String>[]);
  }
}

final searchPageControllerProvider =
    NotifierProvider<SearchPageController, SearchState>(SearchPageController.new);
