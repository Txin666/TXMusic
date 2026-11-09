import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:txmusic/core/network/kugou_providers.dart';
import 'package:txmusic/features/discover/application/discover_providers.dart';
import 'package:txmusic/features/shell/presentation/main_shell.dart';
import 'package:txmusic/main.dart';
import 'package:txmusic/routing/app_routes.dart';
import 'package:txmusic/routing/app_router.dart';

import 'helpers/test_app_harness.dart';

Future<FakeAudioEngine> _pumpApp(WidgetTester tester) async {
  // 桌面窗口尺寸下校验布局，避免测试默认 800x600 造成窄屏折叠差异。
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final FakeAudioEngine engine = FakeAudioEngine();
  await tester.pumpWidget(
    ProviderScope(
      overrides: buildTestOverrides(engine: engine),
      child: const TxMusicApp(),
    ),
  );
  await tester.pumpAndSettle();
  return engine;
}

void main() {
  testWidgets('启动后渲染主框架（侧边导航 + 搜索栏 + 播放条）', (WidgetTester tester) async {
    await _pumpApp(tester);

    expect(find.byType(MainShell), findsOneWidget);
    expect(find.text('TX MUSIC'), findsOneWidget);
    expect(find.text('发现'), findsWidgets);
    expect(find.text('暂无播放'), findsOneWidget);
  });

  testWidgets('发现页用注入的桩数据渲染，不依赖真实接口', (WidgetTester tester) async {
    await _pumpApp(tester);

    // 每日推荐来自 discoverFeedProvider 的测试桩。
    expect(find.text('每日推荐'), findsOneWidget);
    expect(find.text('晴天'), findsWidgets);
    // 榜单区块来自同一份桩数据。
    expect(find.text('热门榜单'), findsOneWidget);
    // 轮播 banner 与榜单横排都会出现榜单标题，故用 findsWidgets。
    expect(find.text('TX 飙升榜'), findsWidgets);
    // 真实接口不可达时才会出现的错误态不应出现。
    expect(find.text('推荐内容加载失败'), findsNothing);
  });

  testWidgets('音频引擎经 ProviderScope 覆盖为假实现，播放器可正常初始化', (WidgetTester tester) async {
    final FakeAudioEngine engine = await _pumpApp(tester);

    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(MainShell)),
    );

    expect(container.read(audioEngineProvider), same(engine));
    // 播放器挂载后订阅引擎事件流，但不应触发任何原生解码动作。
    expect(engine.openedUrls, isEmpty);
    expect(find.text('暂无播放'), findsOneWidget);
  });

  test('路由表包含主流程与独立窗口页面', () {
    final ProviderContainer container = ProviderContainer(
      overrides: buildTestOverrides(),
    );
    addTearDown(container.dispose);

    expect(container.read(appRouterProvider).routeInformationParser, isNotNull);
    expect(AppRoutes.navDestinations, contains(AppRoutes.discover));
    expect(AppRoutes.player, '/player');
    expect(AppRoutes.desktopLyric, '/desktop-lyric');
  });

  test('DiscoverFeed 桩数据可被读取（验证 FutureProvider 覆盖生效）', () async {
    final ProviderContainer container = ProviderContainer(
      overrides: buildTestOverrides(),
    );
    addTearDown(container.dispose);

    final DiscoverFeed feed = await container.read(discoverFeedProvider.future);
    expect(feed.dailySongs, kTestSongs);
    expect(feed.ranks.length, kTestRanks.length);
    expect(feed.isEmpty, isFalse);
  });
}
