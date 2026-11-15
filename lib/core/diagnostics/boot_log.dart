import 'dart:io';

import 'package:flutter/foundation.dart';

/// 启动诊断日志。
///
/// release 版 Windows runner 没有控制台，`debugPrint` 全部丢失，
/// 「托盘出现两个图标 / 点击不弹面板」这类只在打包版复现的问题只能落盘排查。
/// 默认只在 debug 或显式设置了 TX_DIAG=1 时落盘，避免正式版无谓写文件。
void bootLog(String message) {
  debugPrint('[diag] $message');
  if (kReleaseMode && Platform.environment['TX_DIAG'] != '1') {
    return;
  }
  try {
    final String? local = Platform.environment['LOCALAPPDATA'];
    if (local == null) {
      return;
    }
    final Directory dir = Directory('$local\\TXMusic');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    File('${dir.path}\\txmusic_diag.log').writeAsStringSync(
      '${DateTime.now().toIso8601String()} [pid=$pid] $message\n',
      mode: FileMode.append,
      flush: true,
    );
  } on Object catch (_) {
    // 诊断日志不能影响主流程。
  }
}
