import 'dart:convert';

import 'package:http/http.dart' as http;

import 'credential_store.dart';
import 'logger_service.dart';

/// Authentication and account client for the NeoAssets scraping API.
///
/// Developer credentials are mandatory for every `/api/v1/scrape/*` request.
/// A personal API key is optional and raises the end-user quota. All three
/// values are kept in NeoStation's credential store and are never written to
/// the normal configuration database.
class NeoAssetsScraperService {
  NeoAssetsScraperService._();

  static const _baseUrl = 'https://neoassets.dev';
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

  /// Verifies credentials using the free account/quota endpoint.
  static Future<Map<String, dynamic>?> verifyCredentials({
    required String clientId,
    required String clientSecret,
    String? apiKey,
  }) async {
    if (clientId.trim().isEmpty || clientSecret.trim().isEmpty) return null;
    try {
      final response = await http
          .get(
            Uri.parse('$_baseUrl/api/v1/scrape/account'),
            headers: _headers(
              clientId: clientId.trim(),
              clientSecret: clientSecret.trim(),
              apiKey: apiKey,
            ),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        _log.w(
          'NeoAssets credential verification returned ${response.statusCode}',
        );
        return null;
      }
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (e) {
      _log.e('NeoAssets credential verification failed: $e');
      return null;
    }
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
