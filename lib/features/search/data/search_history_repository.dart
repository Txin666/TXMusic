import '../../../core/storage/local_store.dart';

/// 搜索历史持久化（`.local/search_history.json`）。
class SearchHistoryRepository {
  const SearchHistoryRepository();

  static const String fileName = 'search_history.json';
  static const int maxItems = 12;

  Future<List<String>> load() async {
    final Map<String, dynamic> json = await LocalStore.readJson(fileName);
    final Object? raw = json['keywords'];
    if (raw is! List) {
      return const <String>[];
    }
    return raw
        .map((Object? item) => '$item'.trim())
        .where((String item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  /// 记录一次搜索：去重置顶，超限截断。
  Future<List<String>> push(String keyword) async {
    final List<String> current = await load();
    final List<String> next = <String>[
      keyword,
      ...current.where((String item) => item != keyword),
    ].take(maxItems).toList(growable: false);
    await LocalStore.writeJson(fileName, <String, dynamic>{'keywords': next});
    return next;
  }

  Future<void> clear() async {
    await LocalStore.writeJson(fileName, <String, dynamic>{'keywords': <Object>[]});
  }
}
