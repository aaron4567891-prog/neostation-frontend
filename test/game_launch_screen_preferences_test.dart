import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neostation/services/game_launch_screen_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Top is default and system defaults are independent', () async {
    expect(
      await GameLaunchScreenPreferences.resolveChoice('ps2', 'Game'),
      'top',
    );
    await GameLaunchScreenPreferences.saveSystem('ps2', 'bottom');
    expect(
      await GameLaunchScreenPreferences.resolveChoice('ps2', 'Game'),
      'bottom',
    );
    expect(
      await GameLaunchScreenPreferences.resolveChoice('psp', 'Game'),
      'top',
    );
  });

  test('Per-game override wins and can return to system default', () async {
    await GameLaunchScreenPreferences.saveSystem('ps2', 'bottom');
    await GameLaunchScreenPreferences.saveGame('ps2', 'Game', 'top');
    expect(
      await GameLaunchScreenPreferences.resolveChoice('ps2', 'Game'),
      'top',
    );
    expect(
      await GameLaunchScreenPreferences.resolveChoice('ps2', 'Other'),
      'bottom',
    );
    await GameLaunchScreenPreferences.saveGame('ps2', 'Game', 'default');
    expect(
      await GameLaunchScreenPreferences.gameChoice('ps2', 'Game'),
      'default',
    );
    expect(
      await GameLaunchScreenPreferences.resolveChoice('ps2', 'Game'),
      'bottom',
    );
  });

  test('DS and 3DS keep dedicated dual-screen behavior', () {
    expect(GameLaunchScreenPreferences.supports('nds', 'Nintendo DS'), false);
    expect(GameLaunchScreenPreferences.supports('3ds', '3ds'), false);
    expect(GameLaunchScreenPreferences.supports('ps2', 'ps2'), true);
  });
}
