import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/models/config_model.dart';

void main() {
  test('app update checks default off, system updates unchanged', () {
    expect(ConfigModel().autoUpdateApp, isFalse);
    expect(ConfigModel.fromJson({}).autoUpdateApp, isFalse);
    expect(ConfigModel().autoUpdateSystems, isTrue);
  });

  for (final key in ['autoUpdateApp', 'auto_update_app']) {
    for (final value in [true, 1, '1', 'true', false, 0, '0', 'false']) {
      test('preserves stored $key=$value', () {
        final expected = [true, 1, '1', 'true'].contains(value);
        final config = ConfigModel.fromJson({key: value});
        expect(config.autoUpdateApp, expected);
        expect(ConfigModel.fromJson(config.toJson()).autoUpdateApp, expected);
      });
    }
  }
}
