import '../../../core/network/json_utils.dart';
import '../../../core/network/kugou_client.dart';
import '../../album/domain/album.dart';
import '../../artist/domain/artist.dart';
import '../../playlist/domain/playlist.dart';
import '../../song/data/song_mappers.dart';
import '../../song/domain/song.dart';

/// 聚合搜索结果：单曲为主体，歌单/歌手/专辑为可选分区。
class SearchBundle {
  const SearchBundle({
    this.songs = const <Song>[],
    this.playlists = const <Playlist>[],
    this.artists = const <Artist>[],
    this.albums = const <Album>[],
    this.partitionsAvailable = false,
    this.partitionsFailed = false,
  });

  final List<Song> songs;
  final List<Playlist> playlists;
  final List<Artist> artists;
  final List<Album> albums;

  /// 分区（歌单/歌手/专辑）是否拿到真实数据。
  ///
  /// 实测 `/search/complex` 会按 `type` 分组返回 `song` / `mv` / `collect`
  /// （歌单）/ `album` / `author` 等分组，分区数据可正常解析；只有当该接口
  /// 请求失败（[partitionsFailed] 为 true）或关键词本身没有分类结果时
  /// 这里才会是 false。
  final bool partitionsAvailable;

  /// 分区接口是否请求失败（只有真失败才提示降级，避免"没有专辑结果"
  /// 被误报成"分区接口不可用"）。
  final bool partitionsFailed;

  bool get isEmpty =>
      songs.isEmpty && playlists.isEmpty && artists.isEmpty && albums.isEmpty;
}

/// 搜索接口。
///
/// 路由策略（按实测结论，见 docs/API联调记录.md）：
/// - 主链路：`/search`（实测稳定返回 `data.lists` 歌曲数组，需带 dfid cookie）；
/// - 分区补充：`/search/complex`（实测恒 152），仅作锦上添花，失败静默降级；
/// - `/search/complex` 的 `data.lists` 是「分组数组」，每组的 `lists` 里才是
///   条目，这里两种形态都兼容（分组 / 平铺）。
class KugouSearchApi {
  KugouSearchApi(this._client);

  final KugouClient _client;

  /// 搜索入口：先取单曲（可靠），再尝试补分区（失败不影响单曲结果）。
  Future<SearchBundle> bundle(
    String keyword, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final String key = keyword.trim();
    if (key.isEmpty) {
      return const SearchBundle();
    }

    // 主链路失败时向上抛（页面展示失败 + 重试），不静默成空结果。
    final List<Song> songs = await searchSongs(
      key,
      page: page,
      pageSize: pageSize,
    );

    SearchBundle partitions = const SearchBundle();
    bool partitionsFailed = false;
    try {
      partitions = await complex(key, page: page, pageSize: pageSize);
    } on Object {
      // 分区接口不可用（152 / 解析异常 / 超时）：降级为只有单曲并标记失败。
      partitions = const SearchBundle();
      partitionsFailed = true;
    }

    return SearchBundle(
      songs: _dedupe(<Song>[...songs, ...partitions.songs]),
      playlists: partitions.playlists,
      artists: partitions.artists,
      albums: partitions.albums,
      partitionsAvailable:
          partitions.playlists.isNotEmpty ||
          partitions.artists.isNotEmpty ||
          partitions.albums.isNotEmpty,
      partitionsFailed: partitionsFailed,
    );
  }

  /// 单曲搜索（`/search`），实测最稳定的搜索入口。
  Future<List<Song>> searchSongs(
    String keyword, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final String key = keyword.trim();
    if (key.isEmpty) {
      return const <Song>[];
    }
    final Map<String, dynamic> json = await _client.getJson(
      '/search',
      query: <String, dynamic>{
        'keywords': key,
        'page': page,
        'pagesize': pageSize,
      },
    );
    final Map<String, dynamic>? data = JsonUtils.asMap(json['data']);
    if (data == null) {
      return const <Song>[];
    }
    return SongMappers.listFrom(data['lists'], dedupe: true);
  }

