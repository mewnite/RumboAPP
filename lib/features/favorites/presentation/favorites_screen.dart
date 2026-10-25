import 'dart:async';

import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/widgets/empty_state.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../map/presentation/map_action_provider.dart';
import '../../search/domain/search_models.dart';
import '../../search/presentation/search_destination_sheet.dart';
import '../../stops_and_lines/domain/transit_models.dart';
import '../../stops_and_lines/presentation/stop_details_sheet.dart';
import '../../trip_planner/domain/trip_planner.dart';
import '../domain/favorite.dart';
import 'favorites_controller.dart';

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final favorites = ref.watch(favoritesControllerProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.favoritesScreenTitle)),
      body: favorites.when(
        loading: () => Semantics(
          label: l10n.favoritesLoading,
          child: const Center(child: CircularProgressIndicator()),
        ),
        error: (error, _) => EmptyState(
          icon: Icon(
            Symbols.error_rounded,
            size: 40,
            color: Theme.of(context).colorScheme.error,
          ),
          title: l10n.favoritesLoadErrorTitle,
          message: l10n.favoritesLoadErrorBody,
          footer: FilledButton.icon(
            onPressed: () => ref.invalidate(favoritesControllerProvider),
            icon: const Icon(Symbols.refresh_rounded),
            label: Text(l10n.actionRetry),
          ),
        ),
        data: (saved) => _FavoritesList(favorites: saved),
      ),
    );
  }
}

class _FavoritesList extends ConsumerWidget {
  const _FavoritesList({required this.favorites});

  final List<Favorite> favorites;

  Favorite? _placeFor(FavoritePlaceSlot slot) {
    for (final favorite in favorites) {
      if (favorite.type == FavoriteType.place && favorite.placeSlot == slot) {
        return favorite;
      }
    }
    return null;
  }

  int _indexOf(Favorite favorite) {
    final index = favorites.indexOf(favorite);
    return index < 0 ? favorites.length : index;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final places = favorites
        .where(
          (favorite) =>
              favorite.type == FavoriteType.place && favorite.placeSlot == null,
        )
        .toList(growable: false);
    final stops = favorites
        .where((favorite) => favorite.type == FavoriteType.stop)
        .toList(growable: false);
    final lines = favorites
        .where((favorite) => favorite.type == FavoriteType.line)
        .toList(growable: false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        if (favorites.isEmpty) _EmptyOverview(l10n: l10n),
        _SectionTitle(l10n.favoritesPlacesSection),
        for (final slot in FavoritePlaceSlot.values)
          _PlaceSlotTile(
            slot: slot,
            favorite: _placeFor(slot),
            onDefine: () => unawaited(_definePlace(context, ref, slot)),
            onOpen: (favorite) => _openPlace(context, ref, favorite),
            onRename: (favorite) => unawaited(_rename(context, ref, favorite)),
            onDelete: (favorite) =>
                unawaited(_delete(context, ref, favorite, _indexOf(favorite))),
          ),
        for (final favorite in places)
          _FavoriteTile(
            key: ValueKey('favorite-place-${favorite.key}'),
            favorite: favorite,
            icon: Symbols.bookmark_rounded,
            title: favorite.name,
            subtitle: l10n.favoritesPlaceSubtitle,
            onTap: () => _openPlace(context, ref, favorite),
            onLongPress: () => unawaited(_rename(context, ref, favorite)),
            onDelete: () =>
                unawaited(_delete(context, ref, favorite, _indexOf(favorite))),
          ),
        const SizedBox(height: 20),
        _SectionTitle(l10n.favoritesStopsSection),
        if (stops.isEmpty)
          _EmptySection(text: l10n.favoritesEmptyStops)
        else
          for (final favorite in stops)
            _FavoriteTile(
              key: ValueKey('favorite-stop-${favorite.id}'),
              favorite: favorite,
              icon: Symbols.favorite_rounded,
              title: favorite.name,
              subtitle: l10n.favoritesStopSubtitle,
              onTap: () => unawaited(_openStop(context, ref, favorite)),
              onLongPress: () => unawaited(_rename(context, ref, favorite)),
              onDelete: () => unawaited(
                _delete(context, ref, favorite, _indexOf(favorite)),
              ),
            ),
        const SizedBox(height: 20),
        _SectionTitle(l10n.favoritesLinesSection),
        if (lines.isEmpty)
          _EmptySection(text: l10n.favoritesEmptyLines)
        else
          for (final favorite in lines)
            _FavoriteTile(
              key: ValueKey('favorite-line-${favorite.id}'),
              favorite: favorite,
              icon: Symbols.favorite_rounded,
              title: favorite.name,
              subtitle: l10n.favoritesLineSubtitle,
              semanticLabel: l10n.favoritesShowLineOnMap(favorite.name),
              onTap: () => _openLine(context, ref, favorite),
              onLongPress: () => unawaited(_rename(context, ref, favorite)),
              onDelete: () => unawaited(
                _delete(context, ref, favorite, _indexOf(favorite)),
              ),
            ),
        const SizedBox(height: 24),
        Text(
          l10n.favoritesHelp,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Future<void> _definePlace(
    BuildContext context,
    WidgetRef ref,
    FavoritePlaceSlot slot,
  ) async {
    final result = await showModalBottomSheet<SearchResult>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SearchDestinationSheet(
        onDestinationSelected: (result) =>
            Navigator.of(sheetContext).pop(result),
      ),
    );
    if (!context.mounted || result == null) return;
    await ref
        .read(favoritesControllerProvider.notifier)
        .setPlace(
          slot: slot,
          name: result.title,
          latitude: result.latitude,
          longitude: result.longitude,
        );
  }

  void _openPlace(BuildContext context, WidgetRef ref, Favorite favorite) {
    final latitude = favorite.latitude;
    final longitude = favorite.longitude;
    if (latitude == null || longitude == null) return;
    ref
        .read(mapActionProvider.notifier)
        .planTo(
          TripEndpoint(
            name: favorite.name,
            latitude: latitude,
            longitude: longitude,
          ),
        );
    context.go('/map');
  }

  void _openLine(BuildContext context, WidgetRef ref, Favorite favorite) {
    ref
        .read(mapActionProvider.notifier)
        .showRoute(Route(id: favorite.id, shortName: favorite.name));
    context.go('/map');
  }

  Future<void> _openStop(
    BuildContext context,
    WidgetRef ref,
    Favorite favorite,
  ) async {
    final latitude = favorite.latitude ?? 0;
    final longitude = favorite.longitude ?? 0;
    final endpoint = TripEndpoint(
      name: favorite.name,
      latitude: latitude,
      longitude: longitude,
      stop: Stop(
        id: favorite.id,
        name: favorite.name,
        latitude: latitude,
        longitude: longitude,
      ),
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StopDetailsSheet(
        stop: endpoint.stop!,
        onHowToGetThere: () {
          Navigator.of(sheetContext).pop();
          if (!context.mounted) return;
          ref.read(mapActionProvider.notifier).planTo(endpoint);
          context.go('/map');
        },
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Favorite favorite,
    int index,
  ) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(favoritesControllerProvider.notifier).remove(favorite);
    if (!context.mounted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.favoritesRemoved(favorite.name)),
          action: SnackBarAction(
            label: l10n.actionUndo,
            onPressed: () => unawaited(
              ref
                  .read(favoritesControllerProvider.notifier)
                  .restore(favorite, index),
            ),
          ),
        ),
      );
  }

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    Favorite favorite,
  ) async {
    final l10n = AppLocalizations.of(context);
    var text = favorite.name;
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.favoritesRenameTitle),
        content: TextFormField(
          initialValue: favorite.name,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onChanged: (value) => text = value,
          onFieldSubmitted: (value) => Navigator.of(dialogContext).pop(value),
          decoration: InputDecoration(labelText: l10n.favoritesNameLabel),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              MaterialLocalizations.of(dialogContext).cancelButtonLabel,
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(text),
            child: Text(l10n.actionSave),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    await ref.read(favoritesControllerProvider.notifier).rename(favorite, name);
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
  );
}

