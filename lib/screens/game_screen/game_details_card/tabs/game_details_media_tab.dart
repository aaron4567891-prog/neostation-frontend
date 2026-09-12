import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../models/game_model.dart';
import '../../../../models/system_model.dart';
import '../../../../providers/file_provider.dart';

/// Displays ScreenScraper's physical-media artwork (disc, cartridge, UMD, etc.).
class GameDetailsMediaTab extends StatelessWidget {
  const GameDetailsMediaTab({
    super.key,
    required this.system,
    required this.game,
    required this.fileProvider,
    this.imageVersion = 0,
    this.bottomOffset = 110.0,
  });

  final SystemModel system;
  final GameModel game;
  final FileProvider fileProvider;
  final int imageVersion;
  final double bottomOffset;

  @override
  Widget build(BuildContext context) {
    final mediaPath = game.getImagePath(
      system.primaryFolderName,
      'media',
      fileProvider,
    );
    final mediaExists = File(mediaPath).existsSync();

    return Positioned(
      left: 12.r,
      right: 12.r,
      top: 55.r,
      bottom: bottomOffset.r,
      child: Center(
        child: mediaExists
            ? Image.file(
                File(mediaPath),
                key: ValueKey(
                  'media_${game.romPath ?? game.romname}_v$imageVersion',
                ),
                fit: BoxFit.contain,
                cacheWidth: 640,
                errorBuilder: (_, _, _) => _placeholder(context),
              )
            : _placeholder(context),
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.album_outlined,
          size: 54.r,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2),
        ),
        SizedBox(height: 8.r),
        Text(
          'No game media artwork',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.45),
          ),
        ),
      ],
    );
  }
}
