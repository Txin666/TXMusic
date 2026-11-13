import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../theme/app_palette.dart';
import '../../../../theme/app_spacing.dart';
import '../../application/search_suggest_controller.dart';

/// 带自动补全的搜索输入框。
///
/// 交互约定（桌面端）：
/// - 输入停顿 [SearchSuggestController.debounceDuration] 后才请求 `/search/suggest`（防抖）；
/// - 联想词里把用户已输入的部分**加粗 + 强调色**高亮，其余部分用主文字色；
/// - `↑` / `↓` 切换高亮项（PageUp / PageDown 翻页），`Esc` 收起联想面板；
/// - `Enter` 在面板展开时确认当前高亮项，收起时直接搜当前输入；
/// - 鼠标点击联想词等同确认。
///
/// 键盘行为由 [RawAutocomplete] 内置的 Shortcuts/Actions 提供，本组件只负责
/// 取数（防抖）与渲染（高亮 + 选中态），不自己抢按键事件，避免与输入法冲突。
class SearchSuggestionField extends ConsumerStatefulWidget {
  const SearchSuggestionField({
    super.key,
    required this.controller,
    required this.onSubmitted,
    this.onChanged,
    this.hintText = '搜索歌曲 / 歌手 / 歌单',
    this.autofocus = false,
    this.suffixIcon,
  });

  /// 外部持有的文本控制器（搜索页要用它做「清空 / 回填关键词」）。
  final TextEditingController controller;

  /// 确认搜索回调：回车确认联想词、点击联想词、点右侧按钮都会走这里。
  final ValueChanged<String> onSubmitted;

  /// 文本变化回调（用于让页面同步 keyword 状态）。
  final ValueChanged<String>? onChanged;

  final String hintText;
  final bool autofocus;
  final Widget? suffixIcon;

  @override
  ConsumerState<SearchSuggestionField> createState() =>
      _SearchSuggestionFieldState();
}

class _SearchSuggestionFieldState extends ConsumerState<SearchSuggestionField> {
  /// 一次最多展示的联想词条数。
  static const int _maxSuggestions = 8;

  /// 联想面板最大高度（超过滚动）。
  static const double _maxPanelHeight = 288;

  /// 自己持有焦点节点：RawAutocomplete 要求 focusNode 与 textEditingController
  /// 同时传入或同时为空（内部断言），且外部要能主动收焦点以关闭联想面板。
  final FocusNode _focusNode = FocusNode(debugLabel: 'searchSuggestionField');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<Iterable<String>> _buildOptions(TextEditingValue value) async {
    final String keyword = value.text.trim();
    if (keyword.isEmpty) {
      return const <String>[];
    }
    // RawAutocomplete 内部会丢弃「文本已变化」的旧回包，这里只需拿到防抖后的结果。
    return ref
        .read(searchSuggestControllerProvider)
        .suggest(keyword, limit: _maxSuggestions);
  }

  Widget _buildOptionsView(
    BuildContext context,
    AutocompleteOnSelected<String> onSelected,
    Iterable<String> options,
  ) {
    final AppPalette palette = context.palette;

    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Material(
          color: palette.surfaceHigh,
          elevation: 10,
          borderRadius: AppRadius.card,
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: _maxPanelHeight),
            child: _SuggestionListView(
              options: options.toList(growable: false),
              keyword: widget.controller.text.trim(),
              onSelected: onSelected,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      displayStringForOption: (String option) => option,
      optionsBuilder: _buildOptions,
      optionsViewOpenDirection: OptionsViewOpenDirection.down,
      // 点击联想词 / 回车确认高亮项 → 直接检索。
      onSelected: widget.onSubmitted,
      optionsViewBuilder: _buildOptionsView,
      fieldViewBuilder:
          (
            BuildContext context,
            TextEditingController textController,
            FocusNode focusNode,
            VoidCallback onFieldSubmitted,
          ) {
            return TextField(
              controller: textController,
              focusNode: focusNode,
              autofocus: widget.autofocus,
              textInputAction: TextInputAction.search,
              onChanged: widget.onChanged,
              onSubmitted: (String value) {
                final String before = textController.text;
                // 面板展开时这一步会把输入替换成高亮联想词，并回调 onSelected。
                onFieldSubmitted();
                if (textController.text != before) {
                  return; // 已由 onSelected 触发检索，避免重复请求。
                }
                widget.onSubmitted(value);
              },
              decoration: InputDecoration(
                hintText: widget.hintText,
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: widget.suffixIcon,
              ),
            );
          },
    );
  }
}

