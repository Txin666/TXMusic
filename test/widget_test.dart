import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:txmusic/features/shell/presentation/main_shell.dart';
import 'package:txmusic/main.dart';
import 'package:txmusic/routing/app_routes.dart';
import 'package:txmusic/routing/app_router.dart';

void main() {
  testWidgets('启动后渲染主框架（侧边导航 + 搜索栏 + 播放条）', (WidgetTester tester) async {
    // 桌面窗口尺寸下校验布局，避免测试默认 800x600 造成窄屏折叠差异。
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProviderScope(child: TxMusicApp()));
    await tester.pumpAndSettle();

    expect(find.byType(MainShell), findsOneWidget);
    expect(find.text('TX MUSIC'), findsOneWidget);
    expect(find.text('发现'), findsWidgets);
    expect(find.text('暂无播放'), findsOneWidget);
  });

  test('路由表包含主流程与独立窗口页面', () {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(appRouterProvider).routeInformationParser, isNotNull);
    expect(AppRoutes.navDestinations, contains(AppRoutes.discover));
    expect(AppRoutes.player, '/player');
    expect(AppRoutes.desktopLyric, '/desktop-lyric');
  });
}
