import '../../../core/network/json_utils.dart';
import '../../../core/network/kugou_client.dart';

/// 剥掉 `data:image/png;base64,` 前缀，交给 `base64Decode`。
String _stripDataPrefix(String image) {
  final int index = image.indexOf('base64,');
  return index >= 0 ? image.substring(index + 7) : image;
}

/// 登录方式。四种方式各自对接不同接口，最终都收敛成 [LoginCredential]。
enum LoginMethod { kugouQr, sms, wechat, qq }

/// 登录凭证：手机 / 微信 / QQ / 酷狗扫码成功后的统一产物。
class LoginCredential {
  const LoginCredential({
    required this.token,
    required this.userid,
    this.nickname = '',
    this.vipType = '0',
    this.vipToken = '',
  });

  final String token;
  final String userid;
  final String nickname;
  final String vipType;
  final String vipToken;

  /// `userid` 可能是 `0`（服务端兜底值），不能当作有效登录。
  bool get isValid => token.isNotEmpty && userid.isNotEmpty && userid != '0';

  Map<String, dynamic> toJson() => <String, dynamic>{
    'token': token,
    'userid': userid,
    'nickname': nickname,
    'vip_type': vipType,
    'vip_token': vipToken,
  };
}

/// 酷狗 App 扫码会话：key 用于轮询，base64 直接渲染。
class LoginQr {
  const LoginQr({required this.key, required this.imageBase64, this.url = ''});

  final String key;

  /// `data:image/png;base64,...` 或纯 base64（渲染前统一剥前缀）。
  final String imageBase64;
  final String url;

  String get rawBase64 => _stripDataPrefix(imageBase64);
}

/// 酷狗扫码状态机（酷狗约定）。
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

/// 酷狗扫码轮询结果：`status == confirmed` 时携带 token / userid。
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

/// 微信开放平台扫码会话（`/login/wx/create`）。
class WechatQrSession {
  const WechatQrSession({
    required this.uuid,
    required this.imageBase64,
    this.url = '',
  });

  final String uuid;
  final String imageBase64;
  final String url;

  String get rawBase64 => _stripDataPrefix(imageBase64);
}

/// 微信扫码状态（微信开放平台约定）。
enum WechatScanStatus {
  /// 408：未扫码 / 等待扫码
  waiting,

  /// 404：已扫码，等待用户确认
  scanned,

  /// 403：用户拒绝授权
  refused,

  /// 402：二维码失效
  expired,

  /// 405：已确认，携带 `wx_code`
  confirmed,
  unknown;

  static WechatScanStatus fromCode(int code) {
    switch (code) {
      case 408:
        return WechatScanStatus.waiting;
      case 404:
        return WechatScanStatus.scanned;
      case 403:
        return WechatScanStatus.refused;
      case 402:
        return WechatScanStatus.expired;
      case 405:
        return WechatScanStatus.confirmed;
      default:
        return WechatScanStatus.unknown;
    }
  }
}

/// 微信扫码轮询结果：`confirmed` 时携带一次性 `code`，需再调 `/login/openplat` 换 token。
class WechatCheckResult {
  const WechatCheckResult({
    required this.status,
    this.code = '',
    this.message = '',
  });

  final WechatScanStatus status;
  final String code;
  final String message;
}

/// QQ 扫码会话：check 接口要求 create 返回的字段**原样回传**。
class QqQrSession {
  const QqQrSession({
    required this.imageBase64,
    required this.qrsig,
    required this.ptqrtoken,
    required this.ptLoginSig,
    required this.ptOpenloginData,
    required this.xloginUrl,
    required this.cookie,
  });

  final String imageBase64;
  final String qrsig;
  final String ptqrtoken;
  final String ptLoginSig;
  final String ptOpenloginData;
  final String xloginUrl;
  final String cookie;

  String get rawBase64 => _stripDataPrefix(imageBase64);
}

/// QQ 扫码状态（ptuiCB 返回码经服务端翻译）。
enum QqScanStatus {
  /// 66：等待扫码
  waiting,

  /// 67 / 其它中间码：已扫码，等待手机确认
  scanned,

  /// 65：二维码失效
  expired,

  /// 0：已确认，可直接拿到酷狗 token
  confirmed,
  unknown;

  static QqScanStatus fromCode(String code) {
    switch (code) {
      case '66':
        return QqScanStatus.waiting;
      case '65':
        return QqScanStatus.expired;
      case '0':
      case '1':
        return QqScanStatus.confirmed;
      case '67':
        return QqScanStatus.scanned;
      default:
        return QqScanStatus.unknown;
    }
  }
}

