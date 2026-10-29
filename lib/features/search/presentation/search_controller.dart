import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/transit_config.dart';
import '../../../core/debug/performance_measurement.dart';
import '../../favorites/domain/favorite.dart';
import '../../favorites/presentation/favorites_controller.dart';
import '../../../features/stops_and_lines/presentation/feed_update_controller.dart';
import '../../../features/stops_and_lines/presentation/transit_repository_provider.dart';
import '../data/in_memory_transit_search_source.dart';
import '../data/local_transit_search_source.dart';
import '../data/remote_geocoding_source.dart';
import '../data/search_history_repository_impl.dart';
import '../domain/place_search_service.dart';
import '../domain/query_normalizer.dart';
import '../domain/ranking_engine.dart';
import '../domain/search_models.dart';
import 'search_state.dart';

final searchServiceProvider = Provider<PlaceSearchService>((ref) {
  final endpoint = transitConfig.placeSearchEndpoint;
  final feed = ref.watch(feedUpdateControllerProvider).asData?.value.feed;
  final repository = ref.watch(transitRepositoryProvider);
  Iterable<SearchResult> savedPlaces() {
    final favorites =
        ref.read(favoritesControllerProvider).asData?.value ?? const [];
    return favorites
        .where(
          (favorite) =>
              favorite.type == FavoriteType.place &&
              favorite.latitude != null &&
              favorite.longitude != null,
        )
        .map(
          (favorite) => SearchResult(
            id: 'favorite:${favorite.id}',
            kind: SearchEntityKind.favorite,
            title: favorite.name,
            subtitle: 'Lugar guardado',
            latitude: favorite.latitude!,
            longitude: favorite.longitude!,
            precision: GeoPrecision.approximateArea,
            source: SearchDataSource.userStorage,
          ),
        );
  }

  final localSource = kIsWeb
      ? InMemoryTransitSearchSource(
          feed,
          repository,
          savedPlacesProvider: savedPlaces,
        )
      : LocalTransitSearchSource(
          () => ref.read(transitDatabaseProvider),
          savedPlacesProvider: savedPlaces,
        );
  final remoteSource = RemoteGeocodingSource(
    endpoint: endpoint.isNotEmpty ? endpoint : defaultTargetPlatformUrl,
  );
  final historyRepo = SearchHistoryRepositoryImpl();

  return DefaultPlaceSearchService(
    localTransitRepo: localSource,
    geocodingRepo: remoteSource,
    historyRepo: historyRepo,
    queryParser: const MontevideoQueryParser(),
    rankingEngine: const SmartRankingEngine(),
  );
});

final remotePlaceSearchEnabledProvider =
    AsyncNotifierProvider<RemotePlaceSearchEnabledController, bool>(
      RemotePlaceSearchEnabledController.new,
    );

class RemotePlaceSearchEnabledController extends AsyncNotifier<bool> {
  static const _preferenceKey = 'remote_place_search_enabled';

  @override
  Future<bool> build() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_preferenceKey) ?? false;
  }

  Future<void> setEnabled(bool enabled) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(_preferenceKey, enabled);
      state = AsyncData(enabled);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }
}

String get defaultTargetPlatformUrl => 'http://127.0.0.1:8765/geocode';

final searchControllerProvider =
    NotifierProvider<DestinationSearchController, SearchState>(
      DestinationSearchController.new,
    );

class DestinationSearchController extends Notifier<SearchState> {
  int _searchGeneration = 0;
  Timer? _localDebounce;
  PerformanceMeasurement? _inputMeasurement;
  Completer<void>? _remoteAbort;

  @override
  SearchState build() {
    ref.onDispose(() {
      _searchGeneration++;
      _localDebounce?.cancel();
      _cancelRemoteSearch();
      _inputMeasurement?.finish(details: 'cancelled');
    });
    Future.microtask(loadRecentSearches);
    return const SearchState();
  }

  PlaceSearchService get _service => ref.read(searchServiceProvider);

  Future<void> loadRecentSearches() async {
    try {
      final recents = await _service.getRecentSearches();
      if (state.query.isEmpty) {
        state = state.copyWith(
          status: recents.isNotEmpty
              ? SearchStatus.success
              : SearchStatus.initial,
          results: recents,
        );
      }
    } on Exception catch (error) {
      if (state.query.isEmpty) {
        state = state.copyWith(
          status: SearchStatus.error,
          errorMessage: error.toString(),
        );
      }
    }
  }

