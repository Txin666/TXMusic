import 'dart:io';

import 'package:flutter/foundation.dart';

/// 启动诊断日志。
///
/// 发布版同样落盘（安装到别人机器上出问题时只能靠它定位），
/// 位置固定为 %LOCALAPPDATA%\TXMusic\txmusic_diag.log，超过 200KB 自动裁剪到最近 200 行。
void bootLog(String message) {
  debugPrint('[diag] $message');
  try {
    final String? local = Platform.environment['LOCALAPPDATA'];
    if (local == null) {
      return;
    }
    final Directory dir = Directory('$local\\TXMusic');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final File file = File('${dir.path}\\txmusic_diag.log');
    if (file.existsSync() && file.lengthSync() > 200 * 1024) {
      final List<String> lines = file.readAsLinesSync();
      final int from = lines.length > 200 ? lines.length - 200 : 0;
      file.writeAsStringSync(
        '${lines.sublist(from).join('\n')}\n',
        flush: true,
      );
    }
    file.writeAsStringSync(
      '${DateTime.now().toIso8601String()} [pid=$pid] $message\n',
      mode: FileMode.append,
      flush: true,
    );
  } on Object catch (_) {
    // 日志失败不能阻塞启动
  }
}
