import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/data/datasources/sqlite_migrations.dart';
import 'package:neostation/data/datasources/sqlite_service.dart';

import 'database_test_helper.dart';

void main() {
  final helper = DatabaseTestHelper();
  late DatabaseAdapter db;

  setUp(() async {
    db = await helper.setUp();
    await SqliteService.saveUserConfig(gameListHighlightBackground: 'purple');
  });

  tearDown(() async => helper.tearDown());

  test(
    'v159 adds the highlight column and preserves the setting after migration',
    () async {
      await db.execute(
        'ALTER TABLE user_config DROP COLUMN game_list_highlight_background',
      );

      await expectLater(
        SqliteService.saveUserConfig(gameListHighlightBackground: 'green'),
        throwsA(isA<Exception>()),
      );

      await SqliteMigrations.migrateToVersion(db.rawDb, 159);
      final migrated = await SqliteService.getUserConfig();
      expect(migrated?['game_list_highlight_background'], 'theme');

      await SqliteService.saveUserConfig(gameListHighlightBackground: 'green');
      expect(
        (await SqliteService.getUserConfig())?['game_list_highlight_background'],
        'green',
      );

      // A repeated migration is a no-op and does not reset the preference.
      await SqliteMigrations.migrateToVersion(db.rawDb, 159);
      expect(
        (await SqliteService.getUserConfig())?['game_list_highlight_background'],
        'green',
      );
    },
  );
}
