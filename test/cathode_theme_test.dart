import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/providers/theme_provider.dart';
import 'package:neostation/themes/app_themes.dart';
import 'package:neostation/themes/cathode_theme.dart';
import 'package:neostation/themes/chrome_surface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('CRT theme is registered without replacing existing themes', () {
    expect(ThemeProvider.availableThemes.containsKey('cathode'), isTrue);
    expect(ThemeProvider.availableThemes.containsKey('dark'), isTrue);
    expect(AppThemes.getThemeDataByName('cathode').brightness, Brightness.dark);
    expect(cathodeTheme.extension<ChromeSurface>(), isNotNull);
  });

  testWidgets('CRT decoration does not intercept touch', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Center(
                child: TextButton(
                  onPressed: () => tapped = true,
                  child: const Text('Select system'),
                ),
              ),
              const CathodeScreenOverlay(),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Select system'));
    expect(tapped, isTrue);
  });
}
