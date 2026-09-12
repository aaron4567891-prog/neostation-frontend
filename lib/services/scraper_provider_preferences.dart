import 'credential_store.dart';

enum MetadataScraperProvider { screenScraper, theGamesDb }

enum ArtworkScraperPriority {
  primaryScraperFirst,
  steamGridDbFirst,
  fillMissingOnly,
}

/// Persists scraper routing choices without adding another database migration.
class ScraperProviderPreferences {
  ScraperProviderPreferences._();

  static const _metadataKey = 'preferred_metadata_scraper';
  static const _artworkKey = 'artwork_scraper_priority';

  static Future<MetadataScraperProvider> getMetadataProvider() async {
    final value = await CredentialStore.read(_metadataKey);
    return value == MetadataScraperProvider.theGamesDb.name
        ? MetadataScraperProvider.theGamesDb
        : MetadataScraperProvider.screenScraper;
  }

  static Future<void> setMetadataProvider(
    MetadataScraperProvider provider,
  ) async {
    await CredentialStore.write(_metadataKey, provider.name);
  }

  static Future<ArtworkScraperPriority> getArtworkPriority() async {
    final value = await CredentialStore.read(_artworkKey);
    return ArtworkScraperPriority.values.firstWhere(
      (priority) => priority.name == value,
      orElse: () => ArtworkScraperPriority.primaryScraperFirst,
    );
  }

  static Future<void> setArtworkPriority(
    ArtworkScraperPriority priority,
  ) async {
    await CredentialStore.write(_artworkKey, priority.name);
  }
}
