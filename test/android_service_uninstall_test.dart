import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/services/android_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.neogamelab.neostation/game');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('uninstall request forwards the selected package to Android', () async {
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          received = call;
          return true;
        });

    final opened = await AndroidService.requestPackageUninstall(
      'com.example.game',
    );

    expect(opened, isTrue);
    expect(received?.method, 'uninstallPackage');
    expect(received?.arguments, {'packageName': 'com.example.game'});
  });

  test(
    'uninstall request reports a platform refusal without throwing',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(code: 'UNINSTALL_FAILED');
          });

      expect(
        await AndroidService.requestPackageUninstall('com.example.protected'),
        isFalse,
      );
    },
  );
}
