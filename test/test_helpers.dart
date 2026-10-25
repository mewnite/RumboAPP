import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rumbo/app.dart';
import 'package:rumbo/core/theme/app_colors.dart';
import 'package:rumbo/features/map/data/connectivity_provider.dart';
import 'package:rumbo/features/map/presentation/map_location_controller.dart';
import 'package:rumbo/features/map/presentation/map_screen.dart';
import 'package:rumbo/features/stops_and_lines/domain/transit_models.dart';
import 'package:rumbo/features/stops_and_lines/presentation/feed_update_controller.dart';

import 'fakes/fake_location_repository.dart';

Widget buildRumboTestApp({Widget Function(Widget child)? wrapApp}) {
  return ProviderScope(
    overrides: [
      mapBuilderOverrideProvider.overrideWithValue(
        (context) => const ColoredBox(color: AppColors.surfaceGray),
      ),
      networkAvailableProvider.overrideWith((ref) => Stream<bool>.value(true)),
      locationRepositoryProvider.overrideWith(
        (ref) => FakeLocationRepository(),
      ),
      feedUpdateControllerProvider.overrideWith(_OfflineFeedController.new),
    ],
    child: wrapApp?.call(const RumboApp()) ?? const RumboApp(),
  );
}

class _OfflineFeedController extends FeedUpdateController {
  @override
  Future<FeedUpdateState> build() async => const FeedUpdateState(
    phase: FeedUpdatePhase.offline,
    message: 'Prueba sin conexión',
    status: FeedStatus(),
  );
}
