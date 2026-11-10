---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 504ce13ce28b6e0c6f1a433469ea3349_0fcb6443dc9511f19280525400393706
    ReservedCode1: Ou5S28TtW48thPXX40x1yszO7MiO33oWxUZJZ2qEThjB70FFfGs4ekgLvoC6K0kxxLF0ng4Z9PJhOak8ntEOV4UCjFpiWgQ2rwrWl94/1x9dfE5xjVI2Gd1EpKZvz2Uf5blRi1Z/k9rndoTJRns2JZJlsozh1u00MCuKEnTyR8rLl05LT87yXSmNzU8=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 504ce13ce28b6e0c6f1a433469ea3349_0fcb6443dc9511f19280525400393706
    ReservedCode2: Ou5S28TtW48thPXX40x1yszO7MiO33oWxUZJZ2qEThjB70FFfGs4ekgLvoC6K0kxxLF0ng4Z9PJhOak8ntEOV4UCjFpiWgQ2rwrWl94/1x9dfE5xjVI2Gd1EpKZvz2Uf5blRi1Z/k9rndoTJRns2JZJlsozh1u00MCuKEnTyR8rLl05LT87yXSmNzU8=
---



# TX Music × KuGouMusicApi 真实接口联调记录

> 联调日期：2026-11-09
> 服务端：本地自建 KuGouMusicApi v1.6.3（`D:\tengxin\Desktop\Flutter\KuGouMusicApi`，`node app.js`，Node v22.12.0）
> 地址：`http://localhost:3000`
> 原始样本：`docs/samples/*.json`（真实响应，未编辑）

---

## 一、服务状态

| 项 | 结果 |
|---|---|
| 启动 | 成功，日志 `server running @ http://localhost:3000` |
| 依赖 | npm install 完成，311 包 |
| 端口 | 3000 可用 |
| 响应缓存 | `cache-control: max-age=120`（服务端 2 分钟缓存，请求需带时间戳绕过） |

---

## 二、实测接口清单

| 接口 | 方法 | 实测结果 | 样本 |
|---|---|---|---|
| `/register/dev` | GET | 200，返回 `dfid` | `register_dev.json` |
| `/search` | GET | 200，total=480，真实歌曲列表 | `search.json` |
| `/song/url` | GET | 不带 `free_part=1` → **errcode 20028 本次请求需要验证**；带 `free_part=1` + dfid cookie → 200 拿到 URL | `song_url.json` |
| `/song/url/new` | GET | 200，返回明文 URL 数组 + 完整元数据（bitrate/extname/duration/image） | `song_url_new.json` |
| `/rank/list` | GET | 200，`data.info` = 56 个榜单 | `rank_list.json` |
| `/top/playlist` | GET | 200，`data.special_list` = 35 个推荐歌单 | `top_playlist.json` |
| `/lyric` | GET | **502**，需 `id` + `accesskey`（不是 hash），搜索结果不返回 accesskey，暂不可用 | — |
| `/search/complex` | GET | **error_code 152**，lists 全空，需登录态 | — |

---

## 三、关键约束（实测修正原文档）

1. **dfid 必须以 cookie 形式贯穿后续请求**
   `/register/dev` 只负责下发 dfid，不会在服务端"记住"。
   原文档写"先取 dfid 再取 URL"不够——正确做法是：取到 dfid 后，所有后续请求都带 `Cookie: dfid=<dfid>`。
   否则 `/song/url` 每次内部随机 dfid（`song_url.js:50`），签名校验必然失败。

2. **`/song/url` 必须加 `free_part=1`**
   不加则固定返回 `errcode 20028 / status 2 / "本次请求需要验证"`（附 edt 加密串）。

3. **未登录只能试听前 60 秒（阻断性限制）**
   - 返回 `trans_param.hash_offset.end_ms = 60000`，URL 内含 `p_0_960115`（字节偏移切片）
   - 实测音频文件 0.92 MB，按 128k 折算约 59 秒
   - 完整曲目 320k 约 10.7 MB

4. **音质被强制降级**
   请求 `quality=128/320/flac/flac24bit`，`/song/url/new` 一律返回 `bitrate=320, extname=mp3, fail_process=12`（降级标记）。高音质需登录 + VIP。

5. **音频 URL 可直连播放**
   实测 `Range: bytes=0-2047` → `206 Partial Content`，`Content-Type: audio/mpeg`，首字节 `ID3`。media_kit 可直接播该 URL。

---

## 四、DTO 反推

