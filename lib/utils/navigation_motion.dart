import 'package:flutter/animation.dart';

/// Motion shared by controller/keyboard selection scrolling.
///
/// A held direction repeats roughly every 80 ms, so its animation must finish
/// before the next step. A discrete tap gets a little more time, but remains
/// short enough to feel directly connected to the button press.
const Duration navigationScrollDuration = Duration(milliseconds: 240);
const Duration repeatNavigationScrollDuration = Duration(milliseconds: 70);
const Curve navigationScrollCurve = Curves.easeOutCubic;
