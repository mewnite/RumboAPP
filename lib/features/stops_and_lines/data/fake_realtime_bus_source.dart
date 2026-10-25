import '../domain/transit_models.dart';
import '../domain/transit_repository.dart';

class FakeRealtimeBusSource implements RealtimeBusSource {
  const FakeRealtimeBusSource(this.snapshot);
  final RealtimeSnapshot snapshot;

  @override
  Future<RealtimeSnapshot> fetch() async => snapshot;
}
