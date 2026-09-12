import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists and applies whether controller input follows bottom-screen focus.
class BottomControllerInputSettings {
  BottomControllerInputSettings._();

  static const _preferenceKey = 'bottom_controller_input_enabled';
  static const _channel = MethodChannel(
    'com.neogamelab.neostation/secondary_display',
  );

  static Future<bool> isEnabled() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_preferenceKey) ?? true;
  }

  static Future<void> setEnabled(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_preferenceKey, enabled);
    try {
      await _channel.invokeMethod<void>('setBottomControllerInputEnabled', {
        'enabled': enabled,
      });
    } on MissingPluginException {
      // Secondary-display controls are Android-only.
    } on PlatformException {
      // The preference is still persisted and will apply after app restart.
    }
  }
}
