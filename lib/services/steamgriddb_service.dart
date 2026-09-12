import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import '../repositories/scraper_repository.dart';
import 'credential_store.dart';
import 'logger_service.dart';
import 'screenscraper/media_resolver.dart';
import 'screenscraper/rom_hasher.dart';

/// Optional artwork supplement backed by SteamGridDB.
class SteamGridDbService {
  SteamGridDbService._();

  static const _baseUrl = 'https://www.steamgriddb.com/api/v2';
  static const _apiKeyStoreKey = 'steamgriddb_api_key';
  static final _log = LoggerService.instance;

  static Future<String?> getApiKey() => CredentialStore.read(_apiKeyStoreKey);

  static Future<bool> hasApiKey() async {
    final key = await getApiKey();
    return key != null && key.trim().isNotEmpty;
  }

  static Future<Map<String, dynamic>?> _get(
    String endpoint, {
    Map<String, String>? query,
    String? apiKey,
  }) async {
    final key = apiKey ?? await getApiKey();
    if (key == null || key.trim().isEmpty) return null;
    try {
      final response = await http
          .get(
            Uri.parse('$_baseUrl$endpoint').replace(queryParameters: query),
            headers: {
              'Authorization': 'Bearer ${key.trim()}',
              'Accept': 'application/json',
              'User-Agent': 'NeoStation/1.0',
            },
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        _log.w('SteamGridDB $endpoint returned ${response.statusCode}');
        return null;
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      _log.w('SteamGridDB request failed: $e');
      return null;
    }
  }

  static Future<bool> verifyApiKey(String key) async {
    final result = await _get('/search/autocomplete/portal', apiKey: key);
    return result?['success'] == true;
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
    name = name.replaceAll('_', ' ');
    return name.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _normalise(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  static Map<String, dynamic>? _firstResult(Map<String, dynamic>? response) {
    final data = response?['data'];
    if (data is! List || data.isEmpty) return null;
    final results = data.whereType<Map<String, dynamic>>();
    return results.isEmpty ? null : results.first;
  }

  static Map<String, dynamic>? _chooseGame(
    Map<String, dynamic>? response,
    String wanted,
  ) {
    final data = response?['data'];
    if (data is! List) return null;
    final games = data.whereType<Map<String, dynamic>>().toList();
    if (games.isEmpty) return null;
    final exact = games.where(
      (game) =>
          _normalise(game['name']?.toString() ?? '') == _normalise(wanted),
    );
    return exact.isNotEmpty ? exact.first : games.first;
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
      _log.w('SteamGridDB artwork download failed: $e');
      return false;
    }
  }

  static Future<bool> _hasArtwork(String directory, String baseName) async {
    for (final extension in const ['png', 'jpg', 'jpeg', 'webp']) {
      if (await File(path.join(directory, '$baseName.$extension')).exists()) {
        return true;
      }
    }
    return false;
  }

  static Future<void> _removeArtworkVariants(
    String directory,
    String baseName,
  ) async {
    for (final extension in const ['png', 'jpg', 'jpeg', 'webp']) {
      final file = File(path.join(directory, '$baseName.$extension'));
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  /// Downloads available SteamGridDB art into NeoStation's normal folders.
  /// Missing files are filled by default; [forceOverwrite] replaces them.
  static Future<bool> downloadGameArtwork({
    required String appSystemId,
    required String systemFolder,
    required String romName,
    String? gameName,
    bool forceOverwrite = false,
  }) async {
    if (!await hasApiKey()) return true;
    final wanted = _searchName(romName, gameName);
    final search = await _get(
      '/search/autocomplete/${Uri.encodeComponent(wanted)}',
    );
    final game = _chooseGame(search, wanted);
    final gameId = int.tryParse(game?['id']?.toString() ?? '');
    if (gameId == null) return false;

    final enabled = await ScraperRepository.getEnabledMediaTypes();
    final endpoints = <String, String>{
      if (enabled.contains('box2D')) 'box2d': '/grids/game/$gameId',
      if (enabled.contains('fanart')) 'fanarts': '/heroes/game/$gameId',
      if (enabled.contains('wheel')) 'wheels': '/logos/game/$gameId',
    };
    final mediaRoot = await ScreenscraperMediaResolver.getMediaDirectory();
    final cleanName = await ScreenscraperRomHasher.getCleanRomName(
      romName,
      appSystemId,
    );
    var foundAny = false;
    for (final entry in endpoints.entries) {
      final response = await _get(
        entry.value,
        query: const {'types': 'static', 'nsfw': 'false', 'humor': 'false'},
      );
      final artwork = _firstResult(response);
      final url = artwork?['url']?.toString();
      if (url == null || url.isEmpty) continue;
      foundAny = true;
      final directory = path.join(mediaRoot, systemFolder, entry.key);
      if (!forceOverwrite && await _hasArtwork(directory, cleanName)) {
        continue;
      }
      if (forceOverwrite) {
        await _removeArtworkVariants(directory, cleanName);
      }
      final extension = path.extension(Uri.parse(url).path);
      await _download(
        url,
        path.join(
          directory,
          cleanName + (extension.isEmpty ? '.png' : extension),
        ),
        overwrite: forceOverwrite,
      );
    }
    return foundAny;
  }
}
