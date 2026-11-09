import '../../../core/network/json_utils.dart';
import '../../../core/network/kugou_client.dart';

/// 二维码登录会话：key 用于轮询，base64 直接渲染。
class LoginQr {
  const LoginQr({required this.key, required this.imageBase64, this.url = ''});

  final String key;

  /// `data:image/png;base64,...` 或纯 base64（渲染前统一剥前缀）。
  final String imageBase64;
  final String url;

  /// 去掉 `data:image/png;base64,` 前缀，交给 `base64Decode`。
  String get rawBase64 {
    final int index = imageBase64.indexOf('base64,');
    return index >= 0 ? imageBase64.substring(index + 7) : imageBase64;
  }
}

/// 扫码状态机（酷狗约定）。
enum QrLoginStatus {
  expired,
  waiting,
  scanned,
  confirmed,
  unknown;

  static QrLoginStatus fromCode(Object? code) {
    switch (JsonUtils.integer(code, fallback: -1)) {
      case 0:
        return QrLoginStatus.expired;
      case 1:
        return QrLoginStatus.waiting;
      case 2:
        return QrLoginStatus.scanned;
      case 4:
        return QrLoginStatus.confirmed;
      default:
        return QrLoginStatus.unknown;
    }
  }
}

/// 轮询结果：`status == confirmed` 时携带 token / userid。
class QrLoginCheck {
  const QrLoginCheck({
    required this.status,
    this.token = '',
    this.userid = '',
    this.nickname = '',
    this.message = '',
  });

  final QrLoginStatus status;
  final String token;
  final String userid;
  final String nickname;
  final String message;

  bool get isSuccess => status == QrLoginStatus.confirmed;
}

/// 扫码登录接口（全部由用户在软件界面内操作，助手不代扫码）。
class KugouLoginApi {
  KugouLoginApi(this._client);

  final KugouClient _client;

  /// 生成二维码：先拿 key，再取图片。
  Future<LoginQr> createQr() async {
    final Map<String, dynamic> keyJson = await _client.getJson('/login/qr/key');
    final Map<String, dynamic> keyData =
        JsonUtils.asMap(keyJson['data']) ?? <String, dynamic>{};
    final String key = JsonUtils.str(keyData['qrcode'] ?? keyData['key']);
    if (key.isEmpty) {
      throw const KugouApiException('二维码生成失败：未返回 key');
    }

    final Map<String, dynamic> createJson = await _client.getJson(
      '/login/qr/create',
      query: <String, dynamic>{'key': key, 'qrimg': 'true'},
    );
    final Map<String, dynamic> createData =
        JsonUtils.asMap(createJson['data']) ?? <String, dynamic>{};
    final String base64 = JsonUtils.str(
      createData['base64'] ?? keyData['qrcode_img'],
    );
    if (base64.isEmpty) {
      throw const KugouApiException('二维码生成失败：未返回图片');
    }
    return LoginQr(
      key: key,
      imageBase64: base64,
      url: JsonUtils.str(createData['url']),
    );
  }

  /// 轮询扫码状态。
  Future<QrLoginCheck> check(String key) async {
    final Map<String, dynamic> json = await _client.getJson(
      '/login/qr/check',
      query: <String, dynamic>{'key': key},
    );
    final Map<String, dynamic> data =
        JsonUtils.asMap(json['data']) ?? <String, dynamic>{};
    return QrLoginCheck(
      status: QrLoginStatus.fromCode(data['status'] ?? json['status']),
      token: JsonUtils.str(data['token']),
      userid: JsonUtils.str(data['userid']),
      nickname: JsonUtils.str(data['nickname'] ?? data['username']),
      message: JsonUtils.str(json['message'] ?? data['message']),
    );
  }
}
