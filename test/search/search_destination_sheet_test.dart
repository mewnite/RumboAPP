import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rumbo/core/theme/app_theme.dart';
import 'package:rumbo/features/map/data/connectivity_provider.dart';
import 'package:rumbo/features/search/domain/place_search_service.dart';
import 'package:rumbo/features/search/domain/search_models.dart';
import 'package:rumbo/features/search/presentation/search_controller.dart';
import 'package:rumbo/features/search/presentation/search_destination_sheet.dart';
import 'package:rumbo/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TestSearchService implements PlaceSearchService {
  int remoteCalls = 0;

  @override
  Future<List<SearchResult>> search({
    required String query,
    double? userLatitude,
    double? userLongitude,
    bool allowRemote = true,
    Future<void>? remoteAbortTrigger,
  }) async {
    remoteCalls++;
    return [
      SearchResult(
        id: 'stop-1',
        kind: SearchEntityKind.stop,
        title: 'Av. 18 de Julio y Ejido',
        subtitle: 'Parada STM · Código 3004',
        latitude: -34.905,
        longitude: -56.191,
        precision: GeoPrecision.stopCoordinates,
        source: SearchDataSource.stmGtfsLocal,
        stopCode: '3004',
        lines: const ['14', '21', '180'],
      ),
      const SearchResult(
        id: 'addr-1',
        kind: SearchEntityKind.address,
        title: 'Av. Italia 2450',
        subtitle: 'La Blanqueada',
        latitude: -34.888,
        longitude: -56.149,
        precision: GeoPrecision.exactDoorNumber,
        source: SearchDataSource.ideUruguay,
      ),
    ];
  }

  @override
  Future<List<SearchResult>> searchLocal({
    required String query,
    double? userLatitude,
    double? userLongitude,
  }) async {
    return [
      SearchResult(
        id: 'stop-1',
        kind: SearchEntityKind.stop,
        title: 'Av. 18 de Julio y Ejido',
        subtitle: 'Parada STM · Código 3004',
        latitude: -34.905,
        longitude: -56.191,
        precision: GeoPrecision.stopCoordinates,
        source: SearchDataSource.stmGtfsLocal,
        stopCode: '3004',
        lines: const ['14', '21', '180'],
      ),
    ];
  }

  @override
  Future<List<SearchResult>> getRecentSearches({int limit = 10}) async {
    return const [
      SearchResult(
        id: 'rec-1',
        kind: SearchEntityKind.recentSearch,
        title: 'Tres Cruces',
        subtitle: 'Terminal y Shopping',
        latitude: -34.89,
        longitude: -56.16,
        precision: GeoPrecision.rooftopPoi,
        source: SearchDataSource.openStreetMap,
      ),
    ];
  }

  @override
  Future<void> saveRecentSearch(SearchResult result) async {}

  @override
  Future<void> clearRecentSearches() async {}
}

void main() {
  testWidgets(
    'SearchDestinationSheet muestra recientes, permite buscar y seleccionar destino',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'remote_place_search_enabled': true,
      });
      final searchService = TestSearchService();
      SearchResult? selectedResult;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            searchServiceProvider.overrideWithValue(searchService),
            networkAvailableProvider.overrideWith(
              (ref) => Stream<bool>.value(true),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('es', 'UY'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.light(),
            home: Scaffold(
              body: SearchDestinationSheet(
                onDestinationSelected: (result) {
                  selectedResult = result;
                },
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 1. Debe mostrar búsqueda reciente inicialmente
      expect(find.text('Búsquedas recientes'), findsOneWidget);
      expect(find.text('Tres Cruces'), findsOneWidget);

      // 2. Escribir en el campo de búsqueda
      await tester.enterText(find.byType(TextField), '18 de Julio');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      // 3. Al escribir solo muestra resultados locales.
      expect(find.text('Av. 18 de Julio y Ejido'), findsOneWidget);
      expect(find.text('14'), findsOneWidget);
      expect(find.text('21'), findsOneWidget);
      expect(find.text('180'), findsOneWidget);
      expect(find.text('Av. Italia 2450'), findsNothing);
      expect(searchService.remoteCalls, 0);
      await tester.tap(find.text('Buscar lugares en línea'));
      await tester.pumpAndSettle();
      expect(find.text('Av. Italia 2450'), findsOneWidget);
      expect(searchService.remoteCalls, 1);
      expect(find.text('Buscar lugares o direcciones'), findsNothing);

      // 4. Seleccionar un destino
      await tester.tap(find.byKey(const ValueKey('search-result-stop-1')));
      await tester.pumpAndSettle();

      expect(selectedResult, isNotNull);
      expect(selectedResult!.id, 'stop-1');
      expect(selectedResult!.title, 'Av. 18 de Julio y Ejido');
    },
  );

  testWidgets('pide consentimiento después de solicitar la búsqueda en línea', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final searchService = TestSearchService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchServiceProvider.overrideWithValue(searchService),
          networkAvailableProvider.overrideWith(
            (ref) => Stream<bool>.value(true),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('es', 'UY'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: Scaffold(
            body: SearchDestinationSheet(onDestinationSelected: (_) {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Shopping Nuevo Centro');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('Buscar lugares en línea'), findsOneWidget);
    expect(searchService.remoteCalls, 0);
    await tester.tap(find.text('Buscar lugares en línea'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Habilitar y buscar'));
    await tester.pumpAndSettle();

    expect(searchService.remoteCalls, 1);
    expect(find.text('Av. Italia 2450'), findsOneWidget);
    expect(find.text('Buscar lugares o direcciones'), findsNothing);
  });
}
