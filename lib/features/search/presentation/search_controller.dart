import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/transit_config.dart';
import '../../../features/stops_and_lines/data/transit_database.dart';
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
  final localSource = kIsWeb
      ? InMemoryTransitSearchSource(feed, repository)
      : LocalTransitSearchSource(() => TransitDatabase().open());
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
  Timer? _remoteDebounce;

  @override
  SearchState build() {
    ref.onDispose(() => _remoteDebounce?.cancel());
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
    bool allowRemote = false,
  }) {
    final trimmed = query.trim();
    _remoteDebounce?.cancel();

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

    // 1. Emisión inmediata local (< 10 ms)
    _searchLocalImmediate(
      trimmed,
      currentId,
      userLatitude,
      userLongitude,
      isLocalOnly: isOffline,
    );

    state = state.copyWith(isLocalOnly: isOffline);
    if (allowRemote && !isOffline && trimmed.length >= 3) {
      _remoteDebounce = Timer(const Duration(milliseconds: 450), () {
        if (_searchGeneration != currentId) return;
        final remoteId = ++_searchGeneration;
        state = state.copyWith(status: SearchStatus.loading);
        unawaited(
          _searchRemoteAndRank(trimmed, remoteId, userLatitude, userLongitude),
        );
      });
    }
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
    _remoteDebounce?.cancel();
    state = state.copyWith(query: trimmed, status: SearchStatus.loading);
    await _searchRemoteAndRank(trimmed, currentId, userLatitude, userLongitude);
  }

  Future<void> _searchLocalImmediate(
    String query,
    int generationId,
    double? userLatitude,
    double? userLongitude, {
    bool isLocalOnly = false,
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
    } on Exception catch (error) {
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
    double? userLongitude,
  ) async {
    try {
      final results = await _service.search(
        query: query,
        userLatitude: userLatitude,
        userLongitude: userLongitude,
        allowRemote: true,
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
    } on Exception catch (error) {
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
