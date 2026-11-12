import 'package:hive_flutter/hive_flutter.dart';

import 'package:tents/domain/models/app_settings.dart';

class SettingsService {
  static const String _boxName = 'tents_settings';

  Future<void> init() async {
    await Hive.openBox(_boxName);
  }

  AppSettings getSettings() {
    final box = Hive.box(_boxName);
    final isHintEnabled = box.get('hint_enabled', defaultValue: false) as bool;
    final isCheckButtonEnabled = box.get('check_button_enabled', defaultValue: false) as bool;
    final isTentCrossButtonsEnabled = box.get('tent_cross_buttons_enabled', defaultValue: false) as bool;
    final themeId = box.get('app_theme', defaultValue: 'pastelButter') as String?;
    final resolvedTheme = AppThemePreset.fromId(themeId);
    final selectedGameScript = box.get('selected_game_script') as String?;
    final autoRunSelectedGameScript =
        box.get('auto_run_selected_game_script', defaultValue: false) as bool;
    return AppSettings(
      isHintEnabled: isHintEnabled,
      isCheckButtonEnabled: isCheckButtonEnabled,
      isTentCrossButtonsEnabled: isTentCrossButtonsEnabled,
      theme: resolvedTheme,
      selectedGameScript: selectedGameScript,
      autoRunSelectedGameScript: autoRunSelectedGameScript,
    );
  }

  Future<void> saveSettings(AppSettings settings) async {
    final box = Hive.box(_boxName);
    await box.put('hint_enabled', settings.isHintEnabled);
    await box.put('check_button_enabled', settings.isCheckButtonEnabled);
    await box.put('tent_cross_buttons_enabled', settings.isTentCrossButtonsEnabled);
    await box.put('app_theme', settings.theme.id);
    if (settings.selectedGameScript == null) {
      await box.delete('selected_game_script');
    } else {
      await box.put('selected_game_script', settings.selectedGameScript);
    }
    await box.put(
      'auto_run_selected_game_script',
      settings.autoRunSelectedGameScript,
    );
  }
}
