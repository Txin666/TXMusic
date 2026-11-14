import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:txmusic/core/audio/i_audio_engine.dart';
import 'package:txmusic/core/network/kugou_client.dart';
import 'package:txmusic/core/network/kugou_providers.dart';
import 'package:txmusic/features/lyric/application/lyric_providers.dart';
import 'package:txmusic/features/lyric/domain/lyric_line.dart';
import 'package:txmusic/features/player/application/player_controller.dart';
import 'package:txmusic/features/player/data/song_url_resolver.dart';
import 'package:txmusic/features/player/presentation/player_page.dart';
import 'package:txmusic/features/song/domain/song.dart';
import 'package:txmusic/shared/widgets/cover_image.dart';
import 'package:txmusic/theme/app_spacing.dart';
import 'package:txmusic/theme/app_theme.dart';

import '../helpers/test_app_harness.dart';

/// 60 行、每行 5 秒的桩歌词：行数要足够多，滚轮才有可滚的余量。
final List<LyricLine> _lines = <LyricLine>[
  for (int i = 0; i < 60; i++) LyricLine(Duration(seconds: i * 5), '歌词第 $i 行'),
];

/// 桩音源解析器：不发 `/song/url` 请求，直接给一个可播放的假地址。
/// 真实解析在测试环境会因 HttpClient 返回 400 而把播放器打进 error 态。
class _StubResolver extends SongUrlResolver {
  // 父类构造参数是私有字段 `_client`，Super 参数写法在这里不合法。
  // ignore: use_super_parameters
  _StubResolver(KugouClient client) : super(client);

  @override
  Future<ResolvedAudio> resolve(Song song, {String quality = '128'}) async =>
      ResolvedAudio(
        url: Uri.parse('https://example.com/${song.hash}.mp3'),
        backups: const <Uri>[],
        duration: song.duration,
      );
}

typedef _Harness = ({FakeAudioEngine engine, ProviderContainer container});

Future<_Harness> _pumpPlayerPage(
  WidgetTester tester, {
  Size size = const Size(1600, 1200),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final FakeAudioEngine engine = FakeAudioEngine();
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      ...buildTestOverrides(engine: engine),
      songUrlResolverProvider.overrideWith(
        (Ref ref) => _StubResolver(ref.watch(kugouClientProvider)),
      ),
      lyricLinesProvider.overrideWith((Ref ref, LyricKey key) async => _lines),
    ],
  );
  addTearDown(container.dispose);

  await container
      .read(playerControllerProvider.notifier)
      .playSong(kTestSongs.first);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.dark(), home: const PlayerPage()),
    ),
  );
  await tester.pumpAndSettle();
  return (engine: engine, container: container);
}

ScrollableState _lyricsScrollable(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable));

