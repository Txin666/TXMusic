import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/kugou_providers.dart';
import '../data/kugou_search_api.dart';

/// 搜索联想（自动补全）的取数控制器：**防抖 + 竞态保护**。
///
/// 为什么不能直接每次 onChanged 就请求：
/// 用户敲「周杰伦」是 3 次按键，不防抖就是 3 个 `/search/suggest`，本地
/// KuGouMusicApi 单进程处理，快速输入时会排队、联想结果还会乱序回包。
/// 这里保证：
/// 1. 停止输入 [debounceDuration] 后才真正发请求，连击只发最后一笔；
/// 2. 被新输入取代的请求立即以空列表完成，不会悬挂 Future；
/// 3. 接口异常静默降级为空联想（搜不到联想词不该弹错误打断输入）。
class SearchSuggestController {
  SearchSuggestController(this._api);

  final KugouSearchApi _api;

  /// 防抖窗口：停止输入这么久之后才请求接口。
  static const Duration debounceDuration = Duration(milliseconds: 280);

  Timer? _timer;

  /// 输入序号：只有最新序号对应的请求会真正发出。
  int _seq = 0;

  /// 当前挂起（还在防抖窗口里）的那一笔请求。
  Completer<List<String>>? _pending;

  /// 取关键词 [keyword] 的联想词。
  ///
  /// 返回的 Future 总以列表完成（失败/被取代都是空列表），调用方无需 try。
  Future<List<String>> suggest(String keyword, {int limit = 10}) {
    final String key = keyword.trim();
    final int seq = ++_seq;
    final Completer<List<String>> completer = Completer<List<String>>();

    _timer?.cancel();
    _timer = null;

    // 上一笔还没发出的请求直接作废，避免一次输入连打多个请求。
    final Completer<List<String>>? stale = _pending;
    _pending = null;
    if (stale != null && !stale.isCompleted) {
      stale.complete(const <String>[]);
    }

    if (key.isEmpty || limit <= 0) {
      completer.complete(const <String>[]);
      return completer.future;
    }

    _pending = completer;
    _timer = Timer(debounceDuration, () async {
      // 防抖窗口内又有新输入：这一笔已经过期，直接丢弃。
      if (seq != _seq || completer.isCompleted) {
        return;
      }
      try {
        final List<String> suggestions = await _api.suggest(key, limit: limit);
        if (!completer.isCompleted) {
          completer.complete(suggestions);
        }
      } on Object {
        if (!completer.isCompleted) {
          completer.complete(const <String>[]);
        }
      } finally {
        if (identical(_pending, completer)) {
          _pending = null;
        }
      }
    });
    return completer.future;
  }

  /// 释放：取消定时器并把挂起请求以空结果收尾（避免页面销毁后 Future 不完成）。
  void dispose() {
    _timer?.cancel();
    _timer = null;
    final Completer<List<String>>? pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) {
      pending.complete(const <String>[]);
    }
  }
}

final Provider<SearchSuggestController> searchSuggestControllerProvider =
    Provider<SearchSuggestController>((Ref ref) {
      final SearchSuggestController controller = SearchSuggestController(
        ref.watch(kugouSearchApiProvider),
      );
      ref.onDispose(controller.dispose);
      return controller;
    });
