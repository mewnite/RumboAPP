import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rumbo/core/theme/app_theme.dart';
import 'package:rumbo/features/favorites/data/fake_favorites_repository.dart';
import 'package:rumbo/features/favorites/data/shared_preferences_favorites_repository.dart';
import 'package:rumbo/features/favorites/domain/favorite.dart';
import 'package:rumbo/features/favorites/domain/favorites_repository.dart';
import 'package:rumbo/features/favorites/presentation/favorites_controller.dart';
import 'package:rumbo/features/favorites/presentation/favorites_screen.dart';
import 'package:rumbo/features/map/presentation/map_action_provider.dart';
import 'package:rumbo/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('FavoritesController', () {
    test(
      'adds, removes and restores favorites in the fake repository',
      () async {
        final repository = FakeFavoritesRepository();
        final container = _container(repository);
        await container.read(favoritesControllerProvider.future);
        final controller = container.read(favoritesControllerProvider.notifier);

        await controller.setPlace(
          slot: FavoritePlaceSlot.home,
          name: 'Mi casa',
          latitude: -34.9,
          longitude: -56.1,
        );
        const stop = Favorite(
          id: 'stop-1',
          type: FavoriteType.stop,
          name: 'Plaza',
        );
        await controller.add(stop);
        final line = const Favorite(
          id: 'r1',
          type: FavoriteType.line,
          name: 'A',
        );
        await controller.add(line);

        expect(
          container
              .read(favoritesControllerProvider)
              .requireValue
              .map((f) => f.key),
          ['place:place-home', 'stop:stop-1', 'line:r1'],
        );
        expect(await repository.load(), hasLength(3));

        await controller.remove(stop);
        expect(await repository.load(), hasLength(2));
        expect(
          await repository.load(),
          isNot(
            contains(
              const Favorite(
                id: 'stop-1',
                type: FavoriteType.stop,
                name: 'Plaza',
              ),
            ),
          ),
        );

        await controller.restore(stop, 1);
        final restored = await repository.load();
        expect(restored.map((f) => f.key), [
          'place:place-home',
          'stop:stop-1',
          'line:r1',
        ]);

        await controller.rename(stop, '  Plaza Vieja  ');
        final renamed = await repository.load();
        expect(
          renamed.firstWhere((f) => f.key == 'stop:stop-1').name,
          'Plaza Vieja',
        );
      },
    );

    test(
      'keeps saved favorites when a new controller opens the same repository',
      () async {
        final repository = FakeFavoritesRepository();
        final first = _container(repository);
        await first.read(favoritesControllerProvider.future);
        await first
            .read(favoritesControllerProvider.notifier)
            .add(
              const Favorite(
                id: 'stop-1',
                type: FavoriteType.stop,
                name: 'Plaza',
              ),
            );

        final second = _container(repository);
        final reopened = await second.read(favoritesControllerProvider.future);

        expect(reopened, hasLength(1));
        expect(reopened.single.name, 'Plaza');
      },
    );
  });

  group('SharedPreferencesFavoritesRepository', () {
    test('persists favorites across repository instances', () async {
      final first = SharedPreferencesFavoritesRepository();
      await first.save([
        Favorite.place(
          slot: FavoritePlaceSlot.home,
          name: 'Mi casa',
          latitude: -34.9,
          longitude: -56.1,
        ),
        const Favorite(id: 'stop-1', type: FavoriteType.stop, name: 'Plaza'),
      ]);

      final reopened = await SharedPreferencesFavoritesRepository().load();

      expect(reopened, hasLength(2));
      expect(reopened.first.placeSlot, FavoritePlaceSlot.home);
      expect(reopened.last.name, 'Plaza');
    });

    test('skips damaged entries without losing the rest', () async {
      SharedPreferences.setMockInitialValues({
        'favorites_v1': jsonEncode([
          {'type': 'stop', 'id': 'stop-1', 'name': 'Plaza'},
          {'type': 'place', 'id': 'place-home', 'name': 'Casa'},
          {'type': 'line', 'id': 'r1', 'name': 'A'},
          {'type': 'unknown', 'id': 'x1', 'name': 'Desconocido'},
          {
            'type': 'stop',
            'id': 'stop-2',
            'name': 'Coordenadas',
            'latitude': 'x',
          },
          'elemento inválido',
        ]),
      });

      final loaded = await SharedPreferencesFavoritesRepository().load();

      expect(loaded.map((f) => f.key), ['stop:stop-1', 'line:r1']);
    });

    test('returns an empty list when the stored JSON is malformed', () async {
      SharedPreferences.setMockInitialValues({'favorites_v1': '{no es json'});

      expect(await SharedPreferencesFavoritesRepository().load(), isEmpty);
    });
  });

  group('FavoritesScreen', () {
    testWidgets('shows Casa, Trabajo and the empty sections', (tester) async {
      final container = _container(FakeFavoritesRepository());
      await tester.pumpWidget(_favoritesApp(container));
      await tester.pumpAndSettle();

      expect(find.text('Todavía no guardaste favoritos'), findsOneWidget);
      expect(find.text('Lugares'), findsOneWidget);
      expect(find.text('Casa'), findsOneWidget);
      expect(find.text('Trabajo'), findsOneWidget);
      expect(find.text('Todavía sin definir'), findsNWidgets(2));
      expect(find.text('Definir'), findsNWidgets(2));
      expect(find.text('Paradas'), findsOneWidget);
      expect(find.text('Líneas'), findsOneWidget);
      expect(
        find.textContaining('Todavía no guardaste paradas'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Todavía no guardaste líneas'),
        findsOneWidget,
      );
      expect(find.textContaining('Deslizá para eliminar'), findsOneWidget);
    });

    testWidgets('opens the place search when defining Casa', (tester) async {
      final container = _container(FakeFavoritesRepository());
      await tester.pumpWidget(_favoritesApp(container));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('favorite-define-home')));
      await tester.pumpAndSettle();

      expect(
        find.text('Buscá una calle, esquina, parada o lugar…'),
        findsOneWidget,
      );
    });

    testWidgets('deletes a favorite and restores it with Deshacer', (
      tester,
    ) async {
      final repository = FakeFavoritesRepository([
        const Favorite(id: 'stop-1', type: FavoriteType.stop, name: 'Plaza'),
      ]);
      final container = _container(repository);
      await tester.pumpWidget(_favoritesApp(container));
      await tester.pumpAndSettle();
      expect(find.text('Plaza'), findsOneWidget);

      await tester.drag(
        find.byKey(const ValueKey('favorite-stop:stop-1')),
        const Offset(-600, 0),
      );
      await tester.pumpAndSettle();

      expect(find.text('Plaza'), findsNothing);
      expect(find.text('Se eliminó «Plaza»'), findsOneWidget);
      expect(await repository.load(), isEmpty);

      await tester.tap(find.text('Deshacer'));
      await tester.pumpAndSettle();

      expect(find.text('Plaza'), findsOneWidget);
      final restored = await repository.load();
      expect(restored.single.key, 'stop:stop-1');
    });

    testWidgets('renames a favorite with a long press', (tester) async {
      final repository = FakeFavoritesRepository([
        const Favorite(id: 'stop-1', type: FavoriteType.stop, name: 'Plaza'),
      ]);
      final container = _container(repository);
      await tester.pumpWidget(_favoritesApp(container));
      await tester.pumpAndSettle();

      await tester.longPress(
        find.byKey(const ValueKey('favorite-stop-stop-1')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Renombrar favorito'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Plaza Nueva');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(find.text('Plaza Nueva'), findsOneWidget);
      expect((await repository.load()).single.name, 'Plaza Nueva');
    });

    testWidgets('opens Casa in the trip planner', (tester) async {
      final container = _container(
        FakeFavoritesRepository([
          Favorite.place(
            slot: FavoritePlaceSlot.home,
            name: 'Mi casa',
            latitude: -34.9,
            longitude: -56.1,
          ),
        ]),
      );
      await tester.pumpWidget(_favoritesApp(container));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('favorite-place-home')));
      await tester.pumpAndSettle();

      expect(find.text('Mapa'), findsOneWidget);
      final action = container.read(mapActionProvider);
      expect(action, isA<PlanTripToPlace>());
      expect((action as PlanTripToPlace).destination.name, 'Mi casa');
      expect(action.destination.latitude, -34.9);
      expect(action.destination.longitude, -56.1);
    });

    testWidgets('opens a saved line on the map', (tester) async {
      final container = _container(
        FakeFavoritesRepository([
          const Favorite(id: 'r1', type: FavoriteType.line, name: 'A'),
        ]),
      );
      await tester.pumpWidget(_favoritesApp(container));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('favorite-line-r1')));
      await tester.pumpAndSettle();

      expect(find.text('Mapa'), findsOneWidget);
      final action = container.read(mapActionProvider);
      expect(action, isA<ShowRouteOnMap>());
      expect((action as ShowRouteOnMap).route.id, 'r1');
      expect(action.route.shortName, 'A');
    });

    testWidgets('shows an error state when favorites cannot be loaded', (
      tester,
    ) async {
      final container = _container(_FailingFavoritesRepository());
      await tester.pumpWidget(_favoritesApp(container));
      await tester.pumpAndSettle();

      expect(find.text('No se pudieron cargar tus favoritos'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
    });
  });
}

ProviderContainer _container(FavoritesRepository repository) {
  final container = ProviderContainer(
    overrides: [favoritesRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  return container;
}

Widget _favoritesApp(ProviderContainer container) {
  final router = GoRouter(
    initialLocation: '/favorites',
    routes: [
      GoRoute(
        path: '/favorites',
        builder: (context, state) => const FavoritesScreen(),
      ),
      GoRoute(
        path: '/map',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('Mapa'))),
      ),
    ],
  );
  addTearDown(router.dispose);
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      locale: const Locale('es', 'UY'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.light(),
      routerConfig: router,
    ),
  );
}

class _FailingFavoritesRepository implements FavoritesRepository {
  @override
  Future<List<Favorite>> load() async => throw StateError('sin almacenamiento');

  @override
  Future<void> save(List<Favorite> favorites) async {}
}
