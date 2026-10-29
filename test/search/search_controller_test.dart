import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rumbo/features/search/domain/place_search_service.dart';
import 'package:rumbo/features/search/domain/search_models.dart';
import 'package:rumbo/features/search/presentation/search_controller.dart';
import 'package:rumbo/features/search/presentation/search_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockPlaceSearchService implements PlaceSearchService {
  MockPlaceSearchService({
    this.localDelay = Duration.zero,
    this.remoteDelay = Duration.zero,
  });

  final Duration localDelay;
  final Duration remoteDelay;
  int searchCalls = 0;
  int localCalls = 0;
  int remoteAbortSignals = 0;
  String lastQuery = '';

  @override
  Future<List<SearchResult>> search({
    required String query,
    double? userLatitude,
    double? userLongitude,
    bool allowRemote = true,
    Future<void>? remoteAbortTrigger,
  }) async {
    searchCalls++;
    lastQuery = query;
    if (remoteAbortTrigger != null) {
      unawaited(remoteAbortTrigger.then((_) => remoteAbortSignals++));
    }
    if (remoteDelay > Duration.zero) await Future<void>.delayed(remoteDelay);
    return [
      SearchResult(
        id: 'res-$query',
        kind: SearchEntityKind.address,
        title: 'Resultado para $query',
        subtitle: 'Montevideo',
        latitude: -34.90,
        longitude: -56.19,
        precision: GeoPrecision.streetSegment,
        source: SearchDataSource.openStreetMap,
      ),
    ];
  }

  @override
  Future<List<SearchResult>> searchLocal({
    required String query,
    double? userLatitude,
    double? userLongitude,
  }) async {
    localCalls++;
    if (localDelay > Duration.zero) await Future<void>.delayed(localDelay);
    return [
      SearchResult(
        id: 'local-$query',
        kind: SearchEntityKind.stop,
        title: 'Parada local $query',
        subtitle: 'Parada STM',
        latitude: -34.90,
        longitude: -56.19,
        precision: GeoPrecision.stopCoordinates,
        source: SearchDataSource.stmGtfsLocal,
      ),
    ];
  }

  @override
  Future<List<SearchResult>> getRecentSearches({int limit = 10}) async => [];

  @override
  Future<void> saveRecentSearch(SearchResult result) async {}

  @override
  Future<void> clearRecentSearches() async {}
}

void main() {
  group('DestinationSearchController', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'remote_place_search_enabled': true,
      });
    });

    test(
      'al escribir solo busca local aunque la búsqueda remota esté activada',
      () async {
        final mockService = MockPlaceSearchService();
        final container = ProviderContainer(
          overrides: [searchServiceProvider.overrideWithValue(mockService)],
        );
        addTearDown(container.dispose);
        await container.read(remotePlaceSearchEnabledProvider.future);

        final notifier = container.read(searchControllerProvider.notifier);
        expect(
          container.read(searchControllerProvider).status,
          SearchStatus.initial,
        );
        notifier.onQueryChanged('Italia');
        await Future<void>.delayed(const Duration(milliseconds: 250));
        expect(container.read(searchControllerProvider).results, isNotEmpty);
        expect(
          container.read(searchControllerProvider).results.first.id,
          'local-Italia',
        );
        expect(mockService.searchCalls, 0);
        expect(mockService.localCalls, 1);
      },
    );

    test('ejecuta búsqueda remota solo tras acción explícita', () async {
      final mockService = MockPlaceSearchService();
      final container = ProviderContainer(
        overrides: [searchServiceProvider.overrideWithValue(mockService)],
      );
      addTearDown(container.dispose);
      await container.read(remotePlaceSearchEnabledProvider.future);

      final notifier = container.read(searchControllerProvider.notifier);
      notifier.onQueryChanged('Italia');
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(mockService.searchCalls, 0);

      await notifier.searchRemote(query: 'Italia');
      expect(mockService.searchCalls, 1);
      expect(
        container.read(searchControllerProvider).results.first.id,
        'res-Italia',
      );
    });

    test('cancela la búsqueda remota cuando cambia la consulta', () async {
      final mockService = MockPlaceSearchService(
        remoteDelay: const Duration(milliseconds: 80),
      );
      final container = ProviderContainer(
        overrides: [searchServiceProvider.overrideWithValue(mockService)],
      );
      addTearDown(container.dispose);
      await container.read(remotePlaceSearchEnabledProvider.future);

      final notifier = container.read(searchControllerProvider.notifier);
      final pending = notifier.searchRemote(query: 'Italia');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      notifier.onQueryChanged('Centro');
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await pending;

      expect(mockService.remoteAbortSignals, 1);
      expect(container.read(searchControllerProvider).query, 'Centro');
      expect(
        container.read(searchControllerProvider).results.first.id,
        'local-Centro',
      );
    });

    test(
      'no consulta lugares en línea al escribir aunque esté habilitado',
      () async {
        final mockService = MockPlaceSearchService();
        final container = ProviderContainer(
          overrides: [searchServiceProvider.overrideWithValue(mockService)],
        );
        addTearDown(container.dispose);
        await container.read(remotePlaceSearchEnabledProvider.future);

        container
            .read(searchControllerProvider.notifier)
            .onQueryChanged('Shopping Nuevo Centro');
        await Future<void>.delayed(const Duration(milliseconds: 250));
        expect(mockService.localCalls, 1);
        expect(mockService.searchCalls, 0);
      },
    );

    test(
      'espera 200 ms y requiere dos caracteres para buscar localmente',
      () async {
        final mockService = MockPlaceSearchService();
        final container = ProviderContainer(
          overrides: [searchServiceProvider.overrideWithValue(mockService)],
        );
        addTearDown(container.dispose);
        await container.read(remotePlaceSearchEnabledProvider.future);

        final notifier = container.read(searchControllerProvider.notifier);
        notifier.onQueryChanged('A');
        await Future<void>.delayed(const Duration(milliseconds: 250));
        expect(mockService.localCalls, 0);

        notifier.onQueryChanged('It');
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(mockService.localCalls, 0);
        await Future<void>.delayed(const Duration(milliseconds: 180));
        expect(mockService.localCalls, 1);
      },
    );

    test(
      'no llama la búsqueda remota si el interruptor está apagado',
      () async {
        SharedPreferences.setMockInitialValues({});
        final mockService = MockPlaceSearchService();
        final container = ProviderContainer(
          overrides: [searchServiceProvider.overrideWithValue(mockService)],
        );
        addTearDown(container.dispose);
        await container.read(remotePlaceSearchEnabledProvider.future);

        final notifier = container.read(searchControllerProvider.notifier);
        notifier.onQueryChanged('Italia');
        await notifier.searchRemote(query: 'Italia');
        expect(mockService.searchCalls, 0);
      },
    );

    test('omite consulta remota cuando isOffline es true', () async {
      final mockService = MockPlaceSearchService();
      final container = ProviderContainer(
        overrides: [searchServiceProvider.overrideWithValue(mockService)],
      );
      addTearDown(container.dispose);
      await container.read(remotePlaceSearchEnabledProvider.future);

      final notifier = container.read(searchControllerProvider.notifier);
      notifier.onQueryChanged('Centro', isOffline: true);
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(container.read(searchControllerProvider).isLocalOnly, isTrue);
      expect(mockService.searchCalls, 0);
      expect(mockService.localCalls, 1);
    });
  });
}
