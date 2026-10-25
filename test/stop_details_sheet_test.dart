import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rumbo/core/theme/app_theme.dart';
import 'package:rumbo/features/map/data/connectivity_provider.dart';
import 'package:rumbo/features/stops_and_lines/domain/transit_models.dart';
import 'package:rumbo/features/stops_and_lines/presentation/stop_details_sheet.dart';
import 'package:rumbo/l10n/generated/app_localizations.dart';

void main() {
  const stop = Stop(
    id: 'stop-1',
    code: '123',
    name: 'Plaza',
    latitude: -34.9,
    longitude: -56.1,
  );

  testWidgets(
    'shows live and scheduled arrivals, line, and disabled favorite',
    (tester) async {
      var requestedRoute = false;
      final container = ProviderContainer(
        overrides: [
          stopDetailsProvider(stop.id).overrideWith(
            (ref) async => StopDetailsData(
              routes: const [
                Route(id: 'r1', shortName: 'A', longName: 'Centro'),
              ],
              arrivals: [
                StopArrival(
                  stopId: stop.id,
                  routeId: 'r1',
                  routeLabel: 'A',
                  destination: 'Centro',
                  departureTime: DateTime.now().add(const Duration(minutes: 2)),
                  variantId: 'v1',
                  isLive: true,
                ),
                StopArrival(
                  stopId: stop.id,
                  routeId: 'r1',
                  routeLabel: 'A',
                  destination: 'Centro',
                  departureTime: DateTime.now().add(const Duration(minutes: 8)),
                  variantId: 'v1',
                ),
              ],
            ),
          ),
          networkAvailableProvider.overrideWith(
            (ref) => Stream<bool>.value(true),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        _app(
          container: container,
          child: StopDetailsSheet(
            stop: stop,
            onHowToGetThere: () => requestedRoute = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Plaza'), findsOneWidget);
      expect(find.text('Código: 123'), findsOneWidget);
      expect(find.text('Líneas que pasan'), findsOneWidget);
      expect(find.text('Próximos ómnibus'), findsOneWidget);
      expect(find.textContaining('en vivo, estimado'), findsOneWidget);
      expect(find.textContaining('estimado'), findsNWidgets(2));
      expect(find.text('A'), findsNWidgets(3));

      final favorite = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Favorito · Próximamente'),
      );
      expect(favorite.onPressed, isNull);
      await tester.tap(find.text('Cómo llegar'));
      expect(requestedRoute, isTrue);
    },
  );

  testWidgets('shows offline and no-service states', (tester) async {
    final container = ProviderContainer(
      overrides: [
        stopDetailsProvider(stop.id).overrideWith(
          (ref) async => const StopDetailsData(routes: [], arrivals: []),
        ),
        networkAvailableProvider.overrideWith(
          (ref) => Stream<bool>.value(false),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      _app(
        container: container,
        child: const StopDetailsSheet(stop: stop, onHowToGetThere: _doNothing),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Sin conexión'), findsOneWidget);
    expect(find.text('No hay servicio programado para hoy.'), findsOneWidget);
  });

  testWidgets('shows a recoverable error state', (tester) async {
    final container = ProviderContainer(
      overrides: [
        stopDetailsProvider(
          stop.id,
        ).overrideWith((ref) async => throw StateError('storage unavailable')),
        networkAvailableProvider.overrideWith(
          (ref) => Stream<bool>.value(true),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      _app(
        container: container,
        child: const StopDetailsSheet(stop: stop, onHowToGetThere: _doNothing),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('No se pudo cargar el detalle:'),
      findsOneWidget,
    );
    expect(find.text('Reintentar'), findsOneWidget);
  });
}

Widget _app({required ProviderContainer container, required Widget child}) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('es', 'UY'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light(),
        home: Scaffold(body: child),
      ),
    );

void _doNothing() {}