  /// 聚合搜索（`/search/complex`）：兼容分组与平铺两种返回形态。
  ///
  /// 服务端把每类结果包在 `{type: 'song', lists: [...]}` 里，也见过把条目
  /// 直接平铺到 `data.lists` 的版本，两种都按 `type` 分发。
  Future<SearchBundle> complex(
    String keyword, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final String key = keyword.trim();
    if (key.isEmpty) {
      return const SearchBundle();
    }
    final Map<String, dynamic> json = await _client.getJson(
      '/search/complex',
      query: <String, dynamic>{
        'keywords': key,
        'page': page,
        'pagesize': pageSize,
      },
    );
    final Map<String, dynamic>? data = JsonUtils.asMap(json['data']);
    if (data == null) {
      return const SearchBundle();
    }

    final List<Song> songs = <Song>[];
    final List<Playlist> playlists = <Playlist>[];
    final List<Artist> artists = <Artist>[];
    final List<Album> albums = <Album>[];

    for (final Map<String, dynamic> group in JsonUtils.asMapList(
      data['lists'],
    )) {
      final String type = JsonUtils.str(
        JsonUtils.pick(group, const <String>['type']),
      ).toLowerCase();
      final List<Map<String, dynamic>> items = JsonUtils.asMapList(
        group['lists'],
      );
      if (items.isNotEmpty) {
        for (final Map<String, dynamic> item in items) {
          _dispatchByType(type, item, songs, playlists, artists, albums);
        }
        continue;
      }
      // 平铺形态：条目本身就是结果。
      _dispatchByType(type, group, songs, playlists, artists, albums);
    }

    return SearchBundle(
      songs: _dedupe(songs),
      playlists: playlists,
      artists: artists,
      albums: albums,
      partitionsAvailable:
          playlists.isNotEmpty || artists.isNotEmpty || albums.isNotEmpty,
    );
  }

  /// 热搜关键词（默认展示在搜索页空态）。
  ///
  /// 实测真实结构：`data.list` 是**分组**数组，形如
  /// `[{ name: '热搜榜', keywords: [{ keyword: '慌啥子嘛', reason: '...' }, ...] }]`。
  /// 早期实现把 `keywords` 当成字符串键去 pick，`List.toString()` 会把整个
  /// 数组摊成一串 JSON 样文本，于是热搜榜每一项都渲染成长长的一行 `[{...}]`。
  /// 正确做法是展开分组内层数组，逐个取 `keyword`。
  Future<List<String>> hotKeywords() async {
    final Map<String, dynamic> json = await _client.getJson(
      '/search/hot/detail',
    );
    final Map<String, dynamic>? data = JsonUtils.asMap(json['data']);
    final Object? raw = data?['list'] ?? json['list'];
    return parseHotKeywords(raw);
  }

  /// 解析热搜分组数组 → 纯关键词列表（纯函数，便于单测/回归）。
  static List<String> parseHotKeywords(Object? raw) {
    final List<String> keywords = <String>[];
    if (raw is! List) {
      return keywords;
    }
    for (final Object? node in raw) {
      // 兜底：个别接口直接回纯字符串数组。
      if (node is String) {
        _addKeyword(<String, dynamic>{'keyword': node}, keywords);
        continue;
      }
      final Map<String, dynamic>? group = JsonUtils.asMap(node);
      if (group == null) {
        continue;
      }
      final List<Map<String, dynamic>> nested = JsonUtils.asMapList(
        group['keywords'],
      );
      if (nested.isNotEmpty) {
        for (final Map<String, dynamic> item in nested) {
          _addKeyword(item, keywords);
        }
        continue;
      }
      _addKeyword(group, keywords);
    }
    return keywords;
  }

  /// 从单条热搜项取关键词，注意**不要**再 pick `keywords`（那是数组）。
  static void _addKeyword(Map<String, dynamic> item, List<String> out) {
    final String word = JsonUtils.str(
      JsonUtils.pick(item, const <String>['keyword', 'word', 'name', 'reason']),
    );
    if (word.isNotEmpty && !out.contains(word)) {
      out.add(word);
    }
  }

