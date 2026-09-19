import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import '../models/rom_fingerprint.dart';
import '../providers/scraping_provider.dart';
import '../repositories/scraper_repository.dart';
import 'config_service.dart';
import 'credential_store.dart';
import 'logger_service.dart';
import 'retroachievements_hash_service.dart';
import 'rom_fingerprint_service.dart';
import 'screenscraper/rom_hasher.dart';

/// Authentication and account client for the NeoAssets scraping API.
///
/// Developer credentials are mandatory for every `/api/v1/scrape/*` request.
/// A personal API key is optional and raises the end-user quota. All three
/// values are kept in NeoStation's credential store and are never written to
/// the normal configuration database.
class NeoAssetsConnectionResult {
  const NeoAssetsConnectionResult({
    required this.success,
    required this.message,
    this.account,
  });

  final bool success;
  final String message;
  final Map<String, dynamic>? account;
}

class NeoAssetsScraperService {
  NeoAssetsScraperService._();

  @visibleForTesting
  static const apiBaseUrl = 'https://api.neoassets.dev';
  static const _clientIdKey = 'neoassets_client_id';
  static const _clientSecretKey = 'neoassets_client_secret';
  static const _apiKeyKey = 'neoassets_personal_api_key';
  static final _log = LoggerService.instance;

  static Future<bool> hasCredentials() async {
    final credentials = await getCredentials();
    return credentials != null;
  }

  static Future<Map<String, String>?> getCredentials() async {
    final clientId = await CredentialStore.read(_clientIdKey);
    final clientSecret = await CredentialStore.read(_clientSecretKey);
    if (clientId == null ||
        clientId.trim().isEmpty ||
        clientSecret == null ||
        clientSecret.trim().isEmpty) {
      return null;
    }
    final apiKey = await CredentialStore.read(_apiKeyKey);
    return {
      'clientId': clientId.trim(),
      'clientSecret': clientSecret.trim(),
      if (apiKey != null && apiKey.trim().isNotEmpty) 'apiKey': apiKey.trim(),
    };
  }

  static Map<String, String> _headers({
    required String clientId,
    required String clientSecret,
    String? apiKey,
  }) => {
    'Accept': 'application/json',
    'X-Client-Id': clientId,
    'X-Client-Secret': clientSecret,
    'X-Software-Name': 'NeoStation',
    if (apiKey != null && apiKey.trim().isNotEmpty)
      'Authorization': 'Bearer ${apiKey.trim()}',
  };

  /// Verifies credentials using the free account/quota endpoint and returns a
  /// user-visible reason when the connection fails.
  static Future<NeoAssetsConnectionResult> testCredentials({
    required String clientId,
    required String clientSecret,
    String? apiKey,
  }) async {
    final id = clientId.trim();
    final secret = clientSecret.trim();
    if (id.isEmpty) {
      return const NeoAssetsConnectionResult(
        success: false,
        message: 'Client ID is required.',
      );
    }
    if (secret.isEmpty) {
      return const NeoAssetsConnectionResult(
        success: false,
        message: 'Client Secret is required.',
      );
    }

    try {
      final response = await http
          .get(
            Uri.parse('$apiBaseUrl/api/v1/scrape/account'),
            headers: _headers(
              clientId: id,
              clientSecret: secret,
              apiKey: apiKey,
            ),
          )
          .timeout(const Duration(seconds: 20));

      Map<String, dynamic>? decoded;
      try {
        final body = jsonDecode(response.body);
        if (body is Map<String, dynamic>) decoded = body;
      } catch (_) {
        // Some proxy/server errors are plain text or HTML. The status code is
        // still useful and is reported below.
      }

      if (response.statusCode == 200 && decoded != null) {
        return NeoAssetsConnectionResult(
          success: true,
          message: 'NeoAssets connected successfully.',
          account: decoded,
        );
      }

      if (response.statusCode == 200) {
        const message = 'NeoAssets returned an invalid JSON response.';
        _log.w('NeoAssets credential verification: $message');
        return const NeoAssetsConnectionResult(
          success: false,
          message: message,
        );
      }

      final apiMessage =
          decoded?['error']?.toString() ??
          decoded?['message']?.toString() ??
          decoded?['detail']?.toString();
      final message = switch (response.statusCode) {
        401 => 'NeoAssets rejected the Client ID or Client Secret.',
        403 => 'NeoAssets refused access for this developer application.',
        429 => 'NeoAssets rate limit reached. Try again shortly.',
        _ =>
          apiMessage != null && apiMessage.trim().isNotEmpty
              ? 'NeoAssets error ${response.statusCode}: ${apiMessage.trim()}'
              : 'NeoAssets returned HTTP ${response.statusCode}.',
      };
      _log.w('NeoAssets credential verification: $message');
      return NeoAssetsConnectionResult(success: false, message: message);
    } on TimeoutException {
      const message = 'NeoAssets connection timed out after 20 seconds.';
      _log.w(message);
      return const NeoAssetsConnectionResult(success: false, message: message);
    } catch (e) {
      _log.e('NeoAssets credential verification failed: $e');
      return NeoAssetsConnectionResult(
        success: false,
        message: 'Could not reach NeoAssets: $e',
      );
    }
  }

