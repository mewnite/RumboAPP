import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/line_chip.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../map/data/connectivity_provider.dart';
import '../domain/search_models.dart';
import 'search_controller.dart';
import 'search_state.dart';

/// Hoja modal accesible para búsqueda y selección de destinos en Montevideo.
class SearchDestinationSheet extends ConsumerStatefulWidget {
  const SearchDestinationSheet({
    required this.onDestinationSelected,
    this.userLatitude,
    this.userLongitude,
    this.initialQuery = '',
    super.key,
  });

  final ValueChanged<SearchResult> onDestinationSelected;
  final double? userLatitude;
  final double? userLongitude;
  final String initialQuery;

  @override
  ConsumerState<SearchDestinationSheet> createState() =>
      _SearchDestinationSheetState();
}

class _SearchDestinationSheetState
    extends ConsumerState<SearchDestinationSheet> {
  late final TextEditingController _textController;
  final FocusNode _focusNode = FocusNode();
  bool _askedRemoteConsent = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialQuery);
    if (widget.initialQuery.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _triggerSearch(widget.initialQuery);
      });
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _triggerSearch(String query) {
    final hasNetwork = ref.read(networkAvailableProvider).asData?.value ?? true;
    final isOffline = !hasNetwork;
    final remoteEnabled =
        ref.read(remotePlaceSearchEnabledProvider).asData?.value ?? false;
    ref
        .read(searchControllerProvider.notifier)
        .onQueryChanged(
          query,
          userLatitude: widget.userLatitude,
          userLongitude: widget.userLongitude,
          isOffline: isOffline,
          allowRemote: remoteEnabled,
        );
    if (!remoteEnabled &&
        !isOffline &&
        !_askedRemoteConsent &&
        query.trim().length >= 3 &&
        RegExp(r'[a-zA-ZáéíóúñÁÉÍÓÚÑ]').hasMatch(query)) {
      _askedRemoteConsent = true;
      unawaited(_requestRemoteConsent());
    }
  }

  Future<void> _requestRemoteConsent() async {
    final l10n = AppLocalizations.of(context);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.tripGeocodingConsentTitle),
        content: Text(l10n.tripGeocodingConsentBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.tripGeocodingConsentAction),
          ),
        ],
      ),
    );
    if (!mounted || accepted != true) return;
    await ref.read(remotePlaceSearchEnabledProvider.notifier).setEnabled(true);
    if (mounted) {
      await ref
          .read(searchControllerProvider.notifier)
          .searchRemote(
            query: _textController.text,
            userLatitude: widget.userLatitude,
            userLongitude: widget.userLongitude,
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final searchState = ref.watch(searchControllerProvider);
    final remoteSearchEnabled =
        ref.watch(remotePlaceSearchEnabledProvider).asData?.value ?? false;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Barra de arrastre superior
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),

              // Campo principal de búsqueda
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _textController,
                  focusNode: _focusNode,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onChanged: _triggerSearch,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Symbols.search_rounded),
                    hintText: l10n.searchHint,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    suffixIcon: _textController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Symbols.close_rounded),
                            tooltip: l10n.actionClose,
                            onPressed: () {
                              _textController.clear();
                              _triggerSearch('');
                            },
                          )
                        : null,
                  ),
                ),
              ),

              if (remoteSearchEnabled &&
                  _textController.text.trim().length >= 3)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    l10n.tripGeocodingPrivacy,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ),

              // Barra de progreso sutil
              if (searchState.status == SearchStatus.loading)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(minHeight: 2),
                )
              else
                const SizedBox(height: 10),

              // Aviso si está sin conexión
              if (searchState.isLocalOnly)
                Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Symbols.wifi_off_rounded,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.searchOfflineNotice,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Cabezal de sección (Recientes vs Resultados)
              if (_textController.text.trim().isEmpty &&
                  searchState.results.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        l10n.searchRecent,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      TextButton(
                        onPressed: () => ref
                            .read(searchControllerProvider.notifier)
                            .clearHistory(),
                        child: Text(l10n.searchClearRecent),
                      ),
                    ],
                  ),
                ),

              // Lista de resultados
              Expanded(child: _buildBody(context, searchState, l10n)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    SearchState state,
    AppLocalizations l10n,
  ) {
    if (state.status == SearchStatus.empty) {
      return EmptyState(
        icon: const Icon(Symbols.location_off_rounded, size: 48),
        title: l10n.searchEmptyTitle,
        message: l10n.searchEmptyBody(state.query),
      );
    }

    if (state.status == SearchStatus.error && state.results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            state.errorMessage ?? l10n.mapFeedUnknownError,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      );
    }

    if (state.results.isEmpty && state.query.isEmpty) {
      return const SizedBox.shrink();
    }

    return ListView.separated(
      itemCount: state.results.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 64),
      itemBuilder: (context, index) {
        final result = state.results[index];
        return _SearchResultTile(
          result: result,
          onTap: () {
            ref.read(searchControllerProvider.notifier).selectResult(result);
            widget.onDestinationSelected(result);
          },
        );
      },
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({required this.result, required this.onTap});

  final SearchResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return InkWell(
      key: ValueKey('search-result-${result.id}'),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Icono identificador de entidad
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _kindBackgroundColor(result.kind, theme),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _kindIcon(result.kind),
                  color: _kindIconColor(result.kind, theme),
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),

              // Textos y chips de líneas
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      result.title,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      result.subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (result.lines.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final line in result.lines.take(5))
                            LineChip(
                              label: line,
                              backgroundColor: theme.colorScheme.primary,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // Etiqueta semántica de tipo
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  _kindLabel(result.kind, l10n),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _kindIcon(SearchEntityKind kind) {
    switch (kind) {
      case SearchEntityKind.stop:
        return Symbols.directions_bus_rounded;
      case SearchEntityKind.route:
        return Symbols.alt_route_rounded;
      case SearchEntityKind.address:
        return Symbols.home_pin_rounded;
      case SearchEntityKind.intersection:
        return Symbols.fork_right_rounded;
      case SearchEntityKind.poi:
        return Symbols.location_city_rounded;
      case SearchEntityKind.neighborhood:
        return Symbols.map_rounded;
      case SearchEntityKind.favorite:
        return Symbols.favorite_rounded;
      case SearchEntityKind.recentSearch:
        return Symbols.history_rounded;
    }
  }

  Color _kindBackgroundColor(SearchEntityKind kind, ThemeData theme) {
    if (kind == SearchEntityKind.stop || kind == SearchEntityKind.route) {
      return theme.colorScheme.primaryContainer;
    }
    return theme.colorScheme.surfaceContainerHighest;
  }

  Color _kindIconColor(SearchEntityKind kind, ThemeData theme) {
    if (kind == SearchEntityKind.stop || kind == SearchEntityKind.route) {
      return theme.colorScheme.onPrimaryContainer;
    }
    return theme.colorScheme.onSurfaceVariant;
  }

  String _kindLabel(SearchEntityKind kind, AppLocalizations l10n) {
    switch (kind) {
      case SearchEntityKind.stop:
        return l10n.searchKindStop;
      case SearchEntityKind.route:
        return l10n.searchKindRoute;
      case SearchEntityKind.address:
        return l10n.searchKindAddress;
      case SearchEntityKind.intersection:
        return l10n.searchKindIntersection;
      case SearchEntityKind.poi:
        return l10n.searchKindPoi;
      case SearchEntityKind.neighborhood:
        return l10n.searchKindNeighborhood;
      case SearchEntityKind.favorite:
        return l10n.searchKindFavorite;
      case SearchEntityKind.recentSearch:
        return l10n.searchKindRecent;
    }
  }
}
