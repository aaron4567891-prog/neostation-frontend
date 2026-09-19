import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/models/rom_fingerprint.dart';
import 'package:neostation/services/neoassets_scraper_service.dart';

void main() {
  test('renamed ROM sends identity hashes with the name fallback', () {
    final query = NeoAssetsScraperService.lookupQuery(
      systemId: 'gba',
      romName: 'Pokemon - Firered.gba',
      fingerprint: const RomFingerprint(
        crc32: '1234ABCD',
        md5: '0123456789abcdef0123456789abcdef',
        sizeBytes: 16,
      ),
    );
    expect(query, {
      'system_id': 'gba',
      'name': 'Pokemon - Firered.gba',
      'crc': '1234ABCD',
      'md5': '0123456789abcdef0123456789abcdef',
    });
  });

  test('unavailable fingerprint retains the user name override', () {
    expect(
      NeoAssetsScraperService.lookupQuery(
        systemId: 'gba',
        romName: 'game.gba',
        gameName: ' Pokémon - FireRed Version ',
      ),
      {'system_id': 'gba', 'name': 'Pokémon - FireRed Version'},
    );
  });

  test('documented NeoAssets description is saved under the ROM filename', () {
    final metadata =
        NeoAssetsScraperService.metadataFor('Pokemon - Firered.gba', {
          'name': 'Pokémon - FireRed Version',
          'description_en': 'Explore Kanto.',
          'rating': 8,
        });
    expect(metadata['filename'], 'Pokemon - Firered.gba');
    expect(metadata['real_name'], 'Pokémon - FireRed Version');
    expect(metadata['description_en'], 'Explore Kanto.');
    expect(metadata['rating'], 8.0);
  });

  test('documented media kind and MIME survive extensionless CDN URLs', () {
    final media = NeoAssetsScraperService.normaliseMedia({
      'media': [
        {
          'kind': 'cover',
          'url': 'https://cdn.neoassets.dev/assets/123',
          'mime': 'image/webp',
          'size': 12345,
        },
        {
          'kind': 'logo',
          'url': 'https://cdn.neoassets.dev/assets/456',
          'mime': 'image/png',
        },
      ],
    });
    expect(media[0]['type'], 'box-2D');
    expect(media[0]['format'], 'image/webp');
    expect(media[1]['type'], 'wheel');
    expect(media[1]['format'], 'image/png');
  });

  test('legacy description and URL formats remain supported', () {
    expect(
      NeoAssetsScraperService.metadataFor('game.gba', {
        'description': 'Legacy description',
      })['description_en'],
      'Legacy description',
    );
    expect(
      NeoAssetsScraperService.normaliseMedia({
        'cover': 'https://cdn.neoassets.dev/cover.jpg',
      }).single['format'],
      'jpg',
    );
    expect(NeoAssetsScraperService.normaliseMedia({}), isEmpty);
  });
}
