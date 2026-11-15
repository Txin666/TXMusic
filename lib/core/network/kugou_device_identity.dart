import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// 酷狗设备标识（`KUGOU_API_GUID` / `KUGOU_API_MID`）。
///
/// 为什么需要它：本地 KuGouMusicApi 的播放上报
/// （`module/user_listen_report.js` → `POST /user/listen/report`）要求 cookie 里
/// 带 `KUGOU_API_GUID`（32 位字母数字）与 `KUGOU_API_MID`，缺任意一个都直接
/// 返回 400「需要 token、userid、mid 和 32 位字母数字 uuid」，于是播放行为
/// 上报不上去，官方累计听歌时长永远不涨。
///
/// 服务端本该在缺失时自动注入这两个 cookie（`server.js` 的标识注入中间件），
/// 但它注入的 GUID 取自环境变量 `KUGOU_API_GUID`，未配置时下发的是空串，
/// 等于没补。客户端自带一份设备标识最稳，也能保证 mid 与 guid 始终配对。
class KugouDeviceIdentity {
  const KugouDeviceIdentity._();

  /// 生成本机设备 GUID：UUID v4 去掉连字符，得到 32 位十六进制串。
  static String generateGuid() {
    final Random random = Random.secure();
    final List<int> bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10xx
    return bytes
        .map((int byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// 与服务端 `util/util.js` 的 `calculateMid` 保持同一算法：
  /// `MD5(guid)` 的十六进制串当作 16 进制大整数，再转成十进制字符串。
  static String midOf(String guid) {
    final String value = guid.replaceAll('-', '');
    if (value.isEmpty) {
      return '';
    }
    final String digest = md5.convert(utf8.encode(value)).toString();
    return BigInt.parse(digest, radix: 16).toString();
  }
}
