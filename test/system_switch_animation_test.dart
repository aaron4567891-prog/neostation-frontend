import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neostation/services/system_switch_animation_preferences.dart';

void main() {
  test('defaults, speeds, instant and persistence', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = SystemSwitchAnimationPreferences.instance;
    await preferences.load();
    expect(preferences.style, 'Horizontal slide');
    expect(preferences.duration.inMilliseconds, 220);
    await preferences.setSpeed('Fast');
    expect(preferences.duration.inMilliseconds, 120);
    await preferences.setSpeed('Slow');
    expect(preferences.duration.inMilliseconds, 400);
    await preferences.setStyle('Vertical slide');
    expect(
      (await SharedPreferences.getInstance()).getString(
        'system_switch_animation',
      ),
      'Vertical slide',
    );
    await preferences.setStyle('Instant');
    expect(preferences.duration, Duration.zero);
    await preferences.setStyle('invalid');
    expect(preferences.style, 'Instant');
  });
}
