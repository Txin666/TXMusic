import '../../../core/network/json_utils.dart';
import '../../../core/network/kugou_client.dart';
import '../../album/domain/album.dart';
import '../../playlist/domain/playlist.dart';
import '../domain/my_music_library.dart';

/// 「我的音乐」用户维度接口集合。
///
/// 覆盖三个上游能力：
/// 1. 我创建 / 我收藏的歌单 —— `GET /user/playlist`（底层走 cloudlist
///    `/v7/get_all_list`，一次返回全部歌单，再按创建者拆成两栏）；
/// 2. 我收藏 / 已购的专辑 —— `GET /user/purchased/albums`；
/// 3. 我的喜欢 —— 复用「我喜欢」歌单的曲目（`/playlist/track/all`，
///    由 [KugouPlaylistApi] 完成，这里只负责把「我喜欢」歌单挑出来）。
///
/// 实测约束（见 docs/API联调记录.md）：cloudlist 系的 `/user/playlist` 与
/// `/user/purchased/albums` 对**有数据的账号可正常返回 200**；只有云歌单里
/// 确实没有内容（新账号、无收藏歌单）时才会返回空列表，或被上游拒绝
/// （`30227` / `20006` / `20010`）—— 这组错误码不能一概归因为"概念版登录态
/// 不支持"。因此这里**不吞异常**，而是把失败原样抛给 Provider，由 Provider
/// 做分区降级，保证「收藏专辑」成功时不受「歌单」失败牵连。
///
/// 另注：返回项里 `is_mine` 实测恒为 0，**不能**用它判断歌单归属，见
/// [_isOwnedBySelf]。
class KugouLibraryApi {
  KugouLibraryApi(this._client);

  final KugouClient _client;

  /// 当前登录用户 ID（拆「我创建 / 我收藏」时要用）。
  String get ownUserId => _client.session.userid;

  /// 我创建 + 我收藏的歌单。
  Future<({List<Playlist> created, List<Playlist> collected})>
  playlists() async {
    final Map<String, dynamic> json = await _client.getJson(
      '/user/playlist',
      query: <String, dynamic>{'page': 1, 'pagesize': 100},
    );
    final List<Map<String, dynamic>> raw = _extractList(json, const <String>[
      'list',
      'special_list',
      'info',
      'playlists',
      'data',
    ]);

    final List<Playlist> created = <Playlist>[];
    final List<Playlist> collected = <Playlist>[];
    for (final Map<String, dynamic> item in raw) {
      final Playlist? playlist = Playlist.fromJson(item);
      if (playlist == null) {
        continue;
      }
      if (_isOwnedBySelf(item)) {
        created.add(playlist);
      } else {
        collected.add(playlist);
      }
    }
    return (created: created, collected: collected);
  }

  /// 我收藏 / 已购的专辑。
  ///
  /// 接口在账号无购买记录时返回空 `data`（`total: 0`），这属于正常空态，
  /// 不是错误，返回空列表即可。
  Future<List<Album>> purchasedAlbums({int pageSize = 50}) async {
    final Map<String, dynamic> json = await _client.getJson(
      '/user/purchased/albums',
      query: <String, dynamic>{'page': 1, 'pagesize': pageSize},
    );
    final List<Map<String, dynamic>> raw = _extractList(json, const <String>[
      'albums',
      'album_list',
      'list',
      'info',
      'data',
    ]);
    return raw
        .map(Album.fromJson)
        .whereType<Album>()
        .toList(growable: false);
  }

  /// 从歌单列表里挑出「我喜欢」歌单（标题比较宽松，兼容不同版本命名）。
  static Playlist? findLikedPlaylist(Iterable<Playlist> playlists) {
    for (final Playlist playlist in playlists) {
      final String title = playlist.title.replaceAll(' ', '');
      if (title.contains('我喜欢') || title.contains('我喜歡')) {
        return playlist;
      }
    }
    return null;
  }

  /// 判断某个歌单是否为本账号创建。
  ///
  /// 优先用 `list_create_userid` 与当前 userid 比对（最可靠），拿不到时退回
  /// `type` 字段约定（0 = 自建，1 = 收藏），都没有则默认归入「我创建」，
  /// 避免歌单在页面上凭空消失。
  bool _isOwnedBySelf(Map<String, dynamic> raw) {
    final String creator = JsonUtils.str(
      JsonUtils.pick(raw, const <String>[
        'list_create_userid',
        'create_userid',
        'create_user_id',
        'nickname_userid',
      ]),
    );
    final String own = ownUserId;
    if (creator.isNotEmpty && own.isNotEmpty) {
      return creator == own;
    }
    final Object? typeRaw = JsonUtils.pick(raw, const <String>[
      'type',
      'list_type',
      'collect_type',
    ]);
    if (typeRaw != null) {
      return JsonUtils.integer(typeRaw, fallback: 0) == 0;
    }
    return true;
  }

  /// 从响应里按候选键找出列表：先 `data` 层，再顶层，最后兜底 data 本身。
  static List<Map<String, dynamic>> _extractList(
    Map<String, dynamic> json,
    List<String> keys,
  ) {
    final Map<String, dynamic>? data = JsonUtils.asMap(json['data']);
    final List<Object?> candidates = <Object?>[
      for (final String key in keys) data?[key],
      for (final String key in keys) json[key],
      data,
      json['data'],
    ];
    for (final Object? candidate in candidates) {
      final List<Map<String, dynamic>> list = JsonUtils.asMapList(candidate);
      if (list.isNotEmpty) {
        return list;
      }
    }
    return const <Map<String, dynamic>>[];
  }
}

/// 便捷方法：把 [MyMusicLibrary] 的构造交给 Provider 层组合，这里只提供 id 校验。
extension PlaylistOwnerHint on Playlist {
  /// 该歌单能否打开详情（需要 `global_collection_id`）。
  bool get canOpenDetail => hasCollectionId;
}
