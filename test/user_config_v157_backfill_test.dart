import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/data/datasources/sqlite_config_service.dart';
import 'package:neostation/data/datasources/sqlite_migrations.dart';
import 'package:neostation/data/datasources/sqlite_service.dart';
import 'package:neostation/models/config_model.dart';

import 'database_test_helper.dart';

void main() {
  final helper = DatabaseTestHelper();
  late DatabaseAdapter db;
  const config = ConfigModel(
    systemSortBy: 'custom:["gba","snes","nes"]',
    secondaryMediaMode: 'fanart',
    neoglassBlur: 1,
    neoglassTransparency: 15,
    neoglassBorderWidth: 3,
  );

  setUp(() async {
    db = await helper.setUp();
    await SqliteConfigService.saveConfig(config);
    await db.execute('PRAGMA user_version = 157');
    await db.execute(
      "INSERT INTO user_roms (rom_path, title_name, play_time) "
      "VALUES ('/roms/game.gba', 'Saved game', 1234)",
    );
  });
  tearDown(() async => helper.tearDown());

  for (final missing in [
    ['neoglass_blur', 'neoglass_transparency', 'neoglass_border_width'],
    ['secondary_media_mode'],
    ['neoglass_transparency'],
  ]) {
    test('v158 repairs a v157 database missing $missing', () async {
      for (final column in missing) {
        await db.execute('ALTER TABLE user_config DROP COLUMN $column');
      }
      // This is the whole-config write used by A to drop a system card.
      await expectLater(
        SqliteConfigService.saveConfig(config),
        throwsA(isA<Exception>()),
      );

      // Devices already at v157 skip that slot, even after its code changes.
      await SqliteMigrations.migrateToVersion(db.rawDb, 158);
      final repaired = (await SqliteService.getUserConfig())!;
      final defaults = {
        'secondary_media_mode': 'automatic',
        'neoglass_blur': 0,
        'neoglass_transparency': 10,
        'neoglass_border_width': 2.0,
      };
      final existing = {
        'secondary_media_mode': 'fanart',
        'neoglass_blur': 1,
        'neoglass_transparency': 15,
        'neoglass_border_width': 3.0,
      };
      for (final column in defaults.keys) {
        expect(
          repaired[column],
          missing.contains(column) ? defaults[column] : existing[column],
        );
      }

      const order = 'custom:["nes","gba","snes"]';
      await SqliteConfigService.saveConfig(
        config.copyWith(systemSortBy: order),
      );
      expect((await SqliteService.getUserConfig())!['system_sort_by'], order);
      final games = await db.rawQuery('SELECT * FROM user_roms');
      expect(games.single['title_name'], 'Saved game');
      expect(games.single['play_time'], 1234);
    });
  }

  test('v158 preserves existing settings and can run twice', () async {
    final before = await SqliteService.getUserConfig();
    await SqliteMigrations.migrateToVersion(db.rawDb, 158);
    await SqliteMigrations.migrateToVersion(db.rawDb, 158);
    expect(await SqliteService.getUserConfig(), before);
  });
}
