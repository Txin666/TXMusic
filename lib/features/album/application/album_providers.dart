import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/fake_album_data.dart';
import '../domain/album.dart';

/// 专辑详情（骨架期假数据，按 id 参数化）。
final albumListProvider = Provider<List<Album>>(
  (Ref ref) => FakeAlbums.all,
);

final albumDetailProvider = Provider.family<Album, String>(
  (Ref ref, String id) => FakeAlbums.byId(id),
);
