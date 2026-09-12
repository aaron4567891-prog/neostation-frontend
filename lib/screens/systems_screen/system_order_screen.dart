import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/my_systems.dart';
import '../../providers/sqlite_config_provider.dart';
import '../../services/gamepad/gamepad_navigation_manager.dart';
import '../../services/sfx_service.dart';
import '../../utils/gamepad_nav.dart';

/// Reorders every non-recent card shown by the systems grid and carousel.
class SystemOrderScreen extends StatefulWidget {
  const SystemOrderScreen({super.key, required this.systems});

  final List<SystemInfo> systems;

  @override
  State<SystemOrderScreen> createState() => _SystemOrderScreenState();
}

class _SystemOrderScreenState extends State<SystemOrderScreen> {
  static const _layerId = 'system_order_screen';

  late final GamepadNavigation _gamepadNav;
  late List<SystemInfo> _systems;
  List<SystemInfo>? _orderBeforeMove;
  int _selectedIndex = 0;
  bool _moving = false;

  @override
  void initState() {
    super.initState();
    _systems = widget.systems.where((system) => !system.isGame).toList();
    _gamepadNav = GamepadNavigation(
      onNavigateUp: (_) => _moveSelection(-1),
      onNavigateDown: (_) => _moveSelection(1),
      onNavigateLeft: (_) => _moveSelection(-1),
      onNavigateRight: (_) => _moveSelection(1),
      onSelectItem: _toggleMove,
      onBack: _handleBack,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _gamepadNav.initialize();
      GamepadNavigationManager.pushLayer(
        _layerId,
        onActivate: _gamepadNav.activate,
        onDeactivate: _gamepadNav.deactivate,
      );
    });
  }

  @override
  void dispose() {
    GamepadNavigationManager.popLayer(_layerId);
    _gamepadNav.dispose();
    super.dispose();
  }

  void _moveSelection(int delta) {
    if (_systems.isEmpty) return;
    final next = (_selectedIndex + delta).clamp(0, _systems.length - 1);
    if (next == _selectedIndex) return;
    SfxService().playNavSound();
    setState(() {
      if (_moving) {
        final item = _systems.removeAt(_selectedIndex);
        _systems.insert(next, item);
      }
      _selectedIndex = next;
    });
  }

  void _toggleMove() {
    if (_systems.isEmpty) return;
    SfxService().playEnterSound();
    if (!_moving) {
      setState(() {
        _orderBeforeMove = List<SystemInfo>.of(_systems);
        _moving = true;
      });
      return;
    }
    setState(() {
      _moving = false;
      _orderBeforeMove = null;
    });
    _persistOrder();
  }

  void _handleBack() {
    if (_moving) {
      SfxService().playBackSound();
      setState(() {
        _systems = _orderBeforeMove ?? _systems;
        _orderBeforeMove = null;
        _moving = false;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  void _persistOrder() {
    unawaited(
      context.read<SqliteConfigProvider>().updateCustomSystemOrder(
        _systems.map((system) => system.folderName ?? '').toList(),
      ),
    );
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      final item = _systems.removeAt(oldIndex);
      _systems.insert(newIndex, item);
      _selectedIndex = newIndex;
      _moving = false;
      _orderBeforeMove = null;
    });
    SfxService().playNavSound();
    _persistOrder();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_moving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('System Order')),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
              child: Text(
                _moving
                    ? 'Moving ${_systems[_selectedIndex].title ?? 'system'} — use the D-pad, then press A to save. Press B to cancel.'
                    : 'Press A on a card to move it, or hold its drag handle. Recently Played always stays first.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
            Expanded(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                buildDefaultDragHandles: false,
                itemCount: _systems.length,
                onReorderItem: _reorder,
                itemBuilder: (context, index) {
                  final system = _systems[index];
                  final selected = index == _selectedIndex;
                  return Card(
                    key: ValueKey(system.folderName),
                    color: selected
                        ? Theme.of(context).colorScheme.primaryContainer
                        : null,
                    child: ListTile(
                      onTap: () => setState(() => _selectedIndex = index),
                      leading: SizedBox(
                        width: 36,
                        child: Center(
                          child: Text(
                            '${index + 1}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ),
                      title: Text(
                        system.title ?? system.folderName ?? 'System',
                      ),
                      subtitle: system.shortName == null
                          ? null
                          : Text(system.shortName!),
                      trailing: ReorderableDelayedDragStartListener(
                        index: index,
                        child: const Padding(
                          padding: EdgeInsets.all(12),
                          child: Icon(Icons.drag_handle_rounded),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