  /// 搜索联想（`/search/suggest`），供搜索框自动补全使用。
  ///
  /// 实测真实结构：`data` 是**分组数组**，每组形如
  /// `{ LableName: '', RecordCount: 10, RecordDatas: [{ HintInfo: '周杰伦 晴天', ... }] }`，
  /// 其中 `LableName` 为空的一桶是纯关键词联想，后面还有 `MV` / `专辑` 等分桶。
  /// 自动补全只取纯关键词桶，取不到再退回全部分桶，避免联想列表里混进
  /// 「歌手 - 歌名」这种带分隔符的条目。
  Future<List<String>> suggest(String keyword, {int limit = 10}) async {
    final String key = keyword.trim();
    if (key.isEmpty || limit <= 0) {
      return const <String>[];
    }
    final Map<String, dynamic> json = await _client.getJson(
      '/search/suggest',
      query: <String, dynamic>{'keywords': key},
    );
    return parseSuggest(json['data'], limit: limit);
  }

  /// 解析联想分组数组 → 去重后的关键词列表（纯函数，便于单测/回归）。
  static List<String> parseSuggest(Object? raw, {int limit = 10}) {
    if (raw is! List || limit <= 0) {
      return const <String>[];
    }

    final List<String> primary = <String>[];
    final List<String> fallback = <String>[];

    for (final Object? node in raw) {
      final Map<String, dynamic>? group = JsonUtils.asMap(node);
      if (group == null) {
        continue;
      }
      final bool isPrimary = JsonUtils.str(group['LableName']).trim().isEmpty;
      final List<String> bucket = isPrimary ? primary : fallback;
      for (final Map<String, dynamic> item in JsonUtils.asMapList(
        group['RecordDatas'],
      )) {
        final String word = JsonUtils.str(
          JsonUtils.pick(item, const <String>[
            'HintInfo',
            'hint_info',
            'keyword',
          ]),
        ).trim();
        if (word.isNotEmpty && !bucket.contains(word)) {
          bucket.add(word);
        }
      }
    }

    final List<String> merged = <String>[];
    for (final String word in <String>[...primary, ...fallback]) {
      if (merged.length >= limit) {
        break;
      }
      if (!merged.contains(word)) {
        merged.add(word);
      }
    }
    return merged;
  }

  void _dispatchByType(
    String type,
    Map<String, dynamic> item,
    List<Song> songs,
    List<Playlist> playlists,
    List<Artist> artists,
    List<Album> albums,
  ) {
    switch (type) {
      case 'song':
      case 'audio':
      case 'audios':
      case 'ksong':
        final Song? song = SongMappers.fromJson(item);
        if (song != null) {
          songs.add(song);
        }
      case 'collect':
      case 'playlist':
      case 'special':
        final Playlist? playlist = Playlist.fromJson(item);
        if (playlist != null) {
          playlists.add(playlist);
        }
      case 'author':
      case 'singer':
      case 'artist':
        final Artist? artist = Artist.fromJson(item);
        if (artist != null) {
          artists.add(artist);
        }
      case 'album':
        final Album? album = Album.fromJson(item);
        if (album != null) {
          albums.add(album);
        }
      default:
        _dispatchByShape(item, songs, playlists, artists, albums);
    }
  }

  void _dispatchByShape(
    Map<String, dynamic> item,
    List<Song> songs,
    List<Playlist> playlists,
    List<Artist> artists,
    List<Album> albums,
  ) {
    final bool hasSong =
        JsonUtils.pick(item, const <String>['FileHash', 'hash']) != null;
    if (hasSong) {
      final Song? song = SongMappers.fromJson(item);
      if (song != null) {
        songs.add(song);
      }
      return;
    }
    if (JsonUtils.pick(item, const <String>['AuthorId', 'author_id']) != null) {
      final Artist? artist = Artist.fromJson(item);
      if (artist != null) {
        artists.add(artist);
      }
      return;
    }
    if (JsonUtils.pick(item, const <String>['albumid', 'album_id']) != null) {
      final Album? album = Album.fromJson(item);
      if (album != null) {
        albums.add(album);
      }
      return;
    }
    final Playlist? playlist = Playlist.fromJson(item);
    if (playlist != null) {
      playlists.add(playlist);
    }
  }

  /// 单曲去重：两个接口可能有交集，按 hash 去重保序。
  List<Song> _dedupe(List<Song> songs) {
    final Set<String> seen = <String>{};
    final List<Song> result = <Song>[];
    for (final Song song in songs) {
      if (song.hash.isNotEmpty && !seen.add(song.hash)) {
        continue;
      }
      result.add(song);
    }
    return result;
  }
}
