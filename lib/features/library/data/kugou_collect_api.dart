import 'package:flutter/foundation.dart';

import '../../../core/diagnostics/boot_log.dart';
import '../../../core/network/json_utils.dart';
import '../../../core/network/kugou_client.dart';
import '../../song/data/song_mappers.dart';
import '../../song/domain/song.dart';

/// 「我喜欢」收藏接口（cloudlist 服务）。
///
/// 实测结论（详见 docs/API联调记录.md）：
/// - 「我喜欢」在 cloudlist 里就是 **listid = 2**，其
///   `global_collection_id` 形如 `collection_3_<userid>_2_0`，
///   所以不必先调 `/user/playlist`（该接口对部分账号会 30227）就能定位；
/// - 收藏：`GET /playlist/tracks/add?listid=2&data=<歌名>|<hash>|<albumid>|<mixsongid>`
///   —— 实测只有 `hash` 是必需的，`albumid` / `mixsongid` 传 0 也能成功，
///   歌名会被写进列表用于展示，因此仍按真实字段拼接；
/// - 取消：`GET /playlist/tracks/del?listid=2&fileids=<fileid>`
///   —— **必须传 fileid（数字）**，不是 hash，所以「已收藏」索引必须同时
///   记住 hash → fileid 的映射，否则取消收藏无从下手；
/// - 写入后 `count` 立即变化（330 → 331 → 330），说明写接口本身对当前
///   登录态可用，读侧没有延迟。
class KugouCollectApi {
  KugouCollectApi(this._client);

  final KugouClient _client;

  /// 「我喜欢」在 cloudlist 中的固定 listid。
  static const int likedListId = 2;

  /// 单页上限：与歌单曲目一致，300 首一页实测可用。
  static const int _pageSize = 300;

  /// 翻页保护上限（300 × 60 = 18000 首）。
  static const int _maxPages = 60;

  /// 当前登录用户的「我喜欢」`global_collection_id`；未登录返回空串。
  String get likedCollectionId {
    final String userid = _client.session.userid;
    if (userid.isEmpty) {
      return '';
    }
    return 'collection_3_${userid}_2_0';
  }

  /// 拉取「我喜欢」全量曲目，并顺带建立 `hash → fileid` 映射（取消收藏要用）。
  ///
  /// 未登录返回空快照；上游 502（账号无云歌单数据）也降级为空快照，
  /// 由 UI 按「空收藏」渲染，而不是把播放页打成错误态。
  Future<LikedSongsSnapshot> likedSongs() async {
    final String collectionId = likedCollectionId;
    if (collectionId.isEmpty) {
      return LikedSongsSnapshot.empty;
    }

    final List<Song> songs = <Song>[];
    final Map<String, int> fileids = <String, int>{};
    final Set<String> seen = <String>{};
    int total = 0;

    for (int page = 1; page <= _maxPages; page++) {
      final Map<String, dynamic>? data;
      try {
        final Map<String, dynamic> json = await _client.getJson(
          '/playlist/track/all',
          query: <String, dynamic>{
            'id': collectionId,
            'page': page,
            'pagesize': _pageSize,
          },
        );
        data = JsonUtils.asMap(json['data']);
      } on KugouApiException catch (error) {
        if (error.code == 502) {
          break;
        }
        rethrow;
      }
      if (data == null) {
        break;
      }

      total = JsonUtils.integer(data['count'], fallback: total);
      final List<Map<String, dynamic>> raw = JsonUtils.asMapList(
        data['songs'],
      );
      if (raw.isEmpty) {
        break;
      }
      for (final Map<String, dynamic> item in raw) {
        final Song? song = SongMappers.fromJson(item);
        if (song == null) {
          // 无 hash 的占位条目（版权 / 审核中）无法收藏，也无法取消，跳过。
          continue;
        }
        final int fileid = JsonUtils.integer(
          JsonUtils.pick(item, const <String>['fileid', 'file_id', 'FileId']),
        );
        if (fileid > 0) {
          fileids[song.hash] = fileid;
        }
        if (seen.add(song.hash)) {
          songs.add(song);
        }
      }
      if (total > 0 && page >= (total / _pageSize).ceil()) {
        break;
      }
    }

    return LikedSongsSnapshot(songs: songs, fileids: fileids, total: total);
  }

  /// 收藏到「我喜欢」。
  Future<void> addToLiked(Song song) async {
    if (song.hash.isEmpty) {
      throw const KugouApiException('这首歌缺少 hash，无法收藏');
    }
    final Map<String, dynamic> json = await _client.getJson(
      '/playlist/tracks/add',
      query: <String, dynamic>{
        'listid': likedListId,
        'data': _collectPayload(song),
      },
    );
    _ensureAcceptedWithRetry(json, '收藏', song.hash);
  }

