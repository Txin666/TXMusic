import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:txmusic/features/rank/presentation/rank_detail_page.dart';
import 'package:txmusic/features/rank/presentation/rank_page.dart';
import 'package:txmusic/features/search/presentation/search_page.dart';
import 'package:txmusic/main.dart';

import 'helpers/test_app_harness.dart';

Future<void> _pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(overrides: buildTestOverrides(), child: const TxMusicApp()),
  );
  await tester.pumpAndSettle();
}

Finder get _backButton =>
    find.widgetWithIcon(IconButton, Icons.arrow_back_ios_new_rounded);
Finder get _forwardButton =>
    find.widgetWithIcon(IconButton, Icons.arrow_forward_ios_rounded);

IconButton _buttonOf(WidgetTester tester, Finder finder) =>
    tester.widget<IconButton>(finder);

void main() {
  testWidgets('首屏没有历史时前进/后退都不可点', (WidgetTester tester) async {
    await _pumpApp(tester);

    expect(_backButton, findsOneWidget);
    expect(_forwardButton, findsOneWidget);
    expect(_buttonOf(tester, _backButton).onPressed, isNull);
    expect(_buttonOf(tester, _forwardButton).onPressed, isNull);
  });

  testWidgets('顶栏后退回到上一页、前进再回到走之前那页', (WidgetTester tester) async {
    await _pumpApp(tester);

    // 发现页 → 排行榜 → 搜索页，形成两段历史。
    await tester.tap(find.text('排行榜').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('搜索').first);
    await tester.pumpAndSettle();
    expect(find.byType(SearchPage), findsOneWidget);
    expect(_buttonOf(tester, _backButton).onPressed, isNotNull);
    expect(_buttonOf(tester, _forwardButton).onPressed, isNull);

    // 后退一格：回到排行榜。
    await tester.tap(_backButton);
    await tester.pumpAndSettle();
    expect(find.byType(RankPage), findsOneWidget);
    expect(find.byType(SearchPage), findsNothing);
    expect(_buttonOf(tester, _forwardButton).onPressed, isNotNull);

    // 前进一格：回到搜索页。
    await tester.tap(_forwardButton);
    await tester.pumpAndSettle();
    expect(find.byType(SearchPage), findsOneWidget);
  });

  testWidgets('进入详情页后后退可回到列表页', (WidgetTester tester) async {
    await _pumpApp(tester);

    await tester.tap(find.text('排行榜').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('TX 飙升榜').first);
    await tester.pumpAndSettle();
    expect(find.byType(RankDetailPage), findsOneWidget);

    await tester.tap(_backButton);
    await tester.pumpAndSettle();
    expect(find.byType(RankDetailPage), findsNothing);
    expect(find.byType(RankPage), findsOneWidget);

    // 回到列表页后前进按钮仍可回到详情页，说明历史序列没被后退清空。
    await tester.tap(_forwardButton);
    await tester.pumpAndSettle();
    expect(find.byType(RankDetailPage), findsOneWidget);
  });
}