/// 联想词列表：跟随键盘高亮项自动滚动，避免按 ↓ 到第 8 项时选中项在视口外。
class _SuggestionListView extends StatefulWidget {
  const _SuggestionListView({
    required this.options,
    required this.keyword,
    required this.onSelected,
  });

  final List<String> options;
  final String keyword;
  final AutocompleteOnSelected<String> onSelected;

  @override
  State<_SuggestionListView> createState() => _SuggestionListViewState();
}

class _SuggestionListViewState extends State<_SuggestionListView> {
  /// 行高固定，方便用「下标 × 行高」算滚动目标。
  static const double _rowHeight = 40;

  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 保证第 [index] 行完整落在视口内。
  void _ensureVisible(int index) {
    if (!_scrollController.hasClients) {
      return;
    }
    final ScrollPosition position = _scrollController.position;
    final double itemTop = index * _rowHeight;
    final double itemBottom = itemTop + _rowHeight;
    final double viewTop = position.pixels;
    final double viewBottom = viewTop + position.viewportDimension;

    double? target;
    if (itemTop < viewTop) {
      target = itemTop;
    } else if (itemBottom > viewBottom) {
      target = itemBottom - position.viewportDimension;
    }
    if (target == null) {
      return;
    }
    _scrollController.animateTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final int highlightedIndex = AutocompleteHighlightedOption.of(context);
    // InheritedNotifier 变更发生在 build 之前，滚动必须等这一帧布局完成。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _ensureVisible(highlightedIndex);
      }
    });

    return ListView.builder(
      controller: _scrollController,
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemExtent: _rowHeight,
      itemCount: widget.options.length,
      itemBuilder: (BuildContext context, int index) {
        final String option = widget.options[index];
        return _SuggestionRow(
          keyword: widget.keyword,
          option: option,
          highlighted: index == highlightedIndex,
          onTap: () => widget.onSelected(option),
        );
      },
    );
  }
}

/// 单条联想词：命中部分加粗并染成强调色。
class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.keyword,
    required this.option,
    required this.highlighted,
    required this.onTap,
  });

  /// 用户当前输入（高亮依据）。
  final String keyword;
  final String option;

  /// 是否为键盘当前选中项。
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final ThemeData theme = Theme.of(context);
    final TextStyle base = (theme.textTheme.bodyMedium ?? const TextStyle())
        .copyWith(color: palette.textPrimary);
    final TextStyle match = base.copyWith(
      color: palette.emphasized,
      fontWeight: FontWeight.w700,
    );

    return InkWell(
      onTap: onTap,
      // 深浅色都能看见的悬停底色（palette.hoverOverlay 是纯白叠加，浅色主题下几乎不可见）。
      hoverColor: palette.emphasized.withValues(alpha: 0.10),
      child: Container(
        // 行高由 ListView 的 itemExtent(40) 锁定，这里只负责水平内边距与垂直居中。
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        alignment: Alignment.centerLeft,
        color: highlighted
            ? Color.alphaBlend(
                palette.emphasized.withValues(alpha: 0.16),
                palette.surfaceHigh,
              )
            : null,
        child: Row(
          children: <Widget>[
            Icon(
              Icons.search_rounded,
              size: 15,
              color: highlighted ? palette.emphasized : palette.textDisabled,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: _highlightSpans(option, keyword, base, match),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 把 [option] 按 [keyword]（忽略大小写）切片，命中段用 [match] 样式。
  ///
  /// 空关键词直接整段返回；`keyword` 长于 `option` 时也不会死循环
  /// （`indexOf` 找不到就退出）。
  static List<TextSpan> _highlightSpans(
    String option,
    String keyword,
    TextStyle base,
    TextStyle match,
  ) {
    final String needle = keyword.trim();
    if (needle.isEmpty) {
      return <TextSpan>[TextSpan(text: option, style: base)];
    }

    final String haystackLower = option.toLowerCase();
    final String needleLower = needle.toLowerCase();
    final List<TextSpan> spans = <TextSpan>[];

    int cursor = 0;
    while (cursor < option.length) {
      final int hit = haystackLower.indexOf(needleLower, cursor);
      if (hit < 0) {
        break;
      }
      if (hit > cursor) {
        spans.add(TextSpan(text: option.substring(cursor, hit), style: base));
      }
      spans.add(
        TextSpan(
          text: option.substring(hit, hit + needle.length),
          style: match,
        ),
      );
      cursor = hit + needle.length;
    }
    if (cursor < option.length) {
      spans.add(TextSpan(text: option.substring(cursor), style: base));
    }
    if (spans.isEmpty) {
      spans.add(TextSpan(text: option, style: base));
    }
    return spans;
  }
}