### SongItem（来自 `/search` 的 `data.lists[]`，共 73 个核心字段 + HQ/SQ 变体）

```dart
class SongItem {
  final String hash;        // FileHash，播放寻址主键
  final String? hqHash;     // HQFileHash（320k）
  final String? sqHash;     // SQFileHash（无损）
  final String name;        // SongName
  final String artist;      // SingerName
  final int albumId;        // AlbumID
  final String albumName;   // AlbumName
  final int duration;       // Duration（秒）
  final String? cover;      // Image / AlbumImage，含 {size} 占位需替换
  final int privilege;      // Privilege 10=可播 / 0=不可播
  final int payType;        // PayType 3=付费
  final int mixSongId;      // MixSongID，用于 /song/url/new
  final int bitrate;        // Bitrate
  final String extName;     // ExtName
}
```

> 注意：`Image` 字段形如 `http://imge.kugou.com/stdmusic/{size}/...`，`{size}` 需替换为 240/400/480 等。

### PlayUrlResult（来自 `/song/url?free_part=1`）

| 字段 | 含义 |
|---|---|
| `url[]` | 主播放地址数组（取 [0]） |
| `backupUrl[]` | 备用地址 |
| `timeLength` | 曲目总时长（注意：与 hash_offset 的 60s 限制不一致） |
| `trans_param.hash_offset` | 试听切片边界（end_ms=60000） |
| `status` | 1=成功，2=需验证 |
| `errcode` | 20028 = 需验证 |

### RankInfo（来自 `/rank/list` 的 `data.info[]`，56 项）

`rankname` / `base_img` / `img_9` / `play_times` / `update_frequency_type` / `classify` / `children[]`

### PlaylistItem（来自 `/top/playlist` 的 `data.special_list[]`，35 项）

`specialid` / `singername`(标题) / `nickname` / `percount` / `collectcount` / `flexible_cover` / `tags`

---

## 五、结论与待决问题

**已打通**：搜索 → 歌曲元数据 → 播放地址 → 音频直连播放，整链路真实可用，DTO 已校准到实测字段。

**阻断点**：未登录只能拿 60 秒试听片段，播放器体验不可接受。

**待决**：需酷狗账号登录以获取完整曲目与高音质。
- 可选路径：`/login/qr`（扫码，需用户手机操作）/ `/login/cellphone`（手机号+验证码，有风控冷却）
- 风险：登录态 cookie 有效期有限，需持久化并处理失效重登

**下一步**：登录方案落地后，再接入 media_kit 播放器，替换 `fake_*_data.dart`。
*（内容由AI生成，仅供参考）*

---

## 六、登录态落地（2026-11-09 实测完成）

### 6.1 扫码登录链路（三步）

| 步骤 | 接口 | 关键返回 |
|---|---|---|
| 1. 取二维码 | `GET /login/qr/key?type=web` | `data.qrcode`（key）、`data.qrcode_img`（`data:image/png;base64,...`，387×387） |
| 2. 生成图片 | 本地解码 base64 存 PNG | 也可 `GET /login/qr/create?key=<key>&qrimg=true` |
| 3. 轮询状态 | `GET /login/qr/check?key=<key>`（带 dfid cookie） | `data.status`：0=过期 1=待扫 2=待确认 **4=成功**；status=4 时返回 `data.token` / `data.userid` / `data.nickname` / `data.pic` |

- 轮询间隔 1~2 s；二维码有效期约 120 s，过期重新取 key。
- 登录成功后服务端会把 `token`、`userid` 追加进响应 cookie：`token=<token>; userid=<userid>`。

### 6.2 登录态 cookie 组成（必须四件套一起带）

```
dfid=<dfid>; userid=<userid>; token=<token>
```

实测：未带 cookie 时 `/user/detail` 匿名返回；带上述 cookie 返回 `nickname=蜡笔小鑫, vip_type=0`。
dfid 必须是登录时那一个（换新 dfid 也能识别登录态，但建议固定复用，避免风控）。

### 6.3 登录后实测变化（对比第三章）

