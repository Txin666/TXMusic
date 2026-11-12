/// 资源地址规整（开发文档 §5 图片加载策略第 4 条）。
///
/// 酷狗返回的封面/歌手图有三类坑：
/// 1. 模板串 `http://imge.kugou.com/stdmusic/{size}/xxx.jpg`，`{size}` 必须替换成具体像素；
/// 2. 协议相对地址 `//imge.kugou.com/...`，缺 scheme；
/// 3. 明文 `http://`，Windows 桌面端加载会被混内容策略拦，统一改 `https://`。
class AssetUrl {
  const AssetUrl._();

  /// 默认请求尺寸（列表/播放条足够清晰且体积可控）。
  static const int defaultSize = 480;

  /// 按展示尺寸挑一档请求尺寸，避免 44px 小图去拉 480px 大图。
  static int sizeFor(double logicalSize) {
    if (logicalSize <= 64) {
      return 150;
    }
    if (logicalSize <= 140) {
      return 240;
    }
    if (logicalSize <= 260) {
      return 480;
    }
    return 800;
  }

  /// 规整为可直接加载的绝对 https 地址；无法还原的裸文件名返回 null（交给占位图）。
  static String? normalize(Object? raw, {int size = defaultSize}) {
    String value = (raw ?? '').toString().trim();
    if (value.isEmpty) {
      return null;
    }
    value = value.replaceAll('{size}', '$size');
    if (value.startsWith('//')) {
      value = 'https:$value';
    }
    if (value.startsWith('http://')) {
      value = value.replaceFirst('http://', 'https://');
    }
    if (value.startsWith('https://') || value.startsWith('data:image/')) {
      return value;
    }
    // 部分接口 cover 只给 `20261106103502112276.jpg` 这种文件名，无法还原目录，放弃。
    return null;
  }
}