  /// 收藏结果校验：`30227` 时回拉列表核验，避免把「已收藏」误报成失败。
  ///
  /// 30227 是酷狗写接口的拒绝码，实测至少在「该曲目已在『我喜欢』中」
  /// 与「登录态在本次请求里失效」两种情况下出现，光看码分不出来，
  /// 只能回拉一次列表确认；确认不在列表里再按登录态失效提示用户重登。
  Future<void> _ensureAcceptedWithRetry(
    Map<String, dynamic> json,
    String action,
    String hash,
  ) async {
    try {
      _ensureAccepted(json, action);
    } on KugouApiException catch (error) {
      if (error.code != 30227) {
        rethrow;
      }
      if (await _isAlreadyLiked(hash)) {
        return;
      }
      // 走到这里说明写接口确实被拒、且列表里也没有这首：多半是登录态失效。
      // 把登录态关键信息（不含 token 明文）落进启动日志，方便在别的机器上定位。
      bootLog(
        '[收藏] 30227 被拒 action=$action hash=$hash '
        'loggedIn=${_client.session.isLoggedIn} '
        'useridTail=${_tail(_client.session.userid)} '
        'tokenLen=${_client.session.token.length} '
        'dfidLen=${_client.session.dfid.length} raw=$json',
      );
      throw KugouApiException(
        '$action被拒绝（30227）：请重新登录酷狗账号后再试'
        '（诊断：${_client.session.isLoggedIn ? '已登录，userid 尾号 ${_tail(_client.session.userid)}' : '当前未登录'}）',
        path: error.path,
        code: error.code,
      );
    }
  }

  /// 回拉「我喜欢」列表判断该 hash 是否已在其中；拉取失败按「不在」处理。
  Future<bool> _isAlreadyLiked(String hash) async {
    if (hash.isEmpty) {
      return false;
    }
    try {
      final LikedSongsSnapshot snapshot = await likedSongs();
      return snapshot.has(hash);
    } on Object {
      return false;
    }
  }

  /// 从「我喜欢」取消收藏（`fileid` 来自 [likedSongs] 的映射）。
  Future<void> removeFromLiked({required String hash, required int fileid}) async {
    if (fileid <= 0) {
      throw const KugouApiException('这首歌在「我喜欢」里取不到 fileid，请刷新后再取消');
    }
    final Map<String, dynamic> json = await _client.getJson(
      '/playlist/tracks/del',
      query: <String, dynamic>{
        'listid': likedListId,
        'fileids': '$fileid',
      },
    );
    _ensureAccepted(json, '取消收藏');
  }

  /// 收藏/取消的 data 格式：`歌名|hash|albumid|mixsongid`。
  ///
  /// 歌名里的竖线会破坏分隔，先替换掉；albumid / mixsongid 取不到数字时
  /// 传 0（实测可用）。
  static String _collectPayload(Song song) {
    final String name = song.title.replaceAll('|', ' ').trim();
    final String albumId = _digits(song.albumId);
    final String mixSongId = _digits(song.id);
    return '${name.isEmpty ? '未知歌曲' : name}|${song.hash}|'
        '${albumId.isEmpty ? '0' : albumId}|'
        '${mixSongId.isEmpty ? '0' : mixSongId}';
  }

  /// userid 尾号：只在日志/提示里区分账号，避免把完整 id 摊到界面上。
  static String _tail(String value) {
    if (value.isEmpty) {
      return '空';
    }
    return value.length <= 4 ? value : value.substring(value.length - 4);
  }

  static String _digits(String value) {
    final String trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    return int.tryParse(trimmed) == null ? '' : trimmed;
  }

  /// 写接口成功时 `data.status == 1`；顶层 `status == 0` 会先被
  /// [KugouClient] 的错误码收敛拦下，这里只兜「200 但业务未成功」的情况。
  static void _ensureAccepted(Map<String, dynamic> json, String action) {
    final Map<String, dynamic>? data = JsonUtils.asMap(json['data']);
    final Object? status = data?['status'] ?? json['status'];
    if (status == null) {
      return;
    }
    if (JsonUtils.integer(status, fallback: 1) != 1) {
      throw KugouApiException('$action失败（status=$status）');
    }
  }
}

/// 「我喜欢」快照：曲目列表 + `hash → fileid` 映射。
@immutable
class LikedSongsSnapshot {
  const LikedSongsSnapshot({
    required this.songs,
    required this.fileids,
    this.total = 0,
  });

  static const LikedSongsSnapshot empty = LikedSongsSnapshot(
    songs: <Song>[],
    fileids: <String, int>{},
  );

  final List<Song> songs;

  /// `hash → fileid`：取消收藏只需 fileid，必须和曲目一起缓存。
  final Map<String, int> fileids;

  /// 上游 `data.count`（真实收藏总数，含无 hash 的占位条目）。
  final int total;

  bool has(String hash) => hash.isNotEmpty && fileids.containsKey(hash);

  int? fileidOf(String hash) => fileids[hash];

  LikedSongsSnapshot plus(Song song) {
    return LikedSongsSnapshot(
      songs: <Song>[song, ...songs.where((Song item) => item.hash != song.hash)],
      // 新增时还没有 fileid，等后台刷新补齐；这里先占位 -1 让 has() 立即为真。
      fileids: <String, int>{...fileids, song.hash: fileids[song.hash] ?? -1},
      total: total + 1,
    );
  }

  LikedSongsSnapshot minus(String hash) {
    return LikedSongsSnapshot(
      songs: songs.where((Song item) => item.hash != hash).toList(),
      fileids: <String, int>{...fileids}..remove(hash),
      total: total > 0 ? total - 1 : 0,
    );
  }
}