  static Future<Map<String, dynamic>?> verifyCredentials({
    required String clientId,
    required String clientSecret,
    String? apiKey,
  }) async {
    final result = await testCredentials(
      clientId: clientId,
      clientSecret: clientSecret,
      apiKey: apiKey,
    );
    return result.success ? result.account ?? <String, dynamic>{} : null;
  }

  static Future<bool> saveCredentials({
    required String clientId,
    required String clientSecret,
    String? apiKey,
  }) async {
    final account = await verifyCredentials(
      clientId: clientId,
      clientSecret: clientSecret,
      apiKey: apiKey,
    );
    if (account == null) return false;
    await CredentialStore.write(_clientIdKey, clientId.trim());
    await CredentialStore.write(_clientSecretKey, clientSecret.trim());
    final personalKey = apiKey?.trim() ?? '';
    if (personalKey.isEmpty) {
      await CredentialStore.delete(_apiKeyKey);
    } else {
      await CredentialStore.write(_apiKeyKey, personalKey);
    }
    return true;
  }

  static Future<http.Response?> _authenticatedGet(
    String route, {
    Map<String, String>? query,
  }) async {
    final credentials = await getCredentials();
    if (credentials == null) return null;
    final uri = Uri.parse('$apiBaseUrl$route').replace(queryParameters: query);
    return http
        .get(
          uri,
          headers: _headers(
            clientId: credentials['clientId']!,
            clientSecret: credentials['clientSecret']!,
            apiKey: credentials['apiKey'],
          ),
        )
        .timeout(const Duration(seconds: 30));
  }

  static String _normaliseSystem(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

  static Future<String?> _resolveSystemId({
    required String appSystemId,
    required String systemFolder,
  }) async {
    try {
      final response = await _authenticatedGet('/api/v1/scrape/systems');
      if (response == null || response.statusCode != 200) return appSystemId;
      final decoded = jsonDecode(response.body);
      final raw = decoded is List
          ? decoded
          : decoded is Map<String, dynamic>
          ? (decoded['systems'] as List? ?? const [])
          : const [];
      final targets = {
        _normaliseSystem(appSystemId),
        _normaliseSystem(systemFolder),
      };
      for (final item in raw) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final id = (map['id'] ?? map['system_id'] ?? map['slug'])?.toString();
        if (id == null || id.isEmpty) continue;
        final candidates = [
          id,
          map['slug'],
          map['external_id'],
          map['name'],
          map['short_name'],
          map['folder'],
        ].whereType<Object>().map((v) => _normaliseSystem(v.toString()));
        if (candidates.any(targets.contains)) return id;
      }
    } catch (e) {
      _log.w('NeoAssets system mapping failed for $appSystemId: $e');
    }
    // NeoAssets uses stable system identifiers and NeoStation system IDs are
    // normally the same short platform slugs, so this is a useful fallback.
    return appSystemId;
  }

