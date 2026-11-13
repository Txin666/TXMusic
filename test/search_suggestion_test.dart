import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:txmusic/core/network/kugou_client.dart';
import 'package:txmusic/core/network/kugou_providers.dart';
import 'package:txmusic/core/network/kugou_session.dart';
import 'package:txmusic/features/search/data/kugou_search_api.dart';
import 'package:txmusic/features/search/presentation/widgets/search_suggestion_field.dart';
import 'package:txmusic/theme/app_palette.dart';
import 'package:txmusic/theme/app_theme.dart';

/// 联想接口桩：记录请求关键词，便于断言防抖只打了一次。
class _FakeSearchApi extends KugouSearchApi {
  _FakeSearchApi() : super(KugouClient(session: KugouSession.guest));

  final List<String> requested = <String>[];

  static const List<String> results = <String>['周杰伦', '周杰伦 晴天', '周杰伦 稻香'];

  @override
  Future<List<String>> suggest(String keyword, {int limit = 10}) async {
    requested.add(keyword);
    return results.take(limit).toList();
  }
}

class _Harness {
  _Harness(this.api, this.controller, this.submitted);

  final _FakeSearchApi api;
  final TextEditingController controller;
  final List<String> submitted;
}

Future<_Harness> _pumpField(WidgetTester tester) async {
  final _FakeSearchApi api = _FakeSearchApi();
  final TextEditingController controller = TextEditingController();
  final List<String> submitted = <String>[];
  addTearDown(controller.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[kugouSearchApiProvider.overrideWithValue(api)],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: SearchSuggestionField(
              controller: controller,
              onSubmitted: submitted.add,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(api, controller, submitted);
}

/// 取出联想面板里所有富文本片段。
List<TextSpan> _renderedSpans(WidgetTester tester) {
  final List<TextSpan> spans = <TextSpan>[];
  for (final Text text in tester.widgetList<Text>(find.byType(Text))) {
    final InlineSpan? span = text.textSpan;
    if (span is TextSpan) {
      spans.addAll(span.children?.whereType<TextSpan>() ?? <TextSpan>[]);
    }
  }
  return spans;
}

void main() {
  testWidgets('连续输入只在停止输入后请求一次联想接口（防抖）', (WidgetTester tester) async {
    final _Harness h = await _pumpField(tester);
    final Finder field = find.byType(TextField);

    // 模拟快速连打，每次都远小于 280ms 防抖窗口。
    await tester.enterText(field, '周');
    await tester.pump(const Duration(milliseconds: 80));
    await tester.enterText(field, '周杰');
    await tester.pump(const Duration(milliseconds: 80));
    await tester.enterText(field, '周杰伦');
    await tester.pump(const Duration(milliseconds: 100));

    expect(h.api.requested, isEmpty, reason: '防抖窗口内不应发请求');

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(h.api.requested, <String>['周杰伦'], reason: '连打只应发最后一笔');
  });

  testWidgets('联想词渲染并把已输入部分加粗染成强调色', (WidgetTester tester) async {
    final _Harness h = await _pumpField(tester);

    await tester.enterText(find.byType(TextField), '周杰');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    // 三条联想词都应渲染出来。
    for (final String option in _FakeSearchApi.results) {
      expect(
        find.byWidgetPredicate(
          (Widget w) => w is Text && w.textSpan?.toPlainText() == option,
        ),
        findsOneWidget,
        reason: '缺少联想词：$option',
      );
    }

    final List<TextSpan> spans = _renderedSpans(tester);
    final Iterable<TextSpan> matched = spans.where(
      (TextSpan s) =>
          s.text == '周杰' &&
          s.style?.fontWeight == FontWeight.w700 &&
          s.style?.color == AppPalette.dark.emphasized,
    );
    // 3 条联想词都以「周杰」开头，命中段应各出现一次。
    expect(matched.length, _FakeSearchApi.results.length);

    // 未命中的尾巴必须保持普通样式，避免整行都变成强调色 / 加粗。
    expect(
      spans.any(
        (TextSpan s) =>
            s.text == '伦' &&
            s.style?.fontWeight != FontWeight.w700 &&
            s.style?.color != AppPalette.dark.emphasized,
      ),
      isTrue,
    );

    // 输入被保留，没有被联想词顶掉。
    expect(h.controller.text, '周杰');
  });

  testWidgets('方向键选择 + 回车确认把高亮联想词提交出去', (WidgetTester tester) async {
    final _Harness h = await _pumpField(tester);

    await tester.enterText(find.byType(TextField), '周杰');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    // 默认高亮第 0 条，向下一格到第 1 条。
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    // 真机上引擎会把回车翻成 done/search 动作，测试里用 receiveAction 模拟这条链路
    // （sendKeyEvent(enter) 只发框架按键，不会触发 TextField.onSubmitted）。
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(h.submitted, isNotEmpty);
    expect(h.submitted.first, _FakeSearchApi.results[1]);
    // 回车可能同时走联想确认与输入框提交，两条路径必须落到同一个词，不能重复搜别的。
    expect(h.submitted.toSet(), <String>{_FakeSearchApi.results[1]});
    expect(h.controller.text, _FakeSearchApi.results[1]);
  });

  testWidgets('清空输入后不再请求联想接口', (WidgetTester tester) async {
    final _Harness h = await _pumpField(tester);

    await tester.enterText(find.byType(TextField), '周杰伦');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(h.api.requested, <String>['周杰伦']);

    await tester.enterText(find.byType(TextField), '');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(h.api.requested, <String>['周杰伦'], reason: '空关键词不该打接口');
  });
}
