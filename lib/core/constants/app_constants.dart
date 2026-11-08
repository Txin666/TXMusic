/// 应用级常量：应用名、版本、窗口默认尺寸等（见开发文档 §3.2 core/constants）。
class AppConstants {
  const AppConstants._();

  static const String appName = 'TX Music';
  static const String appVersion = '1.0.0+1';
  static const String appSlogan = '本地优先的桌面音乐播放器';

  /// 窗口默认尺寸，P1 接入 window_manager 后由 bootstrap 使用（文档 §7）。
  static const double defaultWindowWidth = 1320;
  static const double defaultWindowHeight = 860;
  static const double minWindowWidth = 1000;
  static const double minWindowHeight = 640;

  /// 桌面歌词悬浮窗默认尺寸（文档 §7 桌面歌词窗口）。
  static const double desktopLyricWidth = 900;
  static const double desktopLyricHeight = 190;
}
