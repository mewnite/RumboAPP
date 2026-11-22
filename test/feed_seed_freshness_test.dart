import 'package:flutter_test/flutter_test.dart';

import '../tool/feed_seed_freshness.dart';

void main() {
  test('release seed accepts exactly seven days of remaining validity', () {
    final today = DateTime(2026, 12, 10, 23, 59);

    expect(
      hasSevenDaysOfFeedValidityLeft(DateTime(2026, 12, 17), today: today),
      isTrue,
    );
    expect(
      hasSevenDaysOfFeedValidityLeft(
        DateTime(2026, 12, 16, 23, 59),
        today: today,
      ),
      isFalse,
    );
  });
}
