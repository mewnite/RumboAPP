import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

void main() {
  testWidgets('opens on the es-UY map data-error state', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(buildRumboTestApp());
    await tester.pumpAndSettle();

    expect(find.text('¿A dónde vamos?'), findsOneWidget);
    expect(find.text('Paradas y ómnibus'), findsOneWidget);
    expect(
      find.textContaining('No se pudieron cargar los datos oficiales:'),
      findsOneWidget,
    );
  });
}
