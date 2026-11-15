import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 桌面端滚动行为：把鼠标左键拖拽补进可拖拽设备。
///
/// Flutter 默认的 [MaterialScrollBehavior.dragDevices] 只含触摸/触控笔/触控板，
/// **不含鼠标**——所以桌面端按住鼠标左键拖 PageView、横向卡片列表一律没反应；
/// 而竖直方向的滚轮也不会驱动水平 PageView。两者叠加，发现页顶部轮播图看起来
/// 就是「完全不能滑动」。
///
/// 挂到 [MaterialApp.scrollBehavior] 上即可全局生效，不必给每个横向列表单独套
/// [ScrollConfiguration]。
class DesktopScrollBehavior extends MaterialScrollBehavior {
  const DesktopScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => <PointerDeviceKind>{
    ...super.dragDevices,
    PointerDeviceKind.mouse,
  };
}