class _EmptyOverview extends StatelessWidget {
  const _EmptyOverview({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.favoritesEmptyTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          l10n.favoritesEmptyBody,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    ),
  );
}

class _EmptySection extends StatelessWidget {
  const _EmptySection({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}

class _PlaceSlotTile extends StatelessWidget {
  const _PlaceSlotTile({
    required this.slot,
    required this.favorite,
    required this.onDefine,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  final FavoritePlaceSlot slot;
  final Favorite? favorite;
  final VoidCallback onDefine;
  final ValueChanged<Favorite> onOpen;
  final ValueChanged<Favorite> onRename;
  final ValueChanged<Favorite> onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = slot == FavoritePlaceSlot.home
        ? l10n.favoritesHome
        : l10n.favoritesWork;
    final saved = favorite;
    if (saved == null) {
      return ListTile(
        key: ValueKey('favorite-slot-${slot.name}'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: Icon(
          Symbols.bookmark_border_rounded,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        title: Text(label),
        subtitle: Text(l10n.favoritesPlaceNotSet),
        trailing: Semantics(
          button: true,
          label: l10n.favoritesDefinePlace(label),
          child: TextButton(
            key: ValueKey('favorite-define-${slot.name}'),
            onPressed: onDefine,
            child: Text(l10n.favoritesDefine),
          ),
        ),
        onTap: onDefine,
      );
    }

    return Dismissible(
      key: ValueKey('favorite-${saved.key}'),
      direction: DismissDirection.endToStart,
      background: const _DeleteBackground(),
      onDismissed: (_) => onDelete(saved),
      child: ListTile(
        key: ValueKey('favorite-place-${slot.name}'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: Icon(
          Symbols.bookmark_rounded,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: Text(label),
        subtitle: Text(saved.name),
        trailing: const Icon(Symbols.chevron_right_rounded),
        onTap: () => onOpen(saved),
        onLongPress: () => onRename(saved),
      ),
    );
  }
}

class _FavoriteTile extends StatelessWidget {
  const _FavoriteTile({
    required this.favorite,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.onLongPress,
    required this.onDelete,
    this.semanticLabel,
    super.key,
  });

  final Favorite favorite;
  final IconData icon;
  final String title;
  final String subtitle;
  final String? semanticLabel;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final tile = ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Symbols.chevron_right_rounded),
      onTap: onTap,
      onLongPress: onLongPress,
    );

    return Dismissible(
      key: ValueKey('favorite-${favorite.key}'),
      direction: DismissDirection.endToStart,
      background: const _DeleteBackground(),
      onDismissed: (_) => onDelete(),
      child: semanticLabel == null
          ? tile
          : Semantics(button: true, label: semanticLabel, child: tile),
    );
  }
}

class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colorScheme.error,
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 20),
          child: Icon(Symbols.delete_rounded, color: colorScheme.onError),
        ),
      ),
    );
  }
}
