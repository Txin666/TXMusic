// Flutter 内部也有同名 RepeatMode，隐藏掉避免歧义。
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:txmusic/features/player/application/player_controller.dart';
import 'package:txmusic/features/player/data/playback_archive.dart';
import 'package:txmusic/features/player/domain/playback_state.dart';
import 'package:txmusic/features/song/domain/song.dart';
import 'package:txmusic/main.dart';

import '../helpers/test_app_harness.dart';

/// 续播链路：本地存档 → 启动恢复 → 进度推进 → 退出前落盘。
///
/// 全程使用内存版 [PlaybackArchiveStorage] 与假音频引擎，
/// 不读写 `.local/`、不解析真实音源、不发网络请求。
void main() {
  PlaybackArchive buildArchive({
    Duration position = const Duration(seconds: 42),
  }) {
    return PlaybackArchive(
      song: kTestSongs.first,
      queue: kTestSongs,
      queueIndex: 0,
      position: position,
      duration: kTestSongs.first.duration,
      volume: 0.5,
      repeatMode: RepeatMode.one,
    );
  }

  Future<ProviderContainer> pumpWithArchive(
    WidgetTester tester,
    FakePlaybackArchiveStorage storage, {
    FakeAudioEngine? engine,
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: buildTestOverrides(engine: engine, archiveStorage: storage),
        child: const TxMusicApp(),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(TxMusicApp)));
  }

  testWidgets('启动时读本地存档，恢复到上次的曲目与进度', (WidgetTester tester) async {
    final FakePlaybackArchiveStorage storage = FakePlaybackArchiveStorage(
      buildArchive(),
    );

    final ProviderContainer container = await pumpWithArchive(tester, storage);
    final PlaybackSnapshot state = container.read(playerControllerProvider);

    expect(state.currentSong?.hash, kTestSongs.first.hash);
    expect(state.position, const Duration(seconds: 42));
    expect(state.queue.length, kTestSongs.length);
    // 恢复态是暂停：不自动加载音源，等用户点播放再续上。
    expect(state.status, PlaybackStatus.paused);
    expect(state.volume, closeTo(0.5, 1e-9));
    expect(state.repeatMode, RepeatMode.one);
  });

  testWidgets('没有存档时保持空态，不显示上次播放', (WidgetTester tester) async {
    final ProviderContainer container = await pumpWithArchive(
      tester,
      FakePlaybackArchiveStorage(),
    );

    final PlaybackSnapshot state = container.read(playerControllerProvider);
    expect(state.currentSong, isNull);
    expect(state.hasSong, isFalse);
    expect(find.text('暂无播放'), findsOneWidget);
  });

  testWidgets('拖动进度后退出，最新进度被写回存档', (WidgetTester tester) async {
    final FakePlaybackArchiveStorage storage = FakePlaybackArchiveStorage(
      buildArchive(),
    );
    final FakeAudioEngine engine = FakeAudioEngine();
    final ProviderContainer container = await pumpWithArchive(
      tester,
      storage,
      engine: engine,
    );

    final PlayerController controller = container.read(
      playerControllerProvider.notifier,
    );
    // 恢复态未加载音源：拖动进度只记目标位置，同时立即落盘。
    controller.seek(const Duration(seconds: 100));
    await tester.pumpAndSettle();

    final PlaybackArchive? saved = storage.archive;
    expect(saved, isNotNull);
    expect(saved!.song.hash, kTestSongs.first.hash);
    expect(saved.position, const Duration(seconds: 100));
    expect(saved.queue.length, kTestSongs.length);
    // 未加载音源时不应该调用引擎 seek。
    expect(engine.lastSeek, isNull);
  });

  testWidgets('续播位置接近结尾时从头开始', (WidgetTester tester) async {
    final Song song = kTestSongs.first;
    final PlaybackArchive archive = buildArchive(
      position: song.duration - const Duration(seconds: 2),
    );
    expect(archive.resumePosition, Duration.zero);

    final ProviderContainer container = await pumpWithArchive(
      tester,
      FakePlaybackArchiveStorage(archive),
    );
    final PlaybackSnapshot state = container.read(playerControllerProvider);
    expect(state.currentSong?.hash, song.hash);
    expect(state.position, Duration.zero);
  });
}
