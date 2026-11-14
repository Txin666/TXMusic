import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:txmusic/features/rank/presentation/rank_detail_page.dart';
import 'package:txmusic/features/rank/presentation/rank_page.dart';
import 'package:txmusic/features/search/presentation/search_page.dart';
import 'package:txmusic/features/shell/presentation/main_shell.dart';
import 'package:txmusic/main.dart';
import 'package:txmusic/routing/app_routes.dart';
import 'package:txmusic/routing/app_router.dart';

import 'helpers/test_app_harness.dart';

Future<void> _pumpApp(WidgetTester tester) async {
  // 桌面窗口尺寸下校验布局，避免测试默认 800x600 造成窄屏折叠差异。
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  // 全部数据与音频引擎经 overrides 注入，测试不触碰真实接口与 media_kit 原生库。
  await tester.pumpWidget(
    ProviderScope(overrides: buildTestOverrides(), child: const TxMusicApp()),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('启动后渲染主框架（侧边导航 + 搜索栏 + 播放条）', (WidgetTester tester) async {
    await _pumpApp(tester);

    expect(find.byType(MainShell), findsOneWidget);
    // 侧边导航顶部品牌区与底部信息栏各有一处品牌文字。
    expect(find.text('TX MUSIC'), findsNWidgets(2));
    expect(find.text('发现'), findsWidgets);
    expect(find.text('暂无播放'), findsOneWidget);
  });

  testWidgets('侧边导航可从发现页切换到排行榜与搜索页', (WidgetTester tester) async {
    await _pumpApp(tester);

    await tester.tap(find.text('排行榜').first);
    await tester.pumpAndSettle();
    expect(find.byType(RankPage), findsOneWidget);

    await tester.tap(find.text('搜索').first);
    await tester.pumpAndSettle();
    expect(find.byType(SearchPage), findsOneWidget);

    // 导航切换后播放条仍在（Shell 不重建），且无异常。
    expect(find.text('暂无播放'), findsOneWidget);
  });

  testWidgets('排行榜卡片可跳转榜单详情页', (WidgetTester tester) async {
    await _pumpApp(tester);

    await tester.tap(find.text('排行榜').first);
    await tester.pumpAndSettle();
    expect(find.byType(RankPage), findsOneWidget);

    // 点击榜单标题进入详情页，详情页仍渲染在主框架内（播放条保留）。
    await tester.tap(find.text('TX 飙升榜').first);
    await tester.pumpAndSettle();
    expect(find.byType(RankDetailPage), findsOneWidget);
    expect(find.byType(MainShell), findsOneWidget);
    // 详情页标题与曲目均来自注入的桩数据。
    expect(find.text('榜单曲目'), findsOneWidget);
    expect(find.text('晴天'), findsWidgets);
  });

  testWidgets('发现页榜单行可跳转榜单详情页', (WidgetTester tester) async {
    await _pumpApp(tester);

    // 榜单行位于首屏下方，先滚动到可见位置再点击。
    await tester.scrollUntilVisible(
      find.text('查看').first,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看').first);
    await tester.pumpAndSettle();

    expect(find.byType(RankDetailPage), findsOneWidget);
    expect(find.byType(MainShell), findsOneWidget);
  });

  test('路由常量与实例可用', () {
    final ProviderContainer container = ProviderContainer(
      overrides: buildTestOverrides(),
    );
    addTearDown(container.dispose);

    expect(container.read(appRouterProvider).routeInformationParser, isNotNull);
    expect(AppRoutes.navDestinations, contains(AppRoutes.discover));
    expect(AppRoutes.player, '/player');
  });
}
