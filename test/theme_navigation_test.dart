import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

void main() {
  testWidgets('theme selector switches and navigation works in both themes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(buildRumboTestApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('navigation-settings')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Oscuro'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('Ajustes').first)).brightness,
      Brightness.dark,
    );

    await tester.tap(find.byKey(const ValueKey('navigation-favorites')));
    await tester.pumpAndSettle();
    expect(find.text('Todavía no guardaste favoritos'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('navigation-map')));
    await tester.pumpAndSettle();
    expect(find.text('Próximos ómnibus'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('navigation-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Claro'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('Ajustes').first)).brightness,
      Brightness.light,
    );

    await tester.tap(find.byKey(const ValueKey('navigation-map')));
    await tester.pumpAndSettle();
    expect(find.text('Próximos ómnibus'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('navigation-favorites')));
    await tester.pumpAndSettle();
    expect(find.text('Todavía no guardaste favoritos'), findsOneWidget);
  });
}
