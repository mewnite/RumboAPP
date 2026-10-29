import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rumbo/core/theme/app_theme.dart';
import 'package:rumbo/core/widgets/empty_state.dart';
import 'package:rumbo/core/widgets/line_chip.dart';
import 'package:rumbo/core/widgets/rumbo_components.dart';

void main() {
  Future<void> pumpComponent(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );
  }

  testWidgets('floating search bar is labeled and opens on tap', (
    tester,
  ) async {
    var tapped = false;
    await pumpComponent(
      tester,
      FloatingSearchBar(label: '¿A dónde vamos?', onTap: () => tapped = true),
    );

    expect(find.bySemanticsLabel('¿A dónde vamos?'), findsOneWidget);
    await tester.tap(find.byType(FloatingSearchBar));
    expect(tapped, isTrue);
  });

  testWidgets('arrival row announces route, destination, and arrival', (
    tester,
  ) async {
    await pumpComponent(
      tester,
      const ArrivalRow(
        lineLabel: '105',
        lineColor: Colors.blue,
        destination: 'Ciudad Vieja',
        arrivalLabel: '4 min',
      ),
    );

    expect(find.bySemanticsLabel('105, Ciudad Vieja, 4 min'), findsOneWidget);
  });

  testWidgets('itinerary summary exposes its whole summary', (tester) async {
    await pumpComponent(
      tester,
      ItinerarySummaryCard(
        lines: const [LineChip(label: '105', backgroundColor: Colors.blue)],
        durationLabel: '24 min',
        walkingLabel: '6 min a pie',
        transfersLabel: '1 transbordo',
        onTap: () {},
      ),
    );

    expect(
      find.bySemanticsLabel('24 min. 6 min a pie. 1 transbordo'),
      findsOneWidget,
    );
  });

  testWidgets('sheet handle has an accessible description', (tester) async {
    await pumpComponent(
      tester,
      const RumboSheetHandle(label: 'Arrastrar para ampliar'),
    );

    expect(find.bySemanticsLabel('Arrastrar para ampliar'), findsOneWidget);
  });

  testWidgets('primary and secondary actions keep 48 dp touch targets', (
    tester,
  ) async {
    await pumpComponent(
      tester,
      const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PrimaryActionButton(label: 'Iniciar viaje', onPressed: null),
          SecondaryActionButton(label: 'Cancelar', onPressed: null),
        ],
      ),
    );

    expect(tester.getSize(find.byType(PrimaryActionButton)).height, 52);
    expect(tester.getSize(find.byType(SecondaryActionButton)).height, 48);
    expect(find.bySemanticsLabel('Iniciar viaje'), findsOneWidget);
    expect(find.bySemanticsLabel('Cancelar'), findsOneWidget);
  });

  testWidgets('stop and bus markers provide useful semantic labels', (
    tester,
  ) async {
    await pumpComponent(
      tester,
      const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StopMapMarker(label: 'Pocitos', selected: true),
          BusMapMarker(label: 'Ómnibus 105 hacia Ciudad Vieja'),
        ],
      ),
    );

    expect(
      find.bySemanticsLabel('Parada Pocitos, seleccionada'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Ómnibus 105 hacia Ciudad Vieja'),
      findsOneWidget,
    );
  });

  testWidgets('trip progress is announced with its current step', (
    tester,
  ) async {
    await pumpComponent(
      tester,
      const TripProgressCard(
        title: 'En camino',
        subtitle: 'Bajá en la próxima parada',
        progress: .5,
      ),
    );

    expect(
      find.bySemanticsLabel('En camino. Bajá en la próxima parada'),
      findsOneWidget,
    );
  });

  testWidgets('common empty state includes its action', (tester) async {
    await pumpComponent(
      tester,
      EmptyState(
        icon: const Icon(Icons.route),
        title: 'No hay resultados',
        message: 'Probá con otro destino.',
        footer: FilledButton(onPressed: () {}, child: const Text('Reintentar')),
      ),
    );

    expect(find.text('No hay resultados'), findsOneWidget);
    expect(find.text('Probá con otro destino.'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });

  testWidgets('shared components fit at 130% text scale', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  const TripEndpointRail(height: 132),
                  FloatingSearchBar(label: '¿A dónde vamos?', onTap: () {}),
                  const ArrivalRow(
                    lineLabel: '105',
                    lineColor: Colors.blue,
                    destination: 'Ciudad Vieja',
                    arrivalLabel: '4 min',
                  ),
                  ItinerarySummaryCard(
                    lines: const [
                      LineChip(label: '105', backgroundColor: Colors.blue),
                      LineChip(label: 'D', backgroundColor: Colors.blue),
                    ],
                    durationLabel: '24 min',
                    walkingLabel: '6 min a pie',
                    transfersLabel: '1 transbordo',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