  void onQueryChanged(
    String query, {
    double? userLatitude,
    double? userLongitude,
    bool isOffline = false,
  }) {
    final trimmed = query.trim();
    _localDebounce?.cancel();
    _cancelRemoteSearch();
    _inputMeasurement?.finish(details: 'superseded');
    _inputMeasurement = null;

    if (trimmed.isEmpty) {
      _searchGeneration++;
      state = state.copyWith(
        query: '',
        status: SearchStatus.initial,
        results: const [],
      );
      loadRecentSearches();
      return;
    }

    final currentId = ++_searchGeneration;
    state = state.copyWith(
      query: trimmed,
      status: trimmed.length >= 2 ? SearchStatus.loading : SearchStatus.initial,
      results: const [],
      isLocalOnly: isOffline,
    );
    if (trimmed.length < 2) return;

    // Measure from the final text edit, including the debounce, through results.
    final measurement = PerformanceMeasurement.start('search.input');
    _inputMeasurement = measurement;
    _localDebounce = Timer(const Duration(milliseconds: 200), () {
      if (_searchGeneration != currentId) return;
      unawaited(
        _searchLocalImmediate(
          trimmed,
          currentId,
          userLatitude,
          userLongitude,
          isLocalOnly: isOffline,
          measurement: measurement,
        ),
      );
    });
  }

  Future<void> searchRemote({
    required String query,
    double? userLatitude,
    double? userLongitude,
  }) async {
    if (ref.read(remotePlaceSearchEnabledProvider).asData?.value != true) {
      return;
    }
    final trimmed = query.trim();
    if (trimmed.length < 3) return;
    final currentId = ++_searchGeneration;
    _localDebounce?.cancel();
    _cancelRemoteSearch();
    _inputMeasurement?.finish(details: 'superseded_by_remote');
    _inputMeasurement = null;
    state = state.copyWith(
      query: trimmed,
      status: SearchStatus.loading,
      results: const [],
    );
    final abort = Completer<void>();
    _remoteAbort = abort;
    await _searchRemoteAndRank(
      trimmed,
      currentId,
      userLatitude,
      userLongitude,
      abortTrigger: abort.future,
    );
    if (identical(_remoteAbort, abort)) _remoteAbort = null;
  }

  void _cancelRemoteSearch() {
    final abort = _remoteAbort;
    if (abort != null && !abort.isCompleted) abort.complete();
    _remoteAbort = null;
  }

  Future<void> _searchLocalImmediate(
    String query,
    int generationId,
    double? userLatitude,
    double? userLongitude, {
    bool isLocalOnly = false,
    required PerformanceMeasurement measurement,
  }) async {
    try {
      final localResults = await _service.searchLocal(
        query: query,
        userLatitude: userLatitude,
        userLongitude: userLongitude,
      );

      if (_searchGeneration == generationId) {
        state = state.copyWith(
          query: query,
          status: localResults.isNotEmpty
              ? SearchStatus.success
              : SearchStatus.loading,
          results: localResults,
          isLocalOnly: isLocalOnly,
          errorMessage: null,
        );
      }
      measurement.finish(details: 'results=${localResults.length}');
      if (identical(_inputMeasurement, measurement)) _inputMeasurement = null;
    } on Exception catch (error) {
      measurement.finish(details: 'error=${error.runtimeType}');
      if (identical(_inputMeasurement, measurement)) _inputMeasurement = null;
      if (_searchGeneration == generationId) {
        state = state.copyWith(
          query: query,
          status: SearchStatus.error,
          errorMessage: error.toString(),
          isLocalOnly: isLocalOnly,
        );
      }
    }
  }

  Future<void> _searchRemoteAndRank(
    String query,
    int generationId,
    double? userLatitude,
    double? userLongitude, {
    required Future<void> abortTrigger,
  }) async {
    final measurement = PerformanceMeasurement.start('search.remote');
    try {
      final results = await _service.search(
        query: query,
        userLatitude: userLatitude,
        userLongitude: userLongitude,
        allowRemote: true,
        remoteAbortTrigger: abortTrigger,
      );

      if (_searchGeneration == generationId) {
        state = state.copyWith(
          query: query,
          status: results.isNotEmpty
              ? SearchStatus.success
              : SearchStatus.empty,
          results: results,
          isLocalOnly: false,
          errorMessage: null,
        );
      }
      measurement.finish(details: 'results=${results.length}');
    } on Exception catch (error) {
      measurement.finish(details: 'error=${error.runtimeType}');
      if (_searchGeneration == generationId) {
        if (state.results.isNotEmpty) {
          state = state.copyWith(
            status: SearchStatus.success,
            isLocalOnly: true,
          );
        } else {
          state = state.copyWith(
            status: SearchStatus.error,
            errorMessage: error.toString(),
          );
        }
      }
    }
  }

  Future<void> selectResult(SearchResult result) async {
    await _service.saveRecentSearch(result);
  }

  Future<void> clearHistory() async {
    await _service.clearRecentSearches();
    if (state.query.isEmpty) {
      state = state.copyWith(results: const []);
    }
  }
}
