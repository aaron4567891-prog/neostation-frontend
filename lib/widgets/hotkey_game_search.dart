import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:neostation/models/database_game_model.dart';
import 'package:neostation/models/game_model.dart';
import 'package:neostation/models/system_model.dart';
import 'package:neostation/providers/sqlite_config_provider.dart';
import 'package:neostation/providers/file_provider.dart';
import 'package:neostation/repositories/game_repository.dart';
import 'package:neostation/repositories/system_repository.dart';
import 'package:neostation/screens/game_screen/my_games_list.dart';
import 'package:neostation/screens/game_screen/android_apps/android_apps_grid.dart';
import 'package:neostation/services/android_service.dart';
import 'package:neostation/services/gamepad/gamepad_navigation_manager.dart';
import 'package:neostation/utils/gamepad_nav.dart';

/// Hold-L1 search. Game results reveal the selected title rather than launching it.
class HotkeyGameSearch {
  static bool _open = false;

  static Future<void> show(BuildContext context, {String? systemFolder}) async {
    if (_open) return;
    _open = true;
    try {
      final result = await showDialog<_SearchEntry>(
        context: context,
        builder: (_) => _SearchDialog(systemFolder: systemFolder),
      );
      if (!context.mounted || result == null) return;
      if (result.package != null) {
        final launched = await AndroidService.launchPackage(result.package!);
        if (!context.mounted) return;
        if (!launched) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(content: Text('Could not open this app.')),
          );
        }
        return;
      }
      final game = result.game;
      final folder = result.system?.folderName ?? game?.systemFolderName;
      if (folder == null) return;
      final system =
          result.system ?? await SystemRepository.getSystemByFolderName(folder);
      if (!context.mounted || system == null) return;
      final fileProvider = context.read<FileProvider>();
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => system.folderName == 'android'
              ? AndroidAppsGrid(system: system)
              : SystemGamesList(
                  system: system,
                  fileProvider: fileProvider,
                  initialRomPath: game == null
                      ? null
                      : GameModel.fromDatabaseModel(game).romPath,
                ),
        ),
      );
    } finally {
      _open = false;
    }
  }
}

class _SearchEntry {
  final String title;
  final String subtitle;
  final DatabaseGameModel? game;
  final String? package;
  final SystemModel? system;
  final String aliases;
  const _SearchEntry(
    this.title,
    this.subtitle, {
    this.game,
    this.package,
    this.system,
    this.aliases = '',
  });
}

