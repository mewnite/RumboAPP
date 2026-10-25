import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

void main() {
  testWidgets('bottom navigation switches between all three destinations', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(buildRumboTestApp());
    await tester.pumpAndSettle();
    expect(find.text('Paradas y ómnibus'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('navigation-favorites')));
    await tester.pumpAndSettle();
    expect(find.text('Todavía no guardaste favoritos'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('navigation-settings')));
    await tester.pumpAndSettle();
    expect(find.text('Personalizá Rumbo a tu gusto.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('navigation-map')));
    await tester.pumpAndSettle();
    expect(find.text('Paradas y ómnibus'), findsOneWidget);
  });
}