/// QQ 扫码轮询结果：`confirmed` 时直接携带登录凭证（服务端已换好酷狗 token）。
class QqCheckResult {
  const QqCheckResult({
    required this.status,
    this.credential,
    this.message = '',
  });

  final QqScanStatus status;
  final LoginCredential? credential;
  final String message;
}

/// 登录接口集合。
///
/// 四种方式全部由**用户本人在软件界面内操作**完成，助手不代收验证码、
/// 不代扫二维码、不接触账号密码：
/// - 手机登录：`/captcha/sent` 发码 → `/login/cellphone` 用验证码换 token；
/// - 微信扫码：`/login/wx/create` 出码 → `/login/wx/check` 轮询 → `/login/openplat` 换 token；
/// - QQ 扫码：`/login/qq/qr/create` 出码 → `/login/qq/qr/check` 轮询（成功即带 token）；
/// - 酷狗 App 扫码：`/login/qr/key` + `/login/qr/create` → `/login/qr/check`。
class KugouLoginApi {
  KugouLoginApi(this._client);

  final KugouClient _client;

  // ---------------------------------------------------------------- 酷狗扫码

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

  /// 轮询酷狗扫码状态。
  Future<QrLoginCheck> check(String key) async {
    final Map<String, dynamic> json = await _client.getJson(
      '/login/qr/check',
      query: <String, dynamic>{'key': key},
      lenient: true,
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

  // ---------------------------------------------------------------- 手机登录

  /// 发送短信验证码（`/captcha/sent`）。
  ///
  /// 服务端失败时以 `status: 0` 返回，[KugouClient.getJson] 会抛
  /// [KugouApiException]，这里再用宽松模式取原始错误文案，保证提示可读。
  Future<void> sendSmsCode(String mobile) async {
    final Map<String, dynamic> json = await _client.getJson(
      '/captcha/sent',
      query: <String, dynamic>{'mobile': mobile},
      lenient: true,
    );
    final int status = JsonUtils.integer(json['status'], fallback: -1);
    if (status == 1) {
      return;
    }
    throw KugouApiException(_errorText(json, fallback: '验证码发送失败，请稍后重试'));
  }

  /// 手机号 + 验证码登录（`/login/cellphone`）。
  Future<LoginCredential> loginBySms({
    required String mobile,
    required String code,
  }) async {
    final Map<String, dynamic> json = await _client.getJson(
      '/login/cellphone',
      query: <String, dynamic>{'mobile': mobile, 'code': code},
      lenient: true,
    );
    final int status = JsonUtils.integer(json['status'], fallback: -1);
    if (status != 1) {
      throw KugouApiException(_errorText(json, fallback: '登录失败：验证码错误或已过期'));
    }
    return _credentialFrom(json);
  }

  // ---------------------------------------------------------------- 微信扫码

  /// 生成微信扫码二维码（`/login/wx/create`）。
  Future<WechatQrSession> createWechatQr() async {
    final Map<String, dynamic> json = await _client.getJson(
      '/login/wx/create',
      lenient: true,
    );
    final int errcode = JsonUtils.integer(json['errcode'], fallback: -1);
    if (errcode != 0) {
      throw KugouApiException(
        _errorText(json, fallback: '微信二维码生成失败（errcode=$errcode）'),
      );
    }
    final String uuid = JsonUtils.str(json['uuid']);
    final Map<String, dynamic> qrcode =
        JsonUtils.asMap(json['qrcode']) ?? <String, dynamic>{};
    final String base64 = JsonUtils.str(qrcode['qrcodebase64']);
    if (uuid.isEmpty || base64.isEmpty) {
      throw const KugouApiException('微信二维码生成失败：返回缺少 uuid 或图片');
    }
    return WechatQrSession(
      uuid: uuid,
      imageBase64: base64,
      url: JsonUtils.str(qrcode['qrcodeurl']),
    );
  }

  /// 轮询微信扫码状态（`/login/wx/check`）。
  Future<WechatCheckResult> checkWechat(String uuid) async {
    final Map<String, dynamic> json = await _client.getJson(
      '/login/wx/check',
      query: <String, dynamic>{
        'uuid': uuid,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
      lenient: true,
    );
    final int errcode = JsonUtils.integer(json['wx_errcode'], fallback: -1);
    return WechatCheckResult(
      status: WechatScanStatus.fromCode(errcode),
      code: JsonUtils.str(json['wx_code']),
      message: JsonUtils.str(json['wx_errmsg'] ?? json['errmsg']),
    );
  }

  /// 用微信一次性 code 换酷狗登录态（`/login/openplat`）。
  Future<LoginCredential> loginByWechatCode(String code) async {
    final Map<String, dynamic> json = await _client.getJson(
      '/login/openplat',
      query: <String, dynamic>{'code': code},
      lenient: true,
    );
    final int status = JsonUtils.integer(json['status'], fallback: -1);
    if (status != 1) {
      throw KugouApiException(_errorText(json, fallback: '微信授权已失效，请刷新二维码重试'));
    }
    return _credentialFrom(json);
  }

  // ---------------------------------------------------------------- QQ 扫码

  /// 生成 QQ 扫码二维码（`/login/qq/qr/create`）。
  Future<QqQrSession> createQqQr() async {
    final Map<String, dynamic> json = await _client.getJson(
      '/login/qq/qr/create',
      lenient: true,
    );
    final String base64 = JsonUtils.str(json['qrcode']);
    final String qrsig = JsonUtils.str(json['qrsig']);
    if (base64.isEmpty || qrsig.isEmpty) {
      throw KugouApiException(_errorText(json, fallback: 'QQ 二维码生成失败'));
    }
    return QqQrSession(
      imageBase64: base64,
      qrsig: qrsig,
      ptqrtoken: JsonUtils.str(json['ptqrtoken']),
      ptLoginSig: JsonUtils.str(json['pt_login_sig']),
      ptOpenloginData: JsonUtils.str(json['pt_openlogin_data']),
      xloginUrl: JsonUtils.str(json['xlogin_url']),
      cookie: JsonUtils.str(json['cookie']),
    );
  }

  /// 轮询 QQ 扫码状态（`/login/qq/qr/check`）。
  ///
  /// 服务端要求 create 返回的五个会话字段**原样回传**，缺一即报
  /// 「缺少 xx」。成功时服务端已经用 code 换好了酷狗 token，直接返回凭证。
  Future<QqCheckResult> checkQqQr(QqQrSession session) async {
    final Map<String, dynamic> json = await _client.getJson(
      '/login/qq/qr/check',
      query: <String, dynamic>{
        'qrsig': session.qrsig,
        'ptqrtoken': session.ptqrtoken,
        'pt_login_sig': session.ptLoginSig,
        'pt_openlogin_data': session.ptOpenloginData,
        'xlogin_url': session.xloginUrl,
        'cookie': session.cookie,
      },
      lenient: true,
    );

    final String raw = JsonUtils.str(json['status']);
    final QqScanStatus status = QqScanStatus.fromCode(raw);
    if (status == QqScanStatus.confirmed) {
      return QqCheckResult(status: status, credential: _credentialFrom(json));
    }
    return QqCheckResult(
      status: status,
      message: JsonUtils.str(json['msg'] ?? json['error_msg']),
    );
  }

  // ---------------------------------------------------------------- 公共

  /// 从登录响应里取凭证：`token` / `userid` 都在 `data` 顶层。
  LoginCredential _credentialFrom(Map<String, dynamic> json) {
    final Map<String, dynamic> data =
        JsonUtils.asMap(json['data']) ?? <String, dynamic>{};
    final LoginCredential credential = LoginCredential(
      token: JsonUtils.str(data['token'] ?? json['token']),
      userid: JsonUtils.str(data['userid'] ?? json['userid']),
      nickname: JsonUtils.str(
        data['nickname'] ?? data['username'] ?? data['user_name'],
      ),
      vipType: JsonUtils.str(data['vip_type'], fallback: '0'),
      vipToken: JsonUtils.str(data['vip_token']),
    );
    if (!credential.isValid) {
      throw const KugouApiException('登录失败：服务端未返回有效 token / userid');
    }
    return credential;
  }

  /// 错误文案：按接口不同字段名逐个兜底，都没有再用 [fallback]。
  String _errorText(Map<String, dynamic> json, {required String fallback}) {
    final String text = JsonUtils.str(
      json['error_msg'] ??
          json['errmsg'] ??
          json['wx_errmsg'] ??
          json['msg'] ??
          json['message'],
    );
    if (text.isNotEmpty) {
      return text;
    }
    final Object? nested = json['msg'];
    final Map<String, dynamic>? nestedMap = JsonUtils.asMap(nested);
    if (nestedMap != null) {
      final String inner = JsonUtils.str(
        nestedMap['error_msg'] ?? nestedMap['errmsg'] ?? nestedMap['msg'],
      );
      if (inner.isNotEmpty) {
        return inner;
      }
    }
    return fallback;
  }
}
