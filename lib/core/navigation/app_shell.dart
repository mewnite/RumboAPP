import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../l10n/generated/app_localizations.dart';

class AppShell extends StatelessWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  void _onDestinationSelected(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: TickerMode(
        enabled: navigationShell.currentIndex == 0,
        child: navigationShell,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _onDestinationSelected,
        destinations: [
          NavigationDestination(
            key: const ValueKey('navigation-map'),
            icon: const Icon(Symbols.map_rounded),
            selectedIcon: const Icon(Symbols.map_rounded, fill: 1),
            label: l10n.navigationMap,
          ),
          NavigationDestination(
            key: const ValueKey('navigation-favorites'),
            icon: const Icon(Symbols.favorite_rounded),
            selectedIcon: const Icon(Symbols.favorite_rounded, fill: 1),
            label: l10n.navigationFavorites,
          ),
          NavigationDestination(
            key: const ValueKey('navigation-settings'),
            icon: const Icon(Symbols.settings_rounded),
            selectedIcon: const Icon(Symbols.settings_rounded, fill: 1),
            label: l10n.navigationSettings,
          ),
        ],
      ),
    );
  }
}
