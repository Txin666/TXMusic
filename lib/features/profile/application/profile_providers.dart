import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/kugou_providers.dart';
import '../domain/user_profile.dart';

/// 当前账号个人信息。
///
/// - 未登录返回 `null`（页面据此展示游客态，且**不会**去打接口：实测未登录时
///   `/user/detail` 等接口统一回 502）；
/// - 登录态变化（扫码登录成功 / 退出）会自动重建并重新拉取；
/// - 需要手动刷新时调用 `ref.invalidate(userProfileProvider)`。
final FutureProvider<UserProfile?> userProfileProvider =
    FutureProvider<UserProfile?>((Ref ref) async {
  if (!ref.watch(kugouSessionProvider).isLoggedIn) {
    return null;
  }
  return ref.watch(kugouUserApiProvider).load();
});
