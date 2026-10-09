import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:neostation/data/datasources/sqlite_migrations.dart';

void main() {
  late Database db;

  setUp(() {
    db = sqlite3.openInMemory();
    db.execute('CREATE TABLE user_config (id INTEGER PRIMARY KEY)');
    db.execute('INSERT INTO user_config (id) VALUES (1)');
    db.execute('''
      CREATE TABLE user_roms (
        filename TEXT, rom_path TEXT PRIMARY KEY, play_time INTEGER
      )
    ''');
    db.execute(
      "INSERT INTO user_roms VALUES ('Game.nes', '/roms/Game.nes', 123)",
    );
  });

  tearDown(() => db.close());

  Future<void> upgradeFrom(int oldVersion) async {
    db.execute('PRAGMA user_version = $oldVersion');
    for (var version = oldVersion + 1; version <= 170; version++) {
      await SqliteMigrations.migrateToVersion(db, version);
    }
    db.execute('PRAGMA user_version = 170');
  }

  void expectCompleteSchema() {
    final config = db.select('SELECT * FROM user_config').single;
    expect(
      config.keys,
      containsAll([
        'secondary_media_mode',
        'game_list_highlight_background',
        'hide_system_logos',
        'hide_search_card',
        'game_list_size',
        'android_apps_as_tab',
        'ignore_articles_in_game_sort',
      ]),
    );
    expect(
      db.select('SELECT filename, play_time FROM user_roms').single.values,
      ['Game.nes', 123],
    );
    expect(
      db.select('PRAGMA table_info(user_roms)').map((row) => row['name']),
      contains('ss_manual_game_id'),
    );
    expect(
      db
          .select('PRAGMA table_info(app_romm_rom_map)')
          .map((row) => row['name']),
      contains('link_source'),
    );
  }

  test(
    'personal v165 keeps preferences while gaining upstream columns',
    () async {
      await SqliteMigrations.migrateToVersion(db, 163);
      await SqliteMigrations.migrateToVersion(db, 165);
      db.execute(
        "UPDATE user_config SET game_list_size = 'XL', "
        "game_list_highlight_background = 'none', android_apps_as_tab = 1, "
        "secondary_media_mode = 'box2d'",
      );

      await upgradeFrom(165);

      expectCompleteSchema();
      final config = db.select('SELECT * FROM user_config').single;
      expect(config['game_list_size'], 'XL');
      expect(config['game_list_highlight_background'], 'none');
      expect(config['android_apps_as_tab'], 1);
      expect(config['secondary_media_mode'], 'box2d');
      expect(config['ignore_articles_in_game_sort'], 0);
    },
  );

  test(
    'main v166 gains personal columns without losing manual matches',
    () async {
      // Main's old slots 163/164/165 contain these upstream migrations.
      await SqliteMigrations.migrateToVersion(db, 167);
      await SqliteMigrations.migrateToVersion(db, 168);
      await SqliteMigrations.migrateToVersion(db, 169);
      db.execute('UPDATE user_config SET ignore_articles_in_game_sort = 1');
      db.execute('UPDATE user_roms SET ss_manual_game_id = 42');
      db.execute(
        "INSERT INTO app_romm_rom_map "
        "(romname, system_folder, romm_rom_id, link_source) "
        "VALUES ('Game.nes', 'nes', 77, 'manual')",
      );

      await upgradeFrom(166);

      expectCompleteSchema();
      expect(
        db
            .select('SELECT ss_manual_game_id FROM user_roms')
            .single['ss_manual_game_id'],
        42,
      );
      expect(
        db
            .select('SELECT romm_rom_id, link_source FROM app_romm_rom_map')
            .single
            .values,
        [77, 'manual'],
      );
      expect(
        db
            .select('SELECT ignore_articles_in_game_sort FROM user_config')
            .single['ignore_articles_in_game_sort'],
        1,
      );

      db.execute(
        "UPDATE user_config SET game_list_size = 'L', secondary_media_mode = 'video'",
      );
      await SqliteMigrations.migrateToVersion(db, 170);
      final config = db.select('SELECT * FROM user_config').single;
      expect(config['game_list_size'], 'L');
      expect(config['secondary_media_mode'], 'video');
      expect(
        db
            .select('SELECT ss_manual_game_id FROM user_roms')
            .single['ss_manual_game_id'],
        42,
      );
    },
  );
}
