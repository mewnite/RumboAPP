import 'package:flutter_test/flutter_test.dart';
import 'package:rumbo/features/trip_planner/domain/plan_search_isolate.dart';

void main() {
  test('cancelling an active search invokes its isolate cancellation hook', () {
    final cancellation = PlanSearchCancellation();
    var canceled = 0;
    cancellation.attach(() => canceled++);

    cancellation.cancel();

    expect(cancellation.isCancelled, isTrue);
    expect(canceled, 1);
  });

  test('a search canceled before isolate startup is canceled on attach', () {
    final cancellation = PlanSearchCancellation()..cancel();
    var canceled = 0;

    cancellation.attach(() => canceled++);

    expect(canceled, 1);
  });
}
