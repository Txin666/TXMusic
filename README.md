<div align="center">
  <img src="https://raw.githubusercontent.com/Txin666/TX/refs/heads/main/TX%20Music/TX-MUSIC.ico" width="110" alt="TX Music logo">
</div>


<h1 align="center">TX Music</h1>

<h4 align="center">
    一个能免费每天领vip的神奇听歌软件
</h4>


<p align="center">
  <img alt="platform" src="https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?style=flat-square&logo=windows11&logoColor=white">
  <img alt="flutter" src="https://img.shields.io/badge/Flutter-desktop-02569B?style=flat-square&logo=flutter&logoColor=white">
  <img alt="version" src="https://img.shields.io/badge/version-3.2.11-4F8CFF?style=flat-square">
  <img alt="license" src="https://img.shields.io/badge/license-personal%20use-2EA043?style=flat-square">
</p>

<p align="center">
  <a href="https://github.com/Txin666/TXMusic/releases"><img alt="download" src="https://img.shields.io/badge/下载-最新发布包-4F8CFF?style=for-the-badge&logo=windows&logoColor=white"></a>
  &nbsp;
  <a href="https://txmusic.pages.dev/"><img alt="homepage" src="https://img.shields.io/badge/官网-txmusic.pages.dev-111827?style=for-the-badge&logo=googlechrome&logoColor=white"></a>
</p>
<img src="https://raw.githubusercontent.com/Txin666/TX/refs/heads/main/TX%20Music/home.png" alt="TX Music 主界面" width="100%">

## 这是什么

一个用 Flutter 写的 Windows 桌面音乐播放器。界面是自己画的，数据来自酷狗概念版，播放引擎走 `media_kit`，本地再挂一个 KuGouMusicApi 服务当数据层 —— 全部打包进发布包里，装完双击就能听。

## 界面一览

<table>
  <tr>
    <td width="10%"><img src="https://raw.githubusercontent.com/Txin666/TX/refs/heads/main/TX%20Music/Personal%20Information.png" alt="个人信息页">
        <br>
        <sub><b>个人信息页</b> · 个人信息与听歌数据</sub>
    </td>
  <tr>
      <tr>
    <td width="10%"><img src="https://raw.githubusercontent.com/Txin666/TX/refs/heads/main/TX%20Music/player.png" alt="播放页">
        <br>
        <sub><b>播放页</b> ·简洁播放器</sub>
    </td>
  <tr>
      <tr>
    <td width="10%"><img src="https://raw.githubusercontent.com/Txin666/TX/refs/heads/main/TX%20Music/playlist.png" alt="排行榜">
        <br>
        <sub><b>发现页</b> · 发现首页 / 每日推荐</sub>
    </td>
  <tr>
      <tr>
    <td width="10%"><img src="https://raw.githubusercontent.com/Txin666/TX/refs/heads/main/TX%20Music/Ranking%20List.png" alt="排行榜">
        <br>
        <sub><b>排行榜</b> · 同步更新每日榜单</sub>
    </td>
  <tr>


---

## 功能特性

| | 能力 | 说明 |
| :-- | :-- | :-- |
| **免费听歌** | 每日自动领 VIP | 登录后每天首次启动自动领 1 天概念版 VIP，设置页可手动补领 |
| **曲库** | 发现 / 榜单 / 搜索 | 轮播 Banner、推荐歌单、排行榜、关键词搜索 + 搜索建议 + 搜索历史 |
| **账号** | 酷狗账号同步 | 四种登录方式，同步我喜欢、收藏歌单、最近播放、听歌数据 |
| **播放** | 完整播放控制 | 播放/暂停/上一首/下一首、进度拖拽、音量、音质切换、自动连播、进度记忆续播 |
| **歌词** | 沉浸式歌词 | 独立播放页逐行高亮滚动，底部播放条也能内嵌滚动歌词 |
| **桌面融合** | 托盘与任务栏 | 自绘托盘面板、任务栏缩略图按钮（上一首/播放/暂停/下一首）、关闭窗口即收进托盘 |
| **外观** | 深色 / 浅色 / 跟随系统 | 深色为默认音乐播放器风格 |



### 登录方式

| 方式 | 说明 | 推荐度 |
| :-- | :-- | :-- |
| 手机验证码 | 输手机号收短信，验证码换 token | 最稳 |
| 酷狗 App 扫码 | 客户端出码，酷狗 App 扫一下 | 手机在手边 |
| 微信扫码 | 微信扫码，服务端换酷狗 token | 微信已登录 |
| QQ 扫码 | QQ 扫码，成功即带登录凭证 | QQ 已登录 |

未登录也能浏览发现页和榜单

### 日常操作

- **切歌**：主界面按钮，或任务栏缩略图上的上一首/播放/暂停/下一首
- **收进托盘**：直接点窗口关闭按钮，程序不退出，图标留在托盘
- **托盘面板**：点托盘图标弹出迷你控制面板
- **每日 VIP**：忘领了去「设置 → 每日 VIP → 立即领取」
- **换主题**：「设置 → 外观 → 深色 / 浅色 / 跟随系统」
- **退干净**：托盘菜单里退出，进程和端口一起释放

### 常见问题

| 现象 | 原因与处理 |
| :-- | :-- |
| 能刷列表，点播放没反应 | 未登录。登录后 `/song/url` 才给播放地址 |
| 启动后白屏几秒 | 内嵌服务在起，正常；久不恢复看 `txmusic_diag.log` |
| 提示端口被占用 | 会自动换空闲端口并写进 `kugou_api.json`，无需处理 |
| 杀进程后还剩 node.exe | 罕见，任务管理器手动结束 `kugou_api` 目录下的 node 即可 |
| 过几天要求重新登录 | token 过期，重登一次即可 |
| 某些音质放不了 | 该音质需 VIP 或受版权限制，切回标准音质；每日 VIP 能覆盖一部分 |
| 提示缺 `msvcp140.dll` | 发布包已内置 VC++ 运行库，正常解压不会出现；若仍报错说明拿的是旧包，重新下载即可，或手动装 [VC++ 2015-2022 运行库](https://aka.ms/vs/17/release/vc_redist.x64.exe) |

---

## 从源码运行

环境：Flutter SDK（stable / Dart 3.x）、Visual Studio 2022 或 2026（勾选「使用 C++ 的桌面开发」）、Windows 10/11 SDK。

```powershell
cd TXMusic
flutter pub get
flutter run -d windows
```



> 本项目仅供个人学习 Flutter 桌面开发使用，非官方客户端。曲库、账号与版权归酷狗所有，请勿商用或二次分发。