/// 模拟鼠标滚轮在歌词区滚动 [deltaY] 像素。
Future<void> _scrollLyrics(WidgetTester tester, double deltaY) async {
  final Finder list = find.byType(ListView);
  final TestPointer pointer = TestPointer(1, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(pointer.hover(tester.getCenter(list)));
  await tester.sendEventToBinding(pointer.scroll(Offset(0, deltaY)));
  await tester.pumpAndSettle();
}

/// 模拟鼠标双击歌词行：两次点击的间隔必须落在双击判定窗口内。
Future<void> _doubleTapLyric(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 60));
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('歌词区渲染成可滚动的完整列表，而不是固定几行', (WidgetTester tester) async {
    await _pumpPlayerPage(tester);

    expect(find.byType(ListView), findsOneWidget);
    // 首行可见，且列表高度撑满可用区域（远高于原来固定 9 行的高度）。
    expect(find.text('歌词第 0 行'), findsOneWidget);
    final double listHeight = tester.getSize(find.byType(ListView)).height;
    expect(listHeight, greaterThan(560));
  });

  testWidgets('滚轮滚动暂停自动跟随，且不再弹出任何手动浏览提示', (WidgetTester tester) async {
    final _Harness harness = await _pumpPlayerPage(tester);

    final ScrollableState scrollable = _lyricsScrollable(tester);
    final double before = scrollable.position.pixels;

    await _scrollLyrics(tester, 300);

    // 列表真的滚了，且播放器位置没被滚轮改动（滚歌词不等于 seek）。
    expect(scrollable.position.pixels, isNot(before));
    expect(harness.engine.lastSeek, isNull);
    // 提示条彻底移除：既没有文案，也没有恢复按钮。
    expect(find.textContaining('手动浏览中'), findsNothing);
    expect(find.text('回到当前播放'), findsNothing);

    await _drainAutoResume(tester);
  });

  testWidgets('滚轮后 3 秒内没点歌词跳转，自动回到当前播放行', (WidgetTester tester) async {
    await _pumpPlayerPage(tester);
    final ScrollableState scrollable = _lyricsScrollable(tester);

    await _scrollLyrics(tester, 300);
    expect(scrollable.position.pixels, isNot(closeTo(0, 1)));

    // 差一点到 3 秒：仍停在用户滚出去的位置。
    await tester.pump(const Duration(milliseconds: 2500));
    expect(scrollable.position.pixels, isNot(closeTo(0, 1)));

    // 越过 3 秒：自动跟随恢复，滚回当前播放行（第 0 行 → 偏移 0）。
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, closeTo(0, 1));
    expect(find.text('歌词第 0 行'), findsOneWidget);
  });

  testWidgets('3 秒内再次滚动会重新计时', (WidgetTester tester) async {
    await _pumpPlayerPage(tester);
    final ScrollableState scrollable = _lyricsScrollable(tester);

    await _scrollLyrics(tester, 300);
    await tester.pump(const Duration(milliseconds: 2000));
    final double userOffset = scrollable.position.pixels;

    await _scrollLyrics(tester, 300);
    await tester.pump(const Duration(milliseconds: 2000));
    // 第一次滚动已过 4 秒，但被第二次滚动重新计时，此刻还在用户位置。
    expect(scrollable.position.pixels, isNot(closeTo(0, 1)));
    expect(scrollable.position.pixels, isNot(userOffset));

    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, closeTo(0, 1));
  });

  testWidgets('暂停期间双击歌词行按该行时间 seek 并立刻恢复跟随', (
    WidgetTester tester,
  ) async {
    final _Harness harness = await _pumpPlayerPage(tester);
    await _scrollLyrics(tester, 300);

    final Finder target = find.text('歌词第 12 行');
    expect(target, findsOneWidget);
    await _doubleTapLyric(tester, target);

    // 第 12 行的时间戳 = 12 * 5s。
    expect(harness.engine.lastSeek, const Duration(seconds: 60));
    // 双击过之后计时器作废，不会被 3 秒规则再次拽走。
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.textContaining('手动浏览中'), findsNothing);
  });

  testWidgets('单击歌词行不跳转，浏览时不会误触 seek', (WidgetTester tester) async {
    final _Harness harness = await _pumpPlayerPage(tester);
    await _scrollLyrics(tester, 300);

    final Finder target = find.text('歌词第 12 行');
    expect(target, findsOneWidget);
    await tester.tap(target);
    await tester.pumpAndSettle();

    // 单击只是浏览，不会跳到第 12 行。
    expect(harness.engine.lastSeek, isNot(const Duration(seconds: 60)));
    // 也不算交互，3 秒规则照常把视图拉回当前播放行。
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(_lyricsScrollable(tester).position.pixels, closeTo(0, 1));
  });

  testWidgets('播放进度推进时自动跟随，当前行滚到视口中间', (WidgetTester tester) async {
    final _Harness harness = await _pumpPlayerPage(tester);

    // 播放器只在 playing / buffering 态采纳 position 事件，先补一个播放事件。
    harness.engine.emit(const AudioEngineEvent.playing(true));
    await tester.pump();
    // 推进到第 30 行对应的 150 秒。
    harness.engine.emit(
      const AudioEngineEvent.position(Duration(seconds: 150)),
    );
    await tester.pumpAndSettle();

    final ScrollableState scrollable = _lyricsScrollable(tester);

    // itemExtent 56 → 第 30 行的居中偏移 = 30 * 56 = 1680。
    expect(scrollable.position.pixels, closeTo(1680, 1));
    expect(find.text('歌词第 30 行'), findsOneWidget);
  });

  testWidgets('暂停期间被外部 seek 打断会重新回到跟随', (WidgetTester tester) async {
    final _Harness harness = await _pumpPlayerPage(tester);
    await _scrollLyrics(tester, 300);

    // 拖动进度条 / 重播会让播放位置大幅跳变，此时跟随必须自动恢复。
    harness.engine.emit(
      const AudioEngineEvent.position(Duration(seconds: 200)),
    );
    await tester.pumpAndSettle();

    expect(_lyricsScrollable(tester).position.pixels, closeTo(40 * 56, 1));
  });

  testWidgets('窗口拉宽后封面与歌词间距不变，内容宽度有上限', (WidgetTester tester) async {
    await _pumpPlayerPage(tester, size: const Size(1500, 1100));
    final double narrowGap = _coverToLyricsGap(tester);
    final double narrowLyricsWidth = tester
        .getSize(find.byType(ListView))
        .width;

    tester.view.physicalSize = const Size(2560, 1400);
    await tester.pumpAndSettle();

    // 最大化 / 全屏后间距依旧是固定的一段，不会跟着窗口一起变宽。
    expect(narrowGap, closeTo(AppSpacing.xxl, 1));
    expect(_coverToLyricsGap(tester), closeTo(narrowGap, 1));
    // 歌词区宽度也不再随窗口无限膨胀（整块内容封顶后居中）。
    expect(
      tester.getSize(find.byType(ListView)).width,
      closeTo(narrowLyricsWidth, 1),
    );
    final double contentWidth =
        tester.getSize(find.byType(CoverImage)).width +
        AppSpacing.xxl +
        tester.getSize(find.byType(ListView)).width;
    expect(contentWidth, lessThanOrEqualTo(AppSpacing.maxContentWidth + 1));
  });

  testWidgets('鼠标悬停歌词行时，在歌词后面显示该行时间', (WidgetTester tester) async {
    await _pumpPlayerPage(tester);

    // 未悬停时不显示时间。
    expect(find.text('0:05'), findsNothing);

    final TestGesture mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('歌词第 1 行')));
    await tester.pumpAndSettle();

    // 第 1 行时间 = 5 秒 → `0:05`，出现在歌词右侧。
    expect(find.text('0:05'), findsOneWidget);
    expect(
      tester.getCenter(find.text('0:05')).dx,
      greaterThan(tester.getCenter(find.text('歌词第 1 行')).dx),
    );
    // 右对齐：时间右边缘贴着行尾（行内边距 12），而不是跟着文字漂。
    final double rowRight = tester.getTopRight(find.byType(ListView)).dx;
    expect(rowRight - tester.getTopRight(find.text('0:05')).dx, lessThan(24));
    // 醒目：强调色 + 加粗。
    final TextStyle timeStyle = tester.widget<Text>(find.text('0:05')).style!;
    expect(timeStyle.fontWeight, FontWeight.w700);
    expect(timeStyle.color, isNotNull);

    // 移开鼠标后时间随之消失。
    await mouse.moveTo(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('0:05'), findsNothing);
  });
}

/// 封面右边缘到歌词列表左边缘的水平距离（两栏间距）。
double _coverToLyricsGap(WidgetTester tester) =>
    tester.getTopLeft(find.byType(ListView)).dx -
    tester.getTopRight(find.byType(CoverImage)).dx;

/// 消化挂起的自动恢复计时器，避免测试结束时报 pending timer。
Future<void> _drainAutoResume(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
}
