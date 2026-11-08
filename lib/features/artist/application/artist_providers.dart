import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/fake_artist_data.dart';
import '../domain/artist.dart';

/// 歌手详情（骨架期假数据，按 id 参数化）。
final artistListProvider = Provider<List<Artist>>(
  (Ref ref) => FakeArtists.all,
);

final artistDetailProvider = Provider.family<Artist, String>(
  (Ref ref, String id) => FakeArtists.byId(id),
);
