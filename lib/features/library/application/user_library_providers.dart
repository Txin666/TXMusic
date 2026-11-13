import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/kugou_client.dart';
import '../../../core/network/kugou_providers.dart';
import '../../album/domain/album.dart';
import '../../playlist/domain/playlist.dart';
import '../../song/domain/song.dart';
import '../data/kugou_library_api.dart';
import '../domain/my_music_library.dart';

/// 「我的音乐」接口数据：一次加载 4 个分区的用户维度内容。
///
/// 设计要点：
/// - **分区降级**：每一栏独立 try/catch，某个接口失败只影响它自己那一栏，
///   不会把整页打成错误态（云歌单接口对部分账号会返回空或被上游拒绝）；
/// - **未登录直接短路**：没登录时 cloudlist 只会返回 502，没必要发请求；
/// - **最近播放不在这里**：仍由 [libraryProvider] 从本机 JSON 提供。
final FutureProvider<MyMusicLibrary> myMusicLibraryProvider =
    FutureProvider<MyMusicLibrary>((Ref ref) async {
      final bool isLoggedIn = ref.watch(kugouSessionProvider).isLoggedIn;
      if (!isLoggedIn) {
        return MyMusicLibrary.empty;
      }

      final KugouLibraryApi api = ref.watch(kugouLibraryApiProvider);
      List<Playlist> created = const <Playlist>[];
      List<Playlist> collected = const <Playlist>[];
      String? playlistsError;

      // 1) 歌单：我创建 + 我收藏（一次请求，按创建者拆分）。
      try {
        final ({List<Playlist> created, List<Playlist> collected}) bundle =
            await api.playlists();
        created = bundle.created;
        collected = bundle.collected;
      } on Object catch (error) {
        created = const <Playlist>[];
        collected = const <Playlist>[];
        playlistsError = describeLibraryError(error);
      }

      // 2) 收藏 / 已购专辑。
      List<Album> albums;
      String? albumsError;
      try {
        albums = await api.purchasedAlbums();
      } on Object catch (error) {
        albums = const <Album>[];
        albumsError = describeLibraryError(error);
      }

      // 3) 我的喜欢：复用「我喜欢」歌单的曲目接口。
      List<Song> liked = const <Song>[];
      String? likedError;
      final Playlist? likedPlaylist = KugouLibraryApi.findLikedPlaylist(
        <Playlist>[...created, ...collected],
      );
      if (likedPlaylist == null) {
        // 账号本来就没有「我喜欢」歌单（新账号 / 从未收藏）属于正常空态，
        // 不是错误：likedError 保持 null，由页面用中性文案回落到本机收藏。
        // 歌单整体失败时已经由 playlistsError 说明原因，也不重复提示。
        likedError = null;
      } else if (!likedPlaylist.hasCollectionId) {
        likedError = '「我喜欢」歌单缺少 collection id，无法拉取曲目';
      } else {
        try {
          // fetchAll：上游分页，330 首的「我喜欢」只拉第一页会只剩 100 首。
          liked = await ref
              .watch(kugouPlaylistApiProvider)
              .songs(likedPlaylist.id, fetchAll: true);
        } on Object catch (error) {
          liked = const <Song>[];
          likedError = describeLibraryError(error);
        }
      }

      return MyMusicLibrary(
        createdPlaylists: created,
        collectedPlaylists: collected,
        likedSongs: liked,
        albums: albums,
        playlistsError: playlistsError,
        likedError: likedError,
        albumsError: albumsError,
        isLoggedIn: true,
      );
    });

/// 把接口异常翻译成能直接显示给用户的一句话。
///
/// 云歌单相关错误码（30227 / 20006 / 20010）光看数字没人看得懂，这里统一
/// 改写成可行动的描述。**注意归因**：实测同一登录态下，有歌单数据的账号
/// `/user/playlist` 正常返回 200，只有无云歌单数据的账号才会被上游拒绝，
/// 所以这组错误码不能断言成"概念版登录态不支持"，只能说上游拒绝了本次读取。
String describeLibraryError(Object error) {
  if (error is KugouApiException) {
    switch (error.code) {
      case 30227:
        return '上游拒绝读取云歌单（30227）：账号可能没有云歌单数据，或当前登录态无权访问';
      case 20006:
        return '云歌单加密参数被拒绝（20006）：请重新登录后再试';
      case 20010:
        return '云歌单接口返回参数错误（20010）：请重新登录后再试';
      default:
        return error.message;
    }
  }
  return '$error';
}
