import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:txmusic/core/network/kugou_providers.dart';
import 'package:txmusic/core/network/kugou_session.dart';
import 'package:txmusic/features/library/application/library_providers.dart';
import 'package:txmusic/features/library/application/liked_songs_providers.dart';
import 'package:txmusic/features/library/data/kugou_collect_api.dart';
import 'package:txmusic/features/song/domain/song.dart';

import '../helpers/test_app_harness.dart';

/// 已登录会话（isFavoriteProvider 只有在登录态才以服务器为准）。
const KugouSession _loggedIn = KugouSession(
  cookie: 'userid=1;token=t',
  userid: '1',
  token: 't',
  nickname: 'tester',
);

const Song _song = Song(
  id: 'song-1',
  title: '晴天',
  artist: '周杰伦',
  album: '叶惠美',
  albumId: 'album-1',
  duration: Duration(minutes: 4, seconds: 29),
  hash: 'hash-1',
);

LikedSongsSnapshot _remote({required bool liked}) => LikedSongsSnapshot(
  songs: liked ? const <Song>[_song] : const <Song>[],
  fileids: liked ? const <String, int>{'hash-1': 1} : const <String, int>{},
);

/// 本机镜像里仍残留 hash-1（模拟「取消收藏后本机 favorites.json 未及时清掉」）。
class _StaleLocalLibrary extends FakeLibraryController {
  @override
  LibraryState build() => const LibraryState(
    favorites: <Song>[_song],
    isLoading: false,
  );
}

class _FakeLikedController extends LikedSongsController {
  @override
  AsyncValue<LikedSongsSnapshot> build() =>
      AsyncData(_remote(liked: true));

  void setLiked(bool liked) {
    state = AsyncData(_remote(liked: liked));
  }
}

void main() {
  test('播放页取消收藏后，迷你播放条依赖的收藏态立刻变未收藏', () {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        kugouSessionProvider.overrideWith(
          () => KugouSessionController(_loggedIn),
        ),
        libraryProvider.overrideWith(_StaleLocalLibrary.new),
        likedSongsProvider.overrideWith(_FakeLikedController.new),
      ],
    );
    addTearDown(container.dispose);

    // 保持订阅，避免普通 Provider 读完即回收。
    container.listen(isFavoriteProvider, (_, _) {}, fireImmediately: true);

    expect(container.read(isFavoriteProvider)('hash-1'), isTrue);

    (container.read(likedSongsProvider.notifier) as _FakeLikedController).setLiked(false);

    // 服务器已取消 → 各处心形必须跟着变；本机镜像残留不能反过来压过服务器。
    expect(container.read(isFavoriteProvider)('hash-1'), isFalse);
    // 本机镜像本身没被清（说明判定确实走的是服务器，而不是本地被清空）。
    expect(container.read(libraryProvider).isFavorite('hash-1'), isTrue);
  });

  test('服务器列表尚未返回时用本机镜像兜底，不闪未收藏', () {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        kugouSessionProvider.overrideWith(
          () => KugouSessionController(_loggedIn),
        ),
        libraryProvider.overrideWith(_StaleLocalLibrary.new),
        likedSongsProvider.overrideWith(() => _LoadingLikedController()),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(isFavoriteProvider)('hash-1'), isTrue);
  });
}

class _LoadingLikedController extends LikedSongsController {
  @override
  AsyncValue<LikedSongsSnapshot> build() => const AsyncLoading();
}
