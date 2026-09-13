import 'package:flutter/material.dart';
import 'package:neostation/themes/dark_theme.dart';
import 'package:neostation/themes/chrome_surface.dart';
import 'package:neostation/themes/corner_radii.dart';

/// Original CRT-inspired styling, not an import of Cathode's ES-DE assets.
final ThemeData cathodeTheme = darkTheme.copyWith(
  colorScheme: darkTheme.colorScheme.copyWith(
    primary: const Color(0xFFFF695E),
    onPrimary: const Color(0xFF210504),
    primaryContainer: const Color(0xFF54221D),
    onPrimaryContainer: const Color(0xFFFFDAD4),
    secondary: const Color(0xFFFFC078),
    onSecondary: const Color(0xFF251406),
    tertiary: const Color(0xFFA6D9BD),
    onTertiary: const Color(0xFF10271B),
    surface: const Color(0xFF121515),
    onSurface: const Color(0xFFE8E5D7),
    onSurfaceVariant: const Color(0xFFCBC5B5),
    outline: const Color(0xFF896457),
  ),
  scaffoldBackgroundColor: const Color(0xFF080B0B),
  cardColor: const Color(0xFF151919),
  dividerColor: const Color(0xFF896457),
  extensions: [
    CornerRadii.s(),
    const ChromeSurface(
      opacity: 0.88,
      fadeLeading: 0.90,
      fadeTrailing: 0.62,
      fadeTrailingNarrow: 0.72,
    ),
  ],
);

/// Static, non-interactive decoration. No timers, blur, shaders or video layers.
class CathodeScreenOverlay extends StatelessWidget {
  const CathodeScreenOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return const Positioned.fill(
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: RepaintBoundary(child: CustomPaint(painter: _CrtPainter())),
        ),
      ),
    );
  }
}

class _CrtPainter extends CustomPainter {
  const _CrtPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scanline = Paint()
      ..color = const Color(0x12000000)
      ..strokeWidth = 1;
    for (double y = 0; y < size.height; y += 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), scanline);
    }
    final border = Paint()
      ..color = const Color(0x80FF695E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        (Offset.zero & size).deflate(5),
        const Radius.circular(14),
      ),
      border,
    );
  }

  @override
  bool shouldRepaint(covariant _CrtPainter oldDelegate) => false;
}
