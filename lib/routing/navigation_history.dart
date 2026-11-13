import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'app_router.dart';
import 'navigation_observer.dart';

/// 前进 / 后退历史状态（位置序列 + 当前位置下标）。
@immutable
class NavigationHistoryState {
  const NavigationHistoryState({
    this.entries = const <NavigationEntry>[],
    this.index = 0,
  });

  /// 访问过的位置序列：最旧 → 最新。
  final List<NavigationEntry> entries;

  /// 当前所处位置在 [entries] 中的下标。
  final int index;

  bool get canGoBack => index > 0 && entries.isNotEmpty;

  bool get canGoForward => entries.isNotEmpty && index < entries.length - 1;

  /// 后退目标；不可后退时为 null。
  NavigationEntry? get backEntry => canGoBack ? entries[index - 1] : null;

  /// 前进目标；不可前进时为 null。
  NavigationEntry? get forwardEntry => canGoForward ? entries[index + 1] : null;

  /// 仅位置字符串，便于日志与调试。
  List<String> get locations =>
      entries.map((NavigationEntry e) => e.location).toList(growable: false);
}

/// 自建前进 / 后退历史。
///
/// go_router 的 `go` 是「替换当前配置」而不是入栈，所以页面之间互相跳转后
/// `context.canPop()` 拿不到可返回的栈，前进更是完全没有——顶栏那两个按钮
/// 因此长期是禁用态。这里同时监听两路来源，按浏览器语义维护一份
/// 「已访问位置序列」：新导航截断前进栈后追加，后退/前进只移动下标。
/// - delegate 变化 → `go` 类导航（侧边栏、搜索、tab 切换）
/// - Navigator 入栈 → `push` 类导航（详情页、播放页）
class NavigationHistoryController extends Notifier<NavigationHistoryState> {
  /// 序列上限，防止长时间使用后无限增长。
  static const int maxEntries = 100;

  late GoRouter _router;
  late NavigationLocationObserver _observer;

  @override
  NavigationHistoryState build() {
    _router = ref.watch(appRouterProvider);
    _observer = ref.watch(navigationLocationObserverProvider);

    _router.routerDelegate.addListener(_handleRouterChanged);
    _observer.addListener(_handlePushed);
    ref.onDispose(() {
      _router.routerDelegate.removeListener(_handleRouterChanged);
      _observer.removeListener(_handlePushed);
    });

    return NavigationHistoryState(
      entries: <NavigationEntry>[NavigationEntry(location: _currentLocation())],
      index: 0,
    );
  }

  String _currentLocation() {
    final String uri = _router.routerDelegate.currentConfiguration.uri
        .toString();
    return uri.isEmpty ? '/' : uri;
  }

  void _handleRouterChanged() =>
      _record(NavigationEntry(location: _currentLocation()));

  void _handlePushed(NavigationEntry entry) => _record(entry);

  /// 记录一次导航。
  ///
  /// Navigator 的 `didPush` 回调发生在 widget 构建 / 布局阶段，此时直接改
  /// Riverpod 状态会触发「构建期间修改 provider」断言，所以统一推迟到微任务里
  /// 执行；微任务按入队顺序执行，导航的先后顺序不会被打破。
  void _record(NavigationEntry entry) => scheduleMicrotask(() {
    if (!ref.mounted) {
      return;
    }
    _applyRecord(entry);
  });

  void _applyRecord(NavigationEntry entry) {
    final List<NavigationEntry> entries = state.entries;
    // 同一位置原地刷新、或我们自己 goBack/goForward 触发的变化，都不新增历史。
    if (state.index < entries.length &&
        entries[state.index].location == entry.location) {
      return;
    }

    // 浏览器语义：新导航会截断「前进栈」。
    final List<NavigationEntry> next = <NavigationEntry>[
      ...entries.take(state.index + 1),
      entry,
    ];
    final List<NavigationEntry> trimmed = next.length > maxEntries
        ? next.sublist(next.length - maxEntries)
        : next;
    state = NavigationHistoryState(entries: trimmed, index: trimmed.length - 1);
  }

  /// 后退一个位置。
  void goBack() {
    final NavigationEntry? target = state.backEntry;
    if (target == null) {
      return;
    }
    final NavigationEntry leaving = state.entries[state.index];
    // 先移动下标：随后的位置变化回调会命中「当前位置未变」分支，不重复记录。
    state = NavigationHistoryState(
      entries: state.entries,
      index: state.index - 1,
    );
    // 离开的是 push 进去的页（详情 / 播放页）时必须真弹栈：
    // 此时路由位置（uri）仍是底层的 /rank，`go('/rank')` 属于原地跳、不会生效。
    if (leaving.isPush && _router.canPop()) {
      _router.pop();
      return;
    }
    _router.go(target.location);
  }

  /// 前进一个位置。
  void goForward() {
    final NavigationEntry? target = state.forwardEntry;
    if (target == null) {
      return;
    }
    state = NavigationHistoryState(
      entries: state.entries,
      index: state.index + 1,
    );
    // 原本是 push 进来的页（详情 / 播放页）继续用 push，保持层级一样。
    if (target.isPush) {
      _router.push(target.location);
    } else {
      _router.go(target.location);
    }
  }
}

final NotifierProvider<NavigationHistoryController, NavigationHistoryState>
navigationHistoryProvider =
    NotifierProvider<NavigationHistoryController, NavigationHistoryState>(
      NavigationHistoryController.new,
    );
