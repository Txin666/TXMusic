import '../../../core/network/json_utils.dart';

/// 领域实体：歌单（推荐歌单 / 搜索结果 / 歌单详情共用）。
class Playlist {
  const Playlist({
    required this.id,
    required this.title,
    this.creator = '',
    this.description = '',
    this.playCount = 0,
    this.trackCount = 0,
    this.coverUrl,
    this.tags = const <String>[],
    this.updateTime = '',
    this.songIds = const <String>[],
  });

  /// 歌单 ID：优先 `global_collection_id`（详情/曲目接口要用它）。
  final String id;
  final String title;
  final String creator;
  final String description;
  final int playCount;

  /// 接口给的曲目总数（详情页未拉全曲目时用它展示）。
  final int trackCount;
  final String? coverUrl;
  final List<String> tags;
  final String updateTime;

  /// 已加载的曲目 ID（详情页使用，可以为空）。
  final List<String> songIds;

  int get songCount => trackCount > 0 ? trackCount : songIds.length;

  /// 可用于 `/playlist/detail` 与 `/playlist/track/all` 的 ID。
  ///
  /// 实测这两个接口只认 `global_collection_id`（`collection_x_y_z`），传
  /// `specialid` 会拿到空数据或 HTTP 502，所以拿不到时返回空串，由上层
  /// 降级为"该歌单暂不支持查看"。
  String get collectionId => id.startsWith('collection_') ? id : '';

  bool get hasCollectionId => collectionId.isNotEmpty;

  /// 各接口字段差异较大，这里统一收敛。
  static Playlist? fromJson(Map<String, dynamic> json) {
    final String id = JsonUtils.str(
      JsonUtils.pick(json, const <String>[
        'global_collection_id',
        'gid',
        'specialid',
        'special_id',
        'listid',
        'id',
      ]),
    );
    if (id.isEmpty) {
      return null;
    }
    final String title = JsonUtils.str(
      JsonUtils.pick(json, const <String>[
        'specialname',
        'special_name',
        'name',
        'title',
        'listname',
      ]),
      fallback: '未命名歌单',
    );
    return Playlist(
      id: id,
      title: title,
      creator: JsonUtils.str(
        JsonUtils.pick(json, const <String>[
          'nickname',
          'username',
          'list_create_username',
        ]),
      ),
      description: JsonUtils.str(
        JsonUtils.pick(json, const <String>[
          'intro',
          'description',
          'list_create_listen_count',
        ]),
      ),
      playCount: JsonUtils.integer(
        JsonUtils.pick(json, const <String>[
          'play_count',
          'playcount',
          'total_play_count',
        ]),
      ),
      trackCount: JsonUtils.integer(
        JsonUtils.pick(json, const <String>[
          'song_count',
          'count',
          'songcount',
          'percount',
        ]),
      ),
      coverUrl: JsonUtils.cover(
        JsonUtils.pick(json, const <String>['img', 'imgurl', 'pic', 'cover']),
        size: 480,
      ),
      tags: _tags(json),
      updateTime: JsonUtils.str(
        JsonUtils.pick(json, const <String>[
          'update_time',
          'publishtime',
          'publish_time',
        ]),
      ),
    );
  }

  static List<String> _tags(Map<String, dynamic> json) {
    final Object? raw = json['tags'];
    if (raw is List) {
      final List<String> tags = <String>[];
      for (final Map<String, dynamic> tag in JsonUtils.asMapList(raw)) {
        final String name = JsonUtils.str(
          JsonUtils.pick(tag, const <String>['tag_name', 'name']),
        );
        if (name.isNotEmpty) {
          tags.add(name);
        }
      }
      return tags;
    }
    final String flat = JsonUtils.str(raw);
    if (flat.isEmpty) {
      return const <String>[];
    }
    return flat
        .split(',')
        .map((String item) => item.trim())
        .where((String item) => item.isNotEmpty)
        .toList();
  }
}