  static String? _firstString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value == null) continue;
      if (value is String && value.trim().isNotEmpty) return value.trim();
      if (value is num) return value.toString();
      if (value is Map) {
        final nested = value['text'] ?? value['name'] ?? value['value'];
        if (nested != null && nested.toString().trim().isNotEmpty) {
          return nested.toString().trim();
        }
      }
    }
    return null;
  }

  @visibleForTesting
  static List<Map<String, dynamic>> normaliseMedia(Map<String, dynamic> game) {
    final output = <Map<String, dynamic>>[];
    void add(String type, Object? value) {
      if (value == null) return;
      if (value is String && value.startsWith('http')) {
        final uri = Uri.tryParse(value);
        var ext = path.extension(uri?.path ?? '').replaceFirst('.', '');
        if (ext.isEmpty) ext = type == 'video' ? 'mp4' : 'png';
        output.add({
          'type': type,
          'url': value,
          'format': ext,
          'region': 'wor',
        });
      } else if (value is Map) {
        final map = Map<String, dynamic>.from(value);
        final url = _firstString(map, [
          'url',
          'public_url',
          'src',
          'download_url',
          'downloadUrl',
          'image_url',
          'imageUrl',
          'uri',
        ]);
        if (url != null) {
          final format = _firstString(map, [
            'format',
            'extension',
            'file_extension',
            'mime_type',
            'mime',
            'content_type',
          ]);
          if (format == null) {
            add(type, url);
          } else {
            output.add({
              'type': type,
              'url': url,
              'format': format,
              'region': _firstString(map, ['region', 'locale']) ?? 'wor',
            });
          }
        }
      } else if (value is List) {
        for (final entry in value) {
          if (entry is Map) {
            final map = Map<String, dynamic>.from(entry);
            final sourceType = _firstString(map, [
              'type',
              'kind',
              'media_type',
            ]);
            add(_neoMediaType(sourceType ?? type), map);
          } else {
            add(type, entry);
          }
        }
      }
    }

    final media =
        game['media'] ??
        game['medias'] ??
        game['assets'] ??
        game['images'] ??
        game['artwork'];
    if (media is Map) {
      final map = Map<String, dynamic>.from(media);
      for (final entry in map.entries) {
        add(_neoMediaType(entry.key), entry.value);
      }
    } else if (media is List) {
      add('ss', media);
    }
    // Also accept APIs that expose common media fields directly on the game.
    for (final entry in <String, String>{
      'boxart': 'box-2D',
      'box_art': 'box-2D',
      'cover': 'box-2D',
      'logo': 'wheel',
      'wheel': 'wheel',
      'fanart': 'fanart',
      'background': 'fanart',
      'screenshot': 'ss',
      'screenshots': 'ss',
      'physical_media': 'support-2D',
      'disc': 'support-2D',
      'cartridge': 'support-2D',
      'video': 'video',
    }.entries) {
      add(entry.value, game[entry.key]);
    }
    return output;
  }

  static String _neoMediaType(String raw) {
    final key = raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (key.contains('box') || key.contains('cover')) return 'box-2D';
    if (key.contains('logo') ||
        key.contains('wheel') ||
        key.contains('marquee')) {
      return 'wheel';
    }
    if (key.contains('fanart') || key.contains('background') || key == 'hero') {
      return 'fanart';
    }
    if (key.contains('support') ||
        key.contains('disc') ||
        key.contains('media') ||
        key.contains('cartridge') ||
        key.contains('cart')) {
      return 'support-2D';
    }
    if (key.contains('video') || key.contains('trailer')) return 'video';
    return 'ss';
  }

  @visibleForTesting
  static Map<String, dynamic> metadataFor(
    String romName,
    Map<String, dynamic> game,
  ) {
    double? rating;
    final ratingText = _firstString(game, ['rating', 'score']);
    if (ratingText != null) rating = double.tryParse(ratingText);
    return {
      'filename': romName,
      'real_name': _firstString(game, ['name', 'title', 'game_name']),
      'description_en': _firstString(game, [
        'description_en',
        'description',
        'overview',
        'synopsis',
      ]),
      'rating': rating,
      'release_date': _firstString(game, ['release_date', 'released', 'date']),
      'developer': _firstString(game, ['developer', 'developers']),
      'publisher': _firstString(game, ['publisher', 'publishers']),
      'genre': _firstString(game, ['genre', 'genres']),
      'players': _firstString(game, ['players', 'player_count']),
    }..removeWhere((key, value) => value == null);
  }

  static Future<bool> _downloadMedia(
    String appSystemId,
    String systemFolder,
    String romName,
    List<Map<String, dynamic>> medias, {
    bool forceOverwrite = false,
  }) async {
    final mediaPath = await ConfigService.getMediaPath();
    final cleanName = await ScreenscraperRomHasher.getCleanRomName(
      romName,
      appSystemId,
    );
    const folders = {
      'box-2D': 'box2d',
      'wheel': 'wheels',
      'fanart': 'fanarts',
      'ss': 'screenshots',
      'support-2D': 'media',
      'video': 'videos',
    };
    var anyFailure = false;
    final seen = <String>{};
    for (final media in medias) {
      final type = media['type']?.toString() ?? 'ss';
      final folder = folders[type];
      final url = media['url']?.toString();
      if (folder == null ||
          url == null ||
          !url.startsWith('http') ||
          !seen.add(type)) {
        continue;
      }
      final uri = Uri.tryParse(url);
      var ext = media['format']?.toString() ?? '';
      if (ext.isEmpty) {
        ext = path.extension(uri?.path ?? '').replaceFirst('.', '');
      }
      ext = ext.toLowerCase().trim();
      if (ext.contains('/')) ext = ext.split('/').last;
      if (ext == 'jpeg') ext = 'jpg';
      if (ext.isEmpty ||
          ext.length > 5 ||
          !RegExp(r'^[a-z0-9]+$').hasMatch(ext)) {
        ext = type == 'video' ? 'mp4' : 'png';
      }
      final file = File(
        path.join(mediaPath, systemFolder, folder, '$cleanName.$ext'),
      );
      if (await file.exists() && !forceOverwrite) continue;
      try {
        final response = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 60));
        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          await file.create(recursive: true);
          await file.writeAsBytes(response.bodyBytes);
        } else {
          anyFailure = true;
        }
      } catch (e) {
        anyFailure = true;
        _log.w('NeoAssets media download failed: $e');
      }
    }
    return seen.isNotEmpty && !anyFailure;
  }

  /// Hash identity takes priority on the API; name remains its fallback.
  @visibleForTesting
  static Map<String, String> lookupQuery({
    required String systemId,
    required String romName,
    String? gameName,
    RomFingerprint? fingerprint,
  }) => {
    'system_id': systemId,
    'name': gameName?.trim().isNotEmpty == true ? gameName!.trim() : romName,
    if (fingerprint != null) 'crc': fingerprint.crc32,
    if (fingerprint?.md5 != null) 'md5': fingerprint!.md5!,
  };

  /// Resolves and stores one game using NeoAssets metadata and media URLs.
  static Future<Map<String, dynamic>> scrapeSingleGame({
    required String appSystemId,
    required String romName,
    required String systemFolder,
    required String romPath,
    String? gameName,
    Function(String status, double progress)? onProgress,
    bool forceOverwrite = false,
  }) async {
    try {
      if (!await hasCredentials()) {
        return {'success': false, 'message': 'Connect NeoAssets first.'};
      }
      onProgress?.call('Fetching NeoAssets metadata', 0.1);
      final systemId = await _resolveSystemId(
        appSystemId: appSystemId,
        systemFolder: systemFolder,
      );
      if (systemId == null) {
        return {'success': false, 'message': 'NeoAssets system not mapped.'};
      }
      RomFingerprint? fingerprint;
      // NeoAssets gives hashes priority and falls back to the supplied name.
      // The shared SAF-aware fingerprinter identifies the ROM inside archives,
      // except for systems such as arcade where the packed set is the ROM.
      try {
        final policy = await RetroAchievementsHashService.policyForSystem(
          systemFolder,
        );
        final attempt = await RomFingerprintService.computeInBackground(
          romPath,
          systemFolder,
          keepsArchivesPacked: policy.keepsArchivesPacked,
        );
        fingerprint = attempt.fingerprint;
      } catch (e) {
        // Unreadable, unsupported or unavailable ROMs can still match by name.
        _log.w('NeoAssets fingerprint unavailable; using name lookup: $e');
      }
      final response = await _authenticatedGet(
        '/api/v1/scrape/games',
        query: lookupQuery(
          systemId: systemId,
          romName: romName,
          gameName: gameName,
          fingerprint: fingerprint,
        ),
      );
      if (response == null) {
        return {
          'success': false,
          'message': 'NeoAssets credentials are missing.',
        };
      }
      if (response.statusCode == 429) {
        return {
          'success': false,
          'message': 'NeoAssets quota/rate limit reached.',
        };
      }
      if (response.statusCode != 200) {
        return {
          'success': false,
          'message': 'NeoAssets returned HTTP ${response.statusCode}.',
        };
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return {
          'success': false,
          'message': 'NeoAssets returned an invalid response.',
        };
      }
      final root = Map<String, dynamic>.from(decoded);
      final rawGame = root['game'] ?? root['data'] ?? root['result'];
      if (rawGame is! Map) {
        return {'success': false, 'message': 'Game not found on NeoAssets.'};
      }
      final game = Map<String, dynamic>.from(rawGame);
      await ScraperRepository.saveGameMetadata(
        metadataFor(romName, game),
        appSystemId,
        isFullyScraped: false,
      );
      onProgress?.call('Downloading NeoAssets media', 0.35);
      final ok = await _downloadMedia(
        appSystemId,
        systemFolder,
        romName,
        normaliseMedia(game),
        forceOverwrite: forceOverwrite,
      );
      if (ok) await ScraperRepository.markGameFullyScraped(romName);
      onProgress?.call('NeoAssets scrape complete', 1.0);
      return {
        'success': true,
        'message': ok
            ? 'NeoAssets scrape successful.'
            : 'Metadata saved; some NeoAssets media failed.',
        'matchedBy': root['matched_by']?.toString(),
      };
    } on TimeoutException {
      return {'success': false, 'message': 'NeoAssets request timed out.'};
    } catch (e) {
      _log.e('NeoAssets game scrape failed: $e');
      return {'success': false, 'message': 'NeoAssets scrape failed: $e'};
    }
  }

  /// Bulk-scrapes the same ROM set used by NeoStation's existing scraper UI.
  static Future<bool> startMetadataScraping(
    BuildContext context,
    ScrapingProvider scrapingProvider, {
    bool Function()? shouldCancel,
  }) async {
    if (!await hasCredentials()) return false;
    final systems = await ScraperRepository.getDetectedScraperSystems();
    final config = await ScraperRepository.getScraperConfig();
    final mode = config['scrape_mode']?.toString() ?? 'new_only';
    final jobs = <Map<String, dynamic>>[];
    for (final system in systems) {
      final appSystemId = system['id'].toString();
      final roms = await ScraperRepository.getRomsForScraping(
        appSystemId,
        mode,
      );
      for (final rom in roms) {
        jobs.add({...rom, ...system});
      }
    }
    scrapingProvider.startScraping(maxThreads: 2);
    scrapingProvider.updateProgress(totalGames: jobs.length);
    var success = 0;
    var failed = 0;
    for (var i = 0; i < jobs.length; i++) {
      if (shouldCancel?.call() == true) {
        scrapingProvider.stopScraping();
        return false;
      }
      final job = jobs[i];
      final threadId = (i % 2) + 1;
      scrapingProvider.updateThreadProgress(
        threadId: threadId,
        gameName: job['filename']?.toString(),
        systemName: job['name']?.toString(),
        isActive: true,
        status: ThreadStatus.active,
        currentStep: ThreadProcessingStep.fetchingMetadata,
        progress: 0,
      );
      final result = await scrapeSingleGame(
        appSystemId: job['id'].toString(),
        romName: job['filename'].toString(),
        systemFolder: job['folder_name'].toString(),
        romPath: job['rom_path'].toString(),
        gameName: job['title_name']?.toString(),
        forceOverwrite: mode == 'all',
      );
      if (result['success'] == true) {
        success++;
      } else {
        failed++;
      }
      scrapingProvider.markThreadCompleted(threadId);
      scrapingProvider.updateProgress(
        totalGames: jobs.length,
        processedGames: i + 1,
        successfulGames: success,
        failedGames: failed,
      );
    }
    scrapingProvider.stopScraping();
    return true;
  }

  static Future<void> clearCredentials() async {
    await CredentialStore.delete(_clientIdKey);
    await CredentialStore.delete(_clientSecretKey);
    await CredentialStore.delete(_apiKeyKey);
  }

  static Future<Map<String, dynamic>?> getAccount() async {
    final credentials = await getCredentials();
    if (credentials == null) return null;
    return verifyCredentials(
      clientId: credentials['clientId']!,
      clientSecret: credentials['clientSecret']!,
      apiKey: credentials['apiKey'],
    );
  }
}
