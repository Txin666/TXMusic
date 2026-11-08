import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// 占位封面：骨架期不加载网络图，用「文字指纹 → 渐变色」生成稳定视觉差异，
/// 接入真实接口后替换为 `Image.network(coverUrl)` + 缓存（文档 §5 图片加载策略）。
class CoverPlaceholder extends StatelessWidget {
  const CoverPlaceholder({
    super.key,
    required this.seed,
    this.size = 160,
    this.radius = 12,
    this.icon = Icons.music_note_rounded,
    this.label,
  });

  final String seed;
  final double size;
  final double radius;
  final IconData icon;
  final String? label;

  static const List<List<Color>> _palettes = <List<Color>>[
    <Color>[Color(0xFF1DB954), Color(0xFF0B3D2C)],
    <Color>[Color(0xFF6C5CE7), Color(0xFF1B1663)],
    <Color>[Color(0xFFE17055), Color(0xFF4A1E17)],
    <Color>[Color(0xFF00B8D9), Color(0xFF073B4C)],
    <Color>[Color(0xFFFF7675), Color(0xFF4A1B2A)],
    <Color>[Color(0xFFFDCB6E), Color(0xFF4A3A10)],
  ];

  List<Color> get _colors {
    if (seed.isEmpty) {
      return _palettes.first;
    }
    final int hash = seed.codeUnits.fold<int>(0, (int sum, int unit) => sum + unit);
    return _palettes[hash % _palettes.length];
  }

  @override
  Widget build(BuildContext context) {
    final List<Color> colors = _colors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: size * 0.28, color: Colors.white.withValues(alpha: 0.9)),
          if (label != null) ...<Widget>[
            const SizedBox(height: 6),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: size * 0.1),
              child: Text(
                label!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: size * 0.09,
                  color: Colors.white.withValues(alpha: 0.92),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
