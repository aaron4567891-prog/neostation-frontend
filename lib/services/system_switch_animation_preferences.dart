import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SystemSwitchAnimationPreferences {
  SystemSwitchAnimationPreferences._();
  static final instance = SystemSwitchAnimationPreferences._();
  static const styles = [
    'Horizontal slide',
    'Vertical slide',
    'Fade',
    'Instant',
  ];
  static const speeds = ['Normal', 'Fast', 'Slow'];
  String style = styles.first;
  String speed = speeds.first;
  Future<void>? _loading;

  Future<void> load() => _loading ??= _load();
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedStyle = prefs.getString('system_switch_animation');
    final savedSpeed = prefs.getString('system_switch_speed');
    if (styles.contains(savedStyle)) style = savedStyle!;
    if (speeds.contains(savedSpeed)) speed = savedSpeed!;
  }

  Future<void> setStyle(String value) async {
    await load();
    if (!styles.contains(value)) return;
    style = value;
    await (await SharedPreferences.getInstance()).setString(
      'system_switch_animation',
      value,
    );
  }

  Future<void> setSpeed(String value) async {
    await load();
    if (!speeds.contains(value)) return;
    speed = value;
    await (await SharedPreferences.getInstance()).setString(
      'system_switch_speed',
      value,
    );
  }

  Duration get duration => Duration(
    milliseconds: style == 'Instant'
        ? 0
        : speed == 'Fast'
        ? 120
        : speed == 'Slow'
        ? 400
        : 220,
  );

  Widget transition(Animation<double> animation, Widget child, bool forward) {
    if (style == 'Instant') return child;
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    if (style == 'Fade') return FadeTransition(opacity: curved, child: child);
    final offset = style == 'Vertical slide'
        ? Offset(0, forward ? 1 : -1)
        : Offset(forward ? 1 : -1, 0);
    return SlideTransition(
      position: Tween<Offset>(begin: offset, end: Offset.zero).animate(curved),
      child: child,
    );
  }
}
