import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/in_memory_transit_repository.dart';
import '../data/sqflite_transit_repository.dart';
import '../data/transit_database.dart';
import '../domain/transit_repository.dart';
import 'feed_update_controller.dart';

final transitRepositoryProvider = Provider<TransitRepository>((ref) {
  if (!kIsWeb) {
    return SqfliteTransitRepository(() => TransitDatabase().open());
  }
  final feedState = ref.watch(feedUpdateControllerProvider).asData?.value;
  return InMemoryTransitRepository(feedState?.feed, status: feedState?.status);
});
