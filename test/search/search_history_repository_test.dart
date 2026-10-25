import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rumbo/features/search/data/search_history_repository_impl.dart';
import 'package:rumbo/features/search/domain/search_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SearchHistoryRepositoryImpl', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('agrega y recupera destinos recientes preservando orden cronológico inverso', () async {
      final repo = SearchHistoryRepositoryImpl();

      const item1 = SearchResult(
        id: 'dest-1',
        kind: SearchEntityKind.address,
        title: 'Av. Italia 2450',
        subtitle: 'La Blanqueada',
        latitude: -34.88,
        longitude: -56.14,
        precision: GeoPrecision.exactDoorNumber,
        source: SearchDataSource.ideUruguay,
      );

      const item2 = SearchResult(
        id: 'dest-2',
        kind: SearchEntityKind.stop,
        title: 'Tres Cruces',
        subtitle: 'Parada STM',
        latitude: -34.89,
        longitude: -56.16,
        precision: GeoPrecision.stopCoordinates,
        source: SearchDataSource.stmGtfsLocal,
      );

      await repo.add(item1);
      await repo.add(item2);

      final recents = await repo.getRecent();
      expect(recents, hasLength(2));
      expect(recents.first.id, 'dest-2'); // El más reciente primero
      expect(recents.last.id, 'dest-1');
      expect(recents.first.kind, SearchEntityKind.recentSearch);
    });

    test('evita duplicados al re-seleccionar un destino existente', () async {
      final repo = SearchHistoryRepositoryImpl();

      const item = SearchResult(
        id: 'dest-1',
        kind: SearchEntityKind.address,
        title: '18 de Julio y Ejido',
        subtitle: 'Centro',
        latitude: -34.90,
        longitude: -56.19,
        precision: GeoPrecision.intersectionPoint,
        source: SearchDataSource.ideUruguay,
      );

      await repo.add(item);
      await repo.add(item);

      final recents = await repo.getRecent();
      expect(recents, hasLength(1));
    });

    test('limpia el historial por completo', () async {
      final repo = SearchHistoryRepositoryImpl();

      await repo.add(
        const SearchResult(
          id: 'test',
          kind: SearchEntityKind.poi,
          title: 'Facultad de Derecho',
          subtitle: 'Montevideo',
          latitude: -34.90,
          longitude: -56.17,
          precision: GeoPrecision.rooftopPoi,
          source: SearchDataSource.openStreetMap,
        ),
      );

      expect(await repo.getRecent(), hasLength(1));
      await repo.clear();
      expect(await repo.getRecent(), isEmpty);
    });
  });
}
