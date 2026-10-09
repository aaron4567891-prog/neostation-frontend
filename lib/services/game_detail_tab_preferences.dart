import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/game_screen/game_details_card/detail_tab.dart';

/// Global, device-local visibility preferences for the game details tabs.
class GameDetailTabPreferences extends ChangeNotifier {
  GameDetailTabPreferences._();
  static final instance = GameDetailTabPreferences._();
  static const _key = 'game_details_hidden_tabs';
  final Set<String> _hidden = {};
  Future<void>? _loading;

  bool isVisible(DetailTab tab) => !_hidden.contains(tab.name);

  // Screenshots and achievements may be unavailable for a particular game.
  // Keep one unconditional tab so navigation can never have an empty list.
  static const _unconditional = [
    DetailTab.wheel,
    DetailTab.box2d,
    DetailTab.media,
    DetailTab.video,
    DetailTab.gameInfo,
  ];

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _hidden.addAll(prefs.getStringList(_key) ?? []);
    if (!_unconditional.any(isVisible)) {
      _hidden.remove(DetailTab.wheel.name);
    }
    notifyListeners();
  }

  Future<void> setVisible(DetailTab tab, bool visible) async {
    await load();
    if (!visible &&
        _unconditional.contains(tab) &&
        !_unconditional.any((other) => other != tab && isVisible(other))) {
      return;
    }
    if (visible) {
      _hidden.remove(tab.name);
    } else {
      _hidden.add(tab.name);
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, _hidden.toList());
  }

  static String label(DetailTab tab) => switch (tab) {
    DetailTab.wheel => 'Logo artwork',
    DetailTab.box2d => 'Box art',
    DetailTab.media => 'Physical media',
    DetailTab.video => 'Video',
    DetailTab.screenshotVideo => 'Screenshot',
    DetailTab.gameInfo => 'Game information',
    DetailTab.achievements => 'Achievements',
  };
}
