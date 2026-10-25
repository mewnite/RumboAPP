import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/widgets/empty_state.dart';
import '../../../l10n/generated/app_localizations.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.favoritesScreenTitle)),
      body: EmptyState(
        icon: Icon(
          Symbols.favorite_rounded,
          size: 40,
          color: Theme.of(context).colorScheme.primary,
          fill: 1,
        ),
        title: l10n.favoritesEmptyTitle,
        message: l10n.favoritesEmptyBody,
      ),
    );
  }
}
