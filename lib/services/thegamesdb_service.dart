import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import '../providers/scraping_provider.dart';
import '../repositories/scraper_repository.dart';
import 'credential_store.dart';
import 'logger_service.dart';
import 'screenscraper/media_resolver.dart';
import 'screenscraper/rom_hasher.dart';
import 'steamgriddb_service.dart';
import 'scraper_provider_preferences.dart';

/// Optional metadata provider backed by TheGamesDB.
///
/// The API key is kept in NeoStation's credential store. Results are written to
/// the existing metadata table and media layout, so no parallel library is
/// created and the rest of the UI remains provider-agnostic.
class TheGamesDbService {
  TheGamesDbService._();

  static const _baseUrl = 'https://api.thegamesdb.net';
  static const _apiKeyStoreKey = 'thegamesdb_api_key';
  static final _log = LoggerService.instance;

  static Future<String?> getApiKey() => CredentialStore.read(_apiKeyStoreKey);

  static Future<bool> hasApiKey() async {
    final key = await getApiKey();
    return key != null && key.trim().isNotEmpty;
  }

  static Future<bool> verifyApiKey(String key) async {
    if (key.trim().isEmpty) return false;
    try {
      final response = await http
          .get(
            Uri.parse(
              '$_baseUrl/v1/API/Limit',
            ).replace(queryParameters: {'apikey': key.trim()}),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return false;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      // The current API/Limit response contains only allowance fields, while
      // older responses also included code/status. Accept either shape.
      return body['remaining_monthly_allowance'] != null ||
          body['code'] == 200 ||
          body['status'] == 'Success';
    } catch (e) {
      _log.e('TheGamesDB API-key verification failed: $e');
      return false;
    }
  }

  static Future<bool> saveApiKey(String key) async {
    if (!await verifyApiKey(key)) return false;
    await CredentialStore.write(_apiKeyStoreKey, key.trim());
    return true;
  }

  static Future<void> clearApiKey() => CredentialStore.delete(_apiKeyStoreKey);

  static String _searchName(String romName, String? gameName) {
    if (gameName != null && gameName.trim().isNotEmpty) return gameName.trim();
    var name = path.basenameWithoutExtension(romName);
    name = name.replaceAll(RegExp(r'\s*[\[(].*?[\])]'), ' ');
    name = name.replaceAll(RegExp(r'[_]+'), ' ');
    return name.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _normalise(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  static Map<String, dynamic>? _chooseGame(
    List<dynamic> games,
    String wanted,
    int? platformId,
  ) {
    final candidates = games.whereType<Map<String, dynamic>>().toList();
    if (candidates.isEmpty) return null;
    if (platformId != null) {
      final onPlatform = candidates
          .where((g) => g['platform']?.toString() == platformId.toString())
          .toList();
      if (onPlatform.isNotEmpty) {
        candidates
          ..clear()
          ..addAll(onPlatform);
      }
    }
    final exact = candidates.where(
      (g) =>
          _normalise(g['game_title']?.toString() ?? '') == _normalise(wanted),
    );
    return exact.isNotEmpty ? exact.first : candidates.first;
  }

  static Future<Map<String, dynamic>?> _getJson(
    String endpoint,
    Map<String, String> parameters,
  ) async {
    final key = await getApiKey();
    if (key == null) return null;
    final response = await http
        .get(
          Uri.parse(
            '$_baseUrl$endpoint',
          ).replace(queryParameters: {...parameters, 'apikey': key}),
          headers: const {
            'Accept': 'application/json',
            'User-Agent': 'NeoStation/1.0',
          },
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      _log.w('TheGamesDB $endpoint returned ${response.statusCode}');
      return null;
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static String? _includedName(
    Map<String, dynamic> response,
    String group,
    dynamic ids,
  ) {
    if (ids is! List || ids.isEmpty) return null;
    final include = response['include'];
    if (include is! Map) return null;
    final values = include[group];
    if (values is! Map) return null;
    final names = <String>[];
    for (final id in ids) {
      final item = values[id.toString()] ?? values[id];
      if (item is Map && item['name'] != null) {
        names.add(item['name'].toString());
      }
    }
    return names.isEmpty ? null : names.join(', ');
  }

  static double? _rating(dynamic value) {
    final parsed = double.tryParse(value?.toString() ?? '');
    if (parsed == null) return null;
    return parsed > 1
        ? (parsed / 10).clamp(0, 1).toDouble()
        : parsed.clamp(0, 1).toDouble();
  }

  static Future<bool> _download(
    String url,
    String destination, {
    required bool overwrite,
  }) async {
    final file = File(destination);
    if (!overwrite && await file.exists()) return true;
    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 60));
      if (response.statusCode != 200) return false;
      await file.create(recursive: true);
      await file.writeAsBytes(response.bodyBytes, flush: true);
      return true;
    } catch (e) {
      _log.w('TheGamesDB media download failed: $e');
      return false;
    }
  }

  static Map<String, dynamic>? _firstImage(List<dynamic> images, String type) {
    final matches = images.whereType<Map<String, dynamic>>().where((image) {
      if (image['type']?.toString() != type) return false;
      return type != 'boxart' || image['side']?.toString() == 'front';
    });
    return matches.isEmpty ? null : matches.first;
  }

  static Future<void> _downloadMedia({
    required int gameId,
    required String appSystemId,
    required String systemFolder,
    required String romName,
    required bool overwrite,
    bool preferSteamGridDb = false,
  }) async {
    final response = await _getJson('/v1/Games/Images', {
      'games_id': gameId.toString(),
    });
    if (response == null) return;
    final data = response['data'];
    if (data is! Map) return;
    final imagesByGame = data['images'];
    if (imagesByGame is! Map) return;
    final rawImages = imagesByGame[gameId.toString()] ?? imagesByGame[gameId];
    if (rawImages is! List) return;

    final base =
        (data['base_url']?['original'] ??
                data['base_url'] ??
                'https://cdn.thegamesdb.net/images/original/')
            .toString();
    final mediaRoot = await ScreenscraperMediaResolver.getMediaDirectory();
    final cleanName = await ScreenscraperRomHasher.getCleanRomName(
      romName,
      appSystemId,
    );
    final enabled = await ScraperRepository.getEnabledMediaTypes();
    final choices = <String, Map<String, dynamic>?>{
      if (!preferSteamGridDb && enabled.contains('box2D'))
        'box2d': _firstImage(rawImages, 'boxart'),
      if (!preferSteamGridDb && enabled.contains('fanart'))
        'fanarts': _firstImage(rawImages, 'fanart'),
      if (enabled.contains('ss'))
        'screenshots': _firstImage(rawImages, 'screenshot'),
      if (!preferSteamGridDb && enabled.contains('wheel'))
        'wheels': _firstImage(rawImages, 'clearlogo'),
    };
    for (final entry in choices.entries) {
      final image = entry.value;
      if (image == null) continue;
      final remote = (image['filename'] ?? image['url'])?.toString();
      if (remote == null || remote.isEmpty) continue;
      final extension = path.extension(Uri.parse(remote).path);
      await _download(
        remote.startsWith('http')
            ? remote
            : '${base.endsWith('/') ? base : '$base/'}$remote',
        path.join(
          mediaRoot,
          systemFolder,
          entry.key,
          '$cleanName${extension.isEmpty ? '.jpg' : extension}',
        ),
        overwrite: overwrite,
      );
    }
  }

  /// Scrapes one game. TheGamesDB is name/platform based and does not require
  /// ScreenScraper developer credentials.
  static Future<Map<String, dynamic>> scrapeSingleGame({
    required String appSystemId,
    required String romName,
    required String systemFolder,
    required String romPath,
    String? gameName,
    Function(String status, double progress)? onProgress,
    bool forceOverwrite = false,
  }) async {
    if (!await hasApiKey()) {
      return {
        'success': false,
        'message': 'TheGamesDB API key is not configured.',
      };
    }
    try {
      final wanted = _searchName(romName, gameName);
      onProgress?.call('Fetching metadata', 0.1);
      final platformId =
          _platformIds[appSystemId] ?? _platformIds[systemFolder];
      final response = await _getJson('/v1.1/Games/ByGameName', {
        'name': wanted,
        'fields':
            'players,publishers,genres,overview,rating,platform,developers',
        'include': 'developers,publishers,genres',
      });
      final data = response?['data'];
      final games = data is Map ? data['games'] : null;
      final game = games is List
          ? _chooseGame(games, wanted, platformId)
          : null;
      if (game == null) {
        return {'success': false, 'message': 'Game not found on TheGamesDB.'};
      }

      final metadata = <String, dynamic>{
        'filename': romName,
        'real_name': game['game_title']?.toString() ?? wanted,
        'description_en': game['overview']?.toString(),
        'release_date': game['release_date']?.toString(),
        'players': game['players']?.toString(),
        'rating': _rating(game['rating']),
        'developer': _includedName(response!, 'developers', game['developers']),
        'publisher': _includedName(response, 'publishers', game['publishers']),
        'genre': _includedName(response, 'genres', game['genres']),
      }..removeWhere((_, value) => value == null || value == '');
      await ScraperRepository.saveGameMetadata(
        metadata,
        appSystemId,
        isFullyScraped: true,
      );

      final id = int.tryParse(game['id']?.toString() ?? '');
      final artworkPriority =
          await ScraperProviderPreferences.getArtworkPriority();
      if (artworkPriority == ArtworkScraperPriority.steamGridDbFirst) {
        await SteamGridDbService.downloadGameArtwork(
          appSystemId: appSystemId,
          systemFolder: systemFolder,
          romName: romName,
          gameName: game['game_title']?.toString() ?? gameName,
          forceOverwrite: forceOverwrite,
        );
      }
      if (id != null) {
        onProgress?.call('Downloading images', 0.35);
        await _downloadMedia(
          gameId: id,
          appSystemId: appSystemId,
          systemFolder: systemFolder,
          romName: romName,
          overwrite:
              forceOverwrite &&
              artworkPriority == ArtworkScraperPriority.primaryScraperFirst,
          preferSteamGridDb:
              artworkPriority == ArtworkScraperPriority.steamGridDbFirst,
        );
      }
      if (artworkPriority != ArtworkScraperPriority.steamGridDbFirst) {
        await SteamGridDbService.downloadGameArtwork(
          appSystemId: appSystemId,
          systemFolder: systemFolder,
          romName: romName,
          gameName: game['game_title']?.toString() ?? gameName,
          forceOverwrite: false,
        );
      }
      onProgress?.call('Completed', 1);
      return {'success': true, 'message': 'Scrape successful'};
    } catch (e) {
      _log.e('TheGamesDB scrape failed for $romName: $e');
      return {'success': false, 'message': 'TheGamesDB error: $e'};
    }
  }

  static Future<bool> startMetadataScraping(
    ScrapingProvider provider, {
    bool Function()? shouldCancel,
  }) async {
    final config = await ScraperRepository.getScraperConfig();
    final mode = config['scrape_mode']?.toString() ?? 'new_only';
    final mappings = await ScraperRepository.getSystemMappings();
    final queue = <Map<String, dynamic>>[];
    for (final mapping in mappings) {
      final systemId = mapping['app_system_id'].toString();
      final roms = await ScraperRepository.getRomsForScraping(systemId, mode);
      for (final rom in roms) {
        queue.add({
          ...rom,
          'app_system_id': systemId,
          'system_folder': mapping['primary_folder_name'].toString(),
          'system_name': mapping['real_name'].toString(),
        });
      }
    }
    provider.updateProgress(
      totalGames: queue.length,
      processedGames: 0,
      successfulGames: 0,
      failedGames: 0,
    );
    var processed = 0;
    var successful = 0;
    var failed = 0;
    for (final rom in queue) {
      if (shouldCancel?.call() == true) return false;
      provider.updateThreadProgress(
        threadId: 1,
        gameName: rom['filename'].toString(),
        systemName: rom['system_name'].toString(),
        isActive: true,
        status: ThreadStatus.active,
        currentStep: ThreadProcessingStep.fetchingMetadata,
        progress: 0,
      );
      final result = await scrapeSingleGame(
        appSystemId: rom['app_system_id'].toString(),
        romName: rom['filename'].toString(),
        systemFolder: rom['system_folder'].toString(),
        romPath: rom['rom_path'].toString(),
        gameName: rom['title_name']?.toString(),
        forceOverwrite: mode == 'all',
        onProgress: (_, progress) => provider.updateThreadProgress(
          threadId: 1,
          progress: progress,
          currentStep: progress < .35
              ? ThreadProcessingStep.fetchingMetadata
              : progress < 1
              ? ThreadProcessingStep.downloadingImages
              : ThreadProcessingStep.completed,
        ),
      );
      processed++;
      if (result['success'] == true) {
        successful++;
      } else {
        failed++;
      }
      provider.updateProgress(
        processedGames: processed,
        successfulGames: successful,
        failedGames: failed,
      );
      provider.markThreadCompleted(1);
    }
    provider.stopScraping();
    return failed == 0 || successful > 0;
  }

  /// Platform IDs from TheGamesDB's platform catalogue. Unknown systems are
  /// still searched by name; the mapping only disambiguates duplicate titles.
  static const Map<String, int> _platformIds = {
    '3do': 25,
    'amiga': 4911,
    'amigacd32': 4947,
    'amstradcpc': 4914,
    'android': 4916,
    'arcade': 23,
    'arc': 23,
    'atari2600': 22,
    'atari5200': 26,
    'atari7800': 27,
    'atarijaguar': 28,
    'atarilynx': 4924,
    'c64': 40,
    'colecovision': 31,
    'dreamcast': 16,
    'fds': 4936,
    'gamegear': 20,
    'gb': 4,
    'gba': 5,
    'gbc': 41,
    'gc': 2,
    'intellivision': 32,
    'mastersystem': 35,
    'megadrive': 18,
    'genesis': 18,
    'msx': 4929,
    'n64': 3,
    'nds': 8,
    '3ds': 4912,
    'nes': 7,
    'ngc': 2,
    'ngcd': 24,
    'ngp': 4922,
    'ngpc': 4923,
    'pc': 1,
    'pcengine': 34,
    'pcfx': 4930,
    'psx': 10,
    'ps2': 11,
    'ps3': 12,
    'ps4': 4919,
    'ps5': 4980,
    'psp': 13,
    'psvita': 39,
    'saturn': 17,
    'sega32x': 33,
    'segacd': 21,
    'snes': 6,
    'switch': 4971,
    'vectrex': 4939,
    'wii': 9,
    'wiiu': 38,
    'xbox': 14,
    'xbox360': 15,
  };
}
