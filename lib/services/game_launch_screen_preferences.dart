import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/game_model.dart';
import '../models/system_model.dart';

/// Device-local per-system defaults and per-game overrides.
class GameLaunchScreenPreferences {
  static String _systemKey(String folder) =>
      'launch_screen_system_${jsonEncode(folder)}';
  static String _gameKey(String folder, String romname) =>
      'launch_screen_game_${jsonEncode([folder, romname])}';
  static bool supports(String? id, String folder) =>
      id != 'nds' && id != '3ds' && folder != 'nds' && folder != '3ds';
  static Future<String> systemChoice(String folder) async =>
      (await SharedPreferences.getInstance()).getString(_systemKey(folder)) ==
          'bottom'
      ? 'bottom'
      : 'top';
  static Future<String> gameChoice(String folder, String romname) async {
    final value = (await SharedPreferences.getInstance()).getString(
      _gameKey(folder, romname),
    );
    return value == 'top' || value == 'bottom' ? value! : 'default';
  }

  static Future<void> saveSystem(String folder, String value) async {
    if (value != 'top' && value != 'bottom') return;
    await (await SharedPreferences.getInstance()).setString(
      _systemKey(folder),
      value,
    );
  }

  static Future<void> saveGame(
    String folder,
    String romname,
    String value,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == 'default') {
      await prefs.remove(_gameKey(folder, romname));
    } else if (value == 'top' || value == 'bottom') {
      await prefs.setString(_gameKey(folder, romname), value);
    }
  }

  static Future<String> resolveChoice(String folder, String romname) async {
    final choice = await gameChoice(folder, romname);
    return choice == 'default' ? await systemChoice(folder) : choice;
  }

  static Future<String> resolve(SystemModel system, GameModel game) async {
    final folder = game.systemFolderName ?? system.folderName;
    if (!supports(game.systemId ?? system.id, folder)) return 'top';
    return resolveChoice(folder, game.romname);
  }
}
