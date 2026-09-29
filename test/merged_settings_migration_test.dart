import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:neostation/data/datasources/sqlite_migrations.dart';

void main() {
  for (final history in ['personal', 'upstream', 'both']) {
    test('v163 preserves $history settings and repairs missing columns', () async {
      final db = sqlite3.openInMemory();
      addTearDown(db.close);
      db.execute('CREATE TABLE user_config (id INTEGER PRIMARY KEY)');
      db.execute('INSERT INTO user_config (id) VALUES (1)');
      if (history != 'upstream') {
        await SqliteMigrations.migrateToVersion(db, 158);
        await SqliteMigrations.migrateToVersion(db, 159);
        db.execute(
          "UPDATE user_config SET game_list_highlight_background = 'green', secondary_media_mode = 'video'",
        );
      }
      if (history != 'personal') {
        db.execute(
          'ALTER TABLE user_config ADD COLUMN hide_system_logos INTEGER DEFAULT 0',
        );
        db.execute(
          'ALTER TABLE user_config ADD COLUMN hide_search_card INTEGER DEFAULT 1',
        );
        db.execute(
          'UPDATE user_config SET hide_system_logos = 1, hide_search_card = 0',
        );
      }
      await SqliteMigrations.migrateToVersion(db, 163);
      final row = db.select('SELECT * FROM user_config').single;
      expect(
        row['game_list_highlight_background'],
        history == 'upstream' ? 'theme' : 'green',
      );
      expect(
        row['secondary_media_mode'],
        history == 'upstream' ? 'automatic' : 'video',
      );
      expect(row['hide_system_logos'], history == 'personal' ? 0 : 1);
      expect(row['hide_search_card'], history == 'personal' ? 1 : 0);
      expect(row['neoglass_blur'], 0);
      await SqliteMigrations.migrateToVersion(db, 163);
      expect(db.select('SELECT * FROM user_config').single, row);
    });
  }
}