| 项 | 未登录 | 登录后（普通账号，非 VIP） |
|---|---|---|
| `/search/complex` | error_code 152，lists 空 | **status=1，error_code=0，正常返回** |
| `/song/url?free_part=1` 免费曲目 | 60 s 切片（≈0.92 MB） | **完整全曲**：143 s 曲 → 2381792 B ≈ 148.9 s；178 s 曲 → 2852197 B ≈ 178.3 s，与 `timeLength` 一致 |
| 付费/VIP 曲目（《晴天》《夜曲》《起风了》《海阔天空》） | 60 s 试听 | `status=502` 无 URL 或仍 60 s；`pay_block_tpl=1`、`privilege` 受限 —— **属版权/付费限制，非登录失败** |
| 音质 | 128k mp3 | 仍 **128k mp3**：`quality=128/320/flac` 返回同一文件（URL 含 `qu128`），非 VIP 强制降级 |
| URL 特征 | `p_0_960115`（切片偏移） | 无切片偏移，含 `us<userid>_df<dfid>` 用户标识 |

> 结论：登录解除了「只有 60 秒」的阻断，但**音质上限仍是 128k**；付费曲目需 VIP/购买，播放器需对 502 / 空 url 做降级提示（置灰 + 提示"需 VIP"）。

### 6.4 登录态持久化

- 文件：`txmusic/.local/kugou_cookie.json`（已加入 `.gitignore` 的 `.local/`，不入库）
- 字段：`cookie`（拼好的四件套整串）、`dfid`、`userid`、`token`、`nickname`、`vip_type`、`base_url`、`saved_at`
- Dart 端建议：启动时读该文件，Dio 拦截器统一注入 `Cookie`；任一接口返回 `error_code=152` / `token` 失效 → 清空并跳扫码登录页。

### 6.5 服务稳定性（重要）

- `/song/url/auth/merge`（高音质授权链路）在上游失败时会因 `authData.body` 解构 `undefined` 抛未捕获异常，**Node 22 下直接崩进程**（实测崩了两次）。已在本机 `module/song_url_auth_merge.js` 打最小加固补丁（改为可选链 + resolve 502）。
- 启动服务的推荐命令（未捕获异常只告警不退出）：
  `node --unhandled-rejections=warn app.js`
- 该接口当前仍返回 `error_code 35002 parameter incomplete`（缺 `auth`/`mid` 等），暂不可用；**播放走 `/song/url?free_part=1` + cookie 即可**。

---

## 7. 客户端真实接入与播放落地（2026-11-09）

客户端已从骨架期假数据切换到真实链路：**搜索 → 解析音源 → media_kit 解码播放**。

### 7.1 新增/改造文件

| 层 | 文件 | 职责 |
|---|---|---|
| core | `lib/core/network/kugou_config.dart` | 服务地址、时间戳防缓存、`.local` 定位（自可执行文件目录向上回溯 9 层，兼容 `build\windows\x64\runner\Debug` 下直接双击运行） |
| core | `lib/core/network/kugou_session.dart` | 读取/保存登录 cookie（dfid/userid/token/nickname），无文件时落游客态 |
| core | `lib/core/network/kugou_client.dart` | 统一 GET/POST，自动注入 `dfid` 等 cookie、加时间戳、把 `error_code`/HTTP 异常收敛为 `KugouApiException` |
| core | `lib/core/network/kugou_providers.dart` | `kugouSessionProvider` / `kugouClientProvider` / API Provider 注入，支持 `main.dart` override |
| core | `lib/core/audio/i_audio_engine.dart` | 引擎抽象（open/play/pause/seek/事件流），便于替换与测试 |
| core | `lib/core/audio/media_kit_audio_engine.dart` | media_kit 实现，直连 mp3 URL |
| song | `lib/features/song/data/kugou_song_api.dart` | `/search/song` JSON → `Song`（hash/albumId/时长秒→Duration/封面模板串） |
| player | `lib/features/player/data/song_url_resolver.dart` | `/song/url?free_part=1` → `ResolvedAudio(url, backupUrl, duration)` |
| player | `lib/features/player/application/player_controller.dart` | 异步解析音源 + 引擎事件驱动快照，含竞态保护与 `errorMessage` 落态 |
| search | `lib/features/search/application/search_controller.dart` | 真实搜索 + `isLoading`/`errorMessage` + 请求竞态丢弃 |
| app | `lib/main.dart` | 启动加载登录态、`MediaKit.ensureInitialized()`、Provider override |

### 7.2 实测记录

- 依赖：`http`、`media_kit`、`media_kit_libs_windows_audio`（`flutter pub get` OK）
- 接口冒烟（`test/kugou_api_smoke_test.dart`）：`/search/song` 命中、`Song` 字段映射非空、`/song/url` 返回可播放 http 地址，3 项全过
- 解码冒烟（`test/media_playback_smoke_test.dart`）：media_kit 真实播放《晴天》→ `duration=0:04:29.79`，position 由 0 连续推进至 5.79 s，`errors=[]`
  - 运行前提：`$env:PATH = "$PWD\build\windows\x64\runner\Debug;$env:PATH"`（提供 `libmpv-2.dll`）
  - flutter_test 默认把 HttpClient 拦成 400，需 `HttpOverrides.global = null` 才能走真实网络
