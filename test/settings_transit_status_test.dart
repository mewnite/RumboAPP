import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rumbo/features/stops_and_lines/domain/transit_models.dart';
import 'package:rumbo/features/stops_and_lines/presentation/feed_update_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

void main() {
  testWidgets('settings shows counts loaded from the cached feed metadata', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      buildRumboTestApp(
        wrapApp: (child) => ProviderScope(
          overrides: [
            feedUpdateControllerProvider.overrideWith(
              _CachedFeedUpdateController.new,
            ),
          ],
          child: child,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('navigation-settings')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Fuente: Datos GTFS guardados'), findsOneWidget);
    expect(find.text('18 paradas · 3 líneas'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('remote address search is disabled by default and persists', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(buildRumboTestApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('navigation-settings')));
    await tester.pumpAndSettle();

    final toggle = find.byKey(const ValueKey('remote-place-search-setting'));
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('remote_place_search_enabled'), isTrue);
  });
}

class _CachedFeedUpdateController extends FeedUpdateController {
  @override
  Future<FeedUpdateState> build() async => FeedUpdateState(
    phase: FeedUpdatePhase.updated,
    status: FeedStatus(
      source: 'Datos GTFS guardados',
      version: 'demo-1',
      downloadedAt: DateTime(2026, 1, 1),
      stopCount: 18,
      routeCount: 3,
    ),
  );
}
