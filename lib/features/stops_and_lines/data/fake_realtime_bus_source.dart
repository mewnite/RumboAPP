import '../domain/transit_models.dart';
import '../domain/transit_repository.dart';

class FakeRealtimeBusSource implements RealtimeBusSource {
  const FakeRealtimeBusSource(this.snapshot);
  final RealtimeSnapshot snapshot;

  @override
  Future<RealtimeSnapshot> fetch({Set<String>? lines}) async {
    if (lines == null || lines.isEmpty) return snapshot;
    final filtered = snapshot.positions
        .where((bus) => lines.contains(bus.lineLabel))
        .toList(growable: false);
    return RealtimeSnapshot(
      positions: filtered,
      discardedCount: snapshot.discardedCount,
      discardReasons: snapshot.discardReasons,
      duplicateCount: snapshot.duplicateCount,
    );
  }
}
