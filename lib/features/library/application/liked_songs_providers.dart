import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/kugou_client.dart';
import '../../../core/network/kugou_providers.dart';
import '../../song/domain/song.dart';
import '../data/kugou_collect_api.dart';
import 'user_library_providers.dart';

/// 「我喜欢」收藏接口。
final Provider<KugouCollectApi> kugouCollectApiProvider =
    Provider<KugouCollectApi>(
      (Ref ref) => KugouCollectApi(ref.watch(kugouClientProvider)),
    );

/// 「我喜欢」收藏状态：服务器为准，本地只做乐观更新的镜像。
///
/// 设计要点：
/// - 状态从服务器的「我喜欢」全量列表构建（含 `hash → fileid`），
///   所以播放页、列表页看到的"是否已收藏"与服务器一致；
/// - [toggle] 先改本地镜像让按钮立即响应，再打写接口，成功后静默回拉
///   服务器列表把 `fileid` / `count` 校准，失败则回滚并抛错给 UI；
/// - 写入成功后 invalidate [myMusicLibraryProvider]，「我的音乐 → 我喜欢」
///   无需手动下拉即可看到新收藏（双向同步）。
class LikedSongsController extends Notifier<AsyncValue<LikedSongsSnapshot>> {
  @override
  AsyncValue<LikedSongsSnapshot> build() {
    final bool loggedIn = ref.watch(kugouSessionProvider).isLoggedIn;
    if (!loggedIn) {
      return const AsyncData<LikedSongsSnapshot>(LikedSongsSnapshot.empty);
    }
    Future<void>.microtask(refresh);
    return const AsyncLoading<LikedSongsSnapshot>();
  }

  KugouCollectApi get _api => ref.read(kugouCollectApiProvider);

  /// 重新从服务器拉取「我喜欢」。
  Future<void> refresh() async {
    if (!ref.read(kugouSessionProvider).isLoggedIn) {
      state = const AsyncData<LikedSongsSnapshot>(LikedSongsSnapshot.empty);
      return;
    }
    final AsyncValue<LikedSongsSnapshot> next = await AsyncValue.guard(
      () => _api.likedSongs(),
    );
    state = next;
  }

  /// 收藏 / 取消收藏；返回操作后的收藏状态（true = 已收藏）。
  ///
  /// 未登录、缺少 hash、取不到 fileid 都会抛 [KugouApiException]，
  /// 由调用方提示用户。
  Future<bool> toggle(Song song) async {
    if (!ref.read(kugouSessionProvider).isLoggedIn) {
      throw const KugouApiException('未登录，收藏不会同步到服务器');
    }
    if (song.hash.isEmpty) {
      throw const KugouApiException('这首歌缺少 hash，无法收藏');
    }

    // 首次点击时列表可能还在加载，先等它落地再判断"是否已收藏"。
    LikedSongsSnapshot snapshot = state.asData?.value ?? await _awaitSnapshot();

    if (snapshot.has(song.hash)) {
      int fileid = snapshot.fileidOf(song.hash) ?? 0;
      if (fileid <= 0) {
        // 刚收藏的歌本地没有 fileid，回拉一次服务器补上再删。
        snapshot = await _api.likedSongs();
        state = AsyncData<LikedSongsSnapshot>(snapshot);
        fileid = snapshot.fileidOf(song.hash) ?? 0;
      }
      await _api.removeFromLiked(hash: song.hash, fileid: fileid);
      state = AsyncData<LikedSongsSnapshot>(snapshot.minus(song.hash));
      _invalidateMusicLibrary();
      return false;
    }

    await _api.addToLiked(song);
    state = AsyncData<LikedSongsSnapshot>(snapshot.plus(song));
    _invalidateMusicLibrary();
    // 后台校准 fileid / 真实 count，失败不影响本次结果。
    Future<void>.microtask(_refreshQuietly);
    return true;
  }

  Future<LikedSongsSnapshot> _awaitSnapshot() async {
    try {
      final LikedSongsSnapshot snapshot = await _api.likedSongs();
      state = AsyncData<LikedSongsSnapshot>(snapshot);
      return snapshot;
    } on KugouApiException {
      // 拉不到列表时不阻断操作：按"未收藏"处理，交给写接口判定。
      const LikedSongsSnapshot fallback = LikedSongsSnapshot.empty;
      state = const AsyncData<LikedSongsSnapshot>(fallback);
      return fallback;
    }
  }

  Future<void> _refreshQuietly() async {
    try {
      final LikedSongsSnapshot fresh = await _api.likedSongs();
      state = AsyncData<LikedSongsSnapshot>(fresh);
      _invalidateMusicLibrary();
    } on Object {
      // 静默：本地乐观结果已经生效，回拉失败留给下次刷新。
    }
  }

  void _invalidateMusicLibrary() {
    ref.invalidate(myMusicLibraryProvider);
  }
}

/// 「我喜欢」收藏状态（服务器同步）。
final NotifierProvider<LikedSongsController, AsyncValue<LikedSongsSnapshot>>
likedSongsProvider =
    NotifierProvider<LikedSongsController, AsyncValue<LikedSongsSnapshot>>(
      LikedSongsController.new,
    );
