// 临时冒烟测试：验证「HTTP 502 + body.error_code」能被正确解析成业务状态。
// 依赖本地 KuGouMusicApi（http://localhost:3000）与已登录的 cookie 文件。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:txmusic/core/network/kugou_client.dart';
import 'package:txmusic/core/network/kugou_session.dart';
import 'package:txmusic/features/vip/data/kugou_vip_api.dart';

void main() {
  test('每日领取在“已领”情况下应返回 alreadyClaimed 而非抛 502', () async {
    final File file = File('.local/kugou_cookie.json');
    expect(file.existsSync(), isTrue, reason: '缺少 .local/kugou_cookie.json');
    final Map<String, dynamic> raw =
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

    final KugouSession session = KugouSession.guest.copyWith(
      dfid: '${raw['dfid'] ?? ''}',
      userid: '${raw['userid'] ?? ''}',
      token: '${raw['token'] ?? ''}',
      cookie: '${raw['cookie'] ?? ''}',
    );

    final KugouClient client = KugouClient(
      session: session,
      baseUrl: 'http://localhost:3000',
    );
    final KugouVipApi api = KugouVipApi(client);

    final DailyVipClaimResult result = await api.claimDailyVip();
    // ignore: avoid_print
    print('status=${result.status} message=${result.message}');
    for (final String step in result.steps) {
      // ignore: avoid_print
      print('  step: $step');
    }
    expect(result.message.contains('HTTP 502'), isFalse);
    expect(result.isOk, isTrue);
  }, skip: '集成冒烟：需本地 KuGouMusicApi(3000) 与已登录 cookie，默认不参与全量测试',
      timeout: const Timeout(Duration(seconds: 60)));
}
