import 'dart:io';
import 'package:flutter/material.dart';
import 'package:neostation/models/system_model.dart';
import 'package:provider/provider.dart';
import 'package:neostation/providers/sqlite_config_provider.dart';

/// Common branding for every game browsing layout.
class GameSystemLogo extends StatelessWidget {
  final SystemModel system;
  final double height;
  const GameSystemLogo({super.key, required this.system, this.height = 42});

  @override
  Widget build(BuildContext context) {
    final savedSystems = context.watch<SqliteConfigProvider>().availableSystems;
    final system = savedSystems.firstWhere(
      (candidate) => this.system.id != null
          ? candidate.id == this.system.id
          : candidate.folderName == this.system.folderName,
      orElse: () => this.system,
    );
    final candidates = <String>{
      if (system.id != null && system.id!.trim().isNotEmpty) system.id!.trim(),
      system.primaryFolderName,
      system.folderName,
    }.where((name) => name.isNotEmpty).toList();
    final color = Theme.of(context).colorScheme.onSurface;
    Widget fallback() => Center(
      child: Text(
        system.shortName ?? system.realName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleLarge,
      ),
    );
    Widget asset([int index = 0]) {
      if (index >= candidates.length) return fallback();
      return Image.asset(
        'assets/images/logos/${candidates[index]}.webp',
        height: height,
        fit: BoxFit.contain,
        cacheWidth: 512,
        frameBuilder: (context, child, frame, synchronous) => ColorFiltered(
          colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
          child: child,
        ),
        errorBuilder: (context, error, stack) => asset(index + 1),
      );
    }

    final custom = system.customLogoPath;
    return Semantics(
      label: system.realName,
      image: true,
      child: SizedBox(
        height: height,
        child: custom != null && custom.isNotEmpty
            ? Image.file(
                File(custom),
                height: height,
                cacheWidth: 512,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stack) => asset(),
              )
            : asset(),
      ),
    );
  }
}