- 构建：`flutter build windows --debug` 成功；`flutter analyze` No issues found

### 7.2.1 第二轮实测修复（2026-11-10）

验证脚本：`test/kugou_api_fixes_smoke_test.dart`（真实请求本地 `localhost:3000`，7 项全过）

| 问题 | 实测现象 | 修复 |
|---|---|---|
| 响应体带 HTML 注释前缀 | 部分接口返回 `<!--KG_TAG_RES_START-->{...}<!--KG_TAG_RES_END-->`，`jsonDecode` 直接抛 FormatException | `KugouClient.sanitizeBody` 剥离 BOM/前后注释/内部注释后再解析；解析失败时把响应前 60 字符带进异常便于排查 |
| 成功码判定过严 | `/lyric`、`/search/lyric` 的 `status=200`、`errcode=200` 被判为失败 | `_isOkErrorCode`（0/200）、`_isOkStatus`（1/200）统一兼容 |
| `/search/complex` 不稳定 | 实测存在 `error_code 152 Parameter Error`；`/search/playlist` `/search/author` `/search/album` 只回歌曲列表，不能撑分区 | 搜索页改为 `bundle()`：主链路 `/search` 单曲（失败才整页报错），`/search/complex` 仅补分区且失败静默降级；分区为空时 UI 隐藏分区并显示降级提示条 |
| 歌词 base64 | `/lyric?decode=true` 的 `content` 仍是 base64，`decodeContent` 可能缺失 | `KugouLyricApi.decodeIfBase64` 兜底解码；LRC 解析兼容 `\r\n`；歌词请求异常降级为空文档 |
| 歌单 ID | `/playlist/detail`、`/playlist/track/all` 只认 `global_collection_id`（`collection_x_y_z`）；传 specialid 时详情空、曲目 HTTP 502 | `Playlist.collectionId`/`hasCollectionId` 收敛 ID；`KugouPlaylistApi.normalizeCollectionId` 拦截非 collection ID；502 与空数据降级为「暂无曲目/暂不支持查看」，详情页对非 collection ID 提前提示 |

实测输出摘录：

```
[search] songs=10 playlists=5 artists=0 albums=6 partitionsAvailable=true
[degrade] songs=5 partitionsAvailable=false        // complex 强制失败时仍返回单曲
[lyric] lines=63 firstLines=[晴天 - 周杰伦 (Jay Chou), 词：周杰伦, 曲：周杰伦]
[playlist] total=40 withCollection=40 sampleIds=[collection_3_xxx_...]
[playlist/detail] title=... songCount=41
[playlist/track/all] tracks=10 first=...
```

结果：`dart analyze lib test` No issues found；`flutter test` 22 项全过。

### 7.3 踩坑

- **libmpv 下载被截断**：`media_kit_libs_windows_audio` 通过 CMake `file(DOWNLOAD)` 从 GitHub Releases 拉 `mpv-dev-x86_64-20230924-git-652a1dd.7z`，本机直连 GitHub 失败（schannel 吊销检查/连接被断），生成 0 字节文件 → 报 `Integrity check failed`。
  - 解法：用镜像下载同一文件并校验 MD5 `cd738e16e2a19626d7cfa48801524f8c`，放到 `build\windows\x64\` 后再 build：
    `curl -L -o build\windows\x64\mpv-dev-x86_64-20230924-git-652a1dd.7z https://ghfast.top/https://github.com/media-kit/libmpv-win32-audio-build/releases/download/2023-09-24/mpv-dev-x86_64-20230924-git-652a1dd.7z`
- **登录态找不到**：cookie 查找最初只回溯 5 层，从 `Debug` 目录启动时够不到工程根 → 自动落游客态（仅 60 s）。已改为回溯 9 层。

### 7.4 待办

- 搜索页歌单/歌手分区仍为骨架空集（待接 `/search/playlist`）；热词榜、发现页、榜单仍为假数据
- 搜索历史未落盘（TODO: Hive）
- 付费/VIP 曲 `502` 的 UI 降级（置灰 + "需 VIP" 提示）尚未做
- 播放失败时已在迷你播放条副标题位置显示 `errorMessage`，但全屏播放页尚未展示
*（内容由AI生成，仅供参考）*