class _SearchDialog extends StatefulWidget {
  final String? systemFolder;
  const _SearchDialog({this.systemFolder});
  @override
  State<_SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<_SearchDialog> {
  final _query = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  late final String _layer = 'hotkey_search#${identityHashCode(this)}';
  late final GamepadNavigation _nav;
  List<_SearchEntry> _entries = [];
  int _selected = 0;
  bool _loading = true;
  bool _closing = false;
  bool _layerRegistered = false;
  String? _error;

  List<_SearchEntry> get _results {
    final query = _query.text.trim().toLowerCase();
    if (query.isEmpty) return _entries;

    return _entries.where((entry) {
      // Search the same title the user actually sees. The old implementation
      // concatenated title + aliases and used contains(), so typing a single
      // letter could surface an Android app whose displayed name started with
      // a completely different letter because that letter existed elsewhere.
      if (entry.title.trim().toLowerCase().startsWith(query)) return true;

      // Keep system shortcuts searchable by their short/folder/id aliases, but
      // require an alias itself to start with the query as well.
      if (entry.system != null) {
        return entry.aliases
            .toLowerCase()
            .split(RegExp(r'\s+'))
            .where((alias) => alias.isNotEmpty)
            .any((alias) => alias.startsWith(query));
      }
      return false;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _nav = GamepadNavigation(
      onNavigateUp: () => _move(-1),
      onNavigateDown: () => _move(1),
      onSelectItem: _choose,
      onBack: _close,
      onXButton: () => _focus.requestFocus(),
      // Navigation deliberately works while the keyboard is open: Down exits it.
      isTextFieldFocused: () => false,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _closing) return;
      _nav.initialize();
      GamepadNavigationManager.pushLayer(
        _layer,
        onActivate: _nav.activate,
        onDeactivate: _nav.deactivate,
      );
      _layerRegistered = true;
    });
    _load();
  }

  Future<void> _load() async {
    try {
      final config = context.read<SqliteConfigProvider>();
      final systems = widget.systemFolder == null
          ? config.detectedSystems
                .where(
                  (s) =>
                      !config.hiddenSystemFolders.contains(s.folderName) &&
                      !{
                        'all',
                        'favorites',
                        'recent',
                        'collections',
                      }.contains(s.folderName),
                )
                .toList()
          : <SystemModel>[];
      final games = await GameRepository.getAllGames();
      final entries = games
          .where(
            (g) =>
                !g.isHidden &&
                // On Android, installed apps are appended below from the live
                // PackageManager scan. Do not also add the cached Android rows
                // from the games database or stale labels can appear beside
                // the current application label and break prefix search.
                !(Platform.isAndroid &&
                    widget.systemFolder == null &&
                    g.systemFolderName == 'android') &&
                (widget.systemFolder == null ||
                    g.systemFolderName == widget.systemFolder),
          )
          .map((g) {
            final model = GameModel.fromDatabaseModel(g);
            return _SearchEntry(
              model.name.isEmpty ? model.romname : model.name,
              g.systemFolderName ?? 'Game',
              game: g,
            );
          })
          .toList();
      for (final system in systems) {
        entries.add(
          _SearchEntry(
            system.realName,
            'System • ${system.shortName ?? system.folderName}',
            system: system,
            aliases:
                '${system.shortName ?? ''} ${system.folderName} ${system.id ?? ''}',
          ),
        );
      }
      if (widget.systemFolder == null && Platform.isAndroid) {
        final apps = await AndroidService.getInstalledApps();
        for (final app in apps) {
          final package = (app['package'] ?? app['packageName'])?.toString();
          if (package == null || package.isEmpty) continue;
          entries.add(
            _SearchEntry(
              (app['name'] ?? app['label'])?.toString() ?? package,
              'Android app',
              package: package,
            ),
          );
        }
      }
      entries.sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
      if (mounted) {
        setState(() {
          _entries = entries;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load search results.';
        });
      }
    }
  }

  void _move(int delta) {
    final typing = _focus.hasFocus;
    _focus.unfocus();
    final results = _results;
    if (results.isEmpty) return;
    setState(
      () => _selected = typing
          ? 0
          : (_selected + delta).clamp(0, results.length - 1),
    );
    if (_scroll.hasClients) {
      _scroll.animateTo(
        (_selected * 72.0).clamp(0.0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    }
  }

  void _choose() {
    final results = _results;
    if (results.isEmpty || _selected >= results.length) return;
    _closeWith(results[_selected]);
  }

  void _close() => _closeWith(null);
  void _closeWith(_SearchEntry? entry) {
    if (!mounted || _closing) return;
    _closing = true;
    _focus.unfocus();
    _nav.deactivate();
    // Keep the modal layer until disposal. Reactivating the screen underneath
    // while the dialog still owns route focus can leave its controls inactive.
    Navigator.of(context).pop(entry);
  }

  @override
  void dispose() {
    _closing = true;
    _nav.dispose();
    _query.dispose();
    _focus.dispose();
    _scroll.dispose();
    // Dispose the search input/focus first, then restore the previous owner
    // exactly once, including barrier taps and Android Back dismissal.
    if (_layerRegistered) {
      _layerRegistered = false;
      GamepadNavigationManager.popLayer(_layer);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return AlertDialog(
      title: Text(
        widget.systemFolder == null
            ? 'Search systems, games and apps'
            : 'Search games',
      ),
      content: SizedBox(
        width: 650,
        height: 360,
        child: Column(
          children: [
            TextField(
              controller: _query,
              focusNode: _focus,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search by name',
              ),
              onChanged: (_) => setState(() => _selected = 0),
              onSubmitted: (_) => _focus.unfocus(),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(child: Text(_error!))
                  : results.isEmpty
                  ? const Center(child: Text('No matches'))
                  : ListView.builder(
                      controller: _scroll,
                      itemExtent: 72,
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        final entry = results[index];
                        return Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: index == _selected
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.transparent,
                              width: 1,
                            ),
                          ),
                          child: ListTile(
                            selectedTileColor: Colors.transparent,
                            leading: Icon(
                              entry.system != null
                                  ? Icons.videogame_asset
                                  : entry.package == null
                                  ? Icons.sports_esports
                                  : Icons.apps,
                            ),
                            title: Text(
                              entry.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(entry.subtitle),
                            onTap: () => _closeWith(entry),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: _close, child: const Text('Close'))],
    );
  }
}
