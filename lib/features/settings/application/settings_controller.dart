import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 应用设置状态（骨架期内存态；持久化见文档 §8）。
@immutable
class SettingsState {
  const SettingsState({
    this.themeMode = ThemeMode.dark,
    this.desktopLyricEnabled = false,
    this.showLyricOnBar = true,
    this.audioQuality = AudioQuality.high,
    this.autoPlayNext = true,
  });

  final ThemeMode themeMode;
  final bool desktopLyricEnabled;
  final bool showLyricOnBar;
  final AudioQuality audioQuality;
  final bool autoPlayNext;

  SettingsState copyWith({
    ThemeMode? themeMode,
    bool? desktopLyricEnabled,
    bool? showLyricOnBar,
    AudioQuality? audioQuality,
    bool? autoPlayNext,
  }) {
    return SettingsState(
      themeMode: themeMode ?? this.themeMode,
      desktopLyricEnabled: desktopLyricEnabled ?? this.desktopLyricEnabled,
      showLyricOnBar: showLyricOnBar ?? this.showLyricOnBar,
      audioQuality: audioQuality ?? this.audioQuality,
      autoPlayNext: autoPlayNext ?? this.autoPlayNext,
    );
  }
}

/// 音质阶梯（文档 §6 音质降级顺序）。
enum AudioQuality { standard, high, lossless, hifi }

extension AudioQualityX on AudioQuality {
  String get label {
    switch (this) {
      case AudioQuality.standard:
        return '标准 128k';
      case AudioQuality.high:
        return '高品质 320k';
      case AudioQuality.lossless:
        return '无损 FLAC';
      case AudioQuality.hifi:
        return 'Hi-Res';
    }
  }
}

/// 设置编排：主题、桌面歌词、音质等。
/// TODO(storage): 落地时写入 Hive `settings` box（`services/storage/dao/settings_dao.dart`）。
class SettingsController extends Notifier<SettingsState> {
  @override
  SettingsState build() => const SettingsState();

  void setThemeMode(ThemeMode mode) =>
      state = state.copyWith(themeMode: mode);

  void setDesktopLyricEnabled(bool enabled) =>
      state = state.copyWith(desktopLyricEnabled: enabled);

  void setShowLyricOnBar(bool enabled) =>
      state = state.copyWith(showLyricOnBar: enabled);

  void setAudioQuality(AudioQuality quality) =>
      state = state.copyWith(audioQuality: quality);

  void setAutoPlayNext(bool enabled) =>
      state = state.copyWith(autoPlayNext: enabled);
}

final settingsControllerProvider =
    NotifierProvider<SettingsController, SettingsState>(SettingsController.new);
