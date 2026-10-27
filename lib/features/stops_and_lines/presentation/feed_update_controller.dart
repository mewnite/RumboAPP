import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/transit_config.dart';
import '../data/gtfs_parser.dart';
import '../data/sqflite_transit_repository.dart';
import '../data/transit_database.dart';
import '../data/transit_feed_source.dart';
import '../domain/transit_models.dart';

enum FeedUpdatePhase {
  noData,
  downloading,
  processing,
  updated,
  errorWithOldData,
  offline,
}

FeedUpdatePhase phaseForFeedError(Object error) =>
    error is TransitFeedNetworkException || error is StateError
    ? FeedUpdatePhase.offline
    : FeedUpdatePhase.errorWithOldData;

bool isTransitUpdateDue({
  required FeedStatus currentStatus,
  required int? lastCheckMilliseconds,
  required DateTime now,
  required Duration minimumInterval,
}) {
  if (currentStatus.synthetic || currentStatus.stopCount == 0) return true;
  if (lastCheckMilliseconds == null) return true;
  return now.difference(
        DateTime.fromMillisecondsSinceEpoch(lastCheckMilliseconds),
      ) >=
      minimumInterval;
}

class FeedUpdateState {
  const FeedUpdateState({
    required this.phase,
    this.progress = 0,
    this.stage = '',
    this.status = const FeedStatus(),
    this.message = '',
    this.feed,
  });
  final FeedUpdatePhase phase;
  final double progress;
  final String stage, message;
  final FeedStatus status;
  final GtfsParseResult? feed;
}

final feedUpdateControllerProvider =
    AsyncNotifierProvider<FeedUpdateController, FeedUpdateState>(
      FeedUpdateController.new,
    );

class FeedUpdateController extends AsyncNotifier<FeedUpdateState> {
  FeedUpdateState? _lastGood;
  @override
  Future<FeedUpdateState> build() => _loadData();

  Future<FeedUpdateState> _loadData() async {
    state = const AsyncData(
      FeedUpdateState(phase: FeedUpdatePhase.downloading, stage: 'conectando'),
    );
    try {
      if (!transitConfig.demoMode && !kIsWeb) {
        final database = TransitDatabase();
        final cachedDatabase = await database.open();
        final cachedStatus = await SqfliteTransitRepository(
          () async => cachedDatabase,
        ).feedStatus();
        await cachedDatabase.close();
        if (!cachedStatus.synthetic &&
            (cachedStatus.stopCount > 0 || cachedStatus.routeCount > 0)) {
          final cached = FeedUpdateState(
            phase: FeedUpdatePhase.updated,
            progress: 1,
            stage: 'actualizado',
            status: cachedStatus,
          );
          state = AsyncData(cached);
          _lastGood = cached;
          await _checkForUpdate(cached);
          return cached;
        }
      }
      if (transitConfig.demoMode) {
        return await _loadBundledDemo();
      }
      if (transitConfig.url.isEmpty) {
        const unavailable = FeedUpdateState(
          phase: FeedUpdatePhase.offline,
          message: 'No hay una fuente GTFS oficial configurada.',
        );
        state = const AsyncData(unavailable);
        return unavailable;
      }
      const empty = FeedUpdateState(
        phase: FeedUpdatePhase.noData,
        status: FeedStatus(),
      );
      await _refresh(empty);
      return state.asData?.value ?? empty;
    } catch (e, stackTrace) {
      final stale = _lastGood;
      final result = FeedUpdateState(
        phase: stale?.feed == null
            ? FeedUpdatePhase.noData
            : FeedUpdatePhase.errorWithOldData,
        message: e.toString(),
        feed: stale?.feed,
        status: stale?.status ?? const FeedStatus(),
      );
      state = AsyncData(result);
      Error.throwWithStackTrace(e, stackTrace);
    }
  }

  Future<FeedUpdateState> _loadBundledDemo() async {
    state = const AsyncData(
      FeedUpdateState(
        phase: FeedUpdatePhase.processing,
        stage: 'procesando_demo',
        progress: .1,
      ),
    );
    try {
      final data = await rootBundle.load('assets/sample_gtfs/sample_gtfs.zip');
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final source = GtfsZipSource(transitConfig.url);
      final parsed = kIsWeb
          ? await source.parseCompact(bytes)
          : await source.parse(bytes, streamStopTimes: true);
      if (!kIsWeb) {
        await TransitDatabase().replaceFeed(
          parsed,
          sourceName: 'Datos sintéticos de prueba',
        );
      }
      final result = FeedUpdateState(
        phase: FeedUpdatePhase.updated,
        progress: 1,
        stage: 'actualizado',
        feed: parsed,
        status: FeedStatus(
          source: 'Datos sintéticos de prueba',
          version: parsed.feedInfo.version,
          downloadedAt: DateTime.now(),
          validUntil: parsed.feedInfo.endDate,
          stopCount: parsed.stops.length,
          routeCount: parsed.routes.length,
          variantCount: parsed.variants.length,
          tripCount: parsed.trips.length,
          stopTimeCount: parsed.stopTimeCount,
          shapePointCount: parsed.shapes.fold<int>(
            0,
            (count, shape) => count + shape.points.length,
          ),
          calendarCount: parsed.calendars.length,
          warningCount: parsed.warningCount,
          stale: isFeedExpired(parsed.feedInfo.endDate, DateTime.now()),
          synthetic: parsed.feedInfo.synthetic,
        ),
      );
      state = AsyncData(result);
      _lastGood = result;
      return result;
    } catch (e, stackTrace) {
      final stale = _lastGood;
      final result = FeedUpdateState(
        phase: stale?.feed == null
            ? FeedUpdatePhase.noData
            : FeedUpdatePhase.errorWithOldData,
        message: e.toString(),
        feed: stale?.feed,
        status: stale?.status ?? const FeedStatus(),
      );
      state = AsyncData(result);
      Error.throwWithStackTrace(e, stackTrace);
    }
  }

  Future<void> _checkForUpdate(FeedUpdateState current) async {
    if (transitConfig.url.isEmpty) return;
    final preferences = await SharedPreferences.getInstance();
    final lastCheck = preferences.getInt('transit_last_check_ms');
    final due = isTransitUpdateDue(
      currentStatus: current.status,
      lastCheckMilliseconds: lastCheck,
      now: DateTime.now(),
      minimumInterval: transitConfig.minimumCheckInterval,
    );
    if (due) unawaited(_refresh(current));
  }

  Future<void> updateNow() async {
    final previous = _lastGood;
    state = AsyncData(
      FeedUpdateState(
        phase: FeedUpdatePhase.downloading,
        feed: previous?.feed,
        status: previous?.status ?? const FeedStatus(),
      ),
    );
    if (transitConfig.url.isNotEmpty) {
      await _refresh(
        previous ??
            const FeedUpdateState(
              phase: FeedUpdatePhase.noData,
              status: FeedStatus(),
            ),
      );
      return;
    }
    // The official URL intentionally remains unset. Do not attempt invented endpoints.
    state = AsyncData(
      FeedUpdateState(
        phase: FeedUpdatePhase.offline,
        feed: previous?.feed,
        status: previous?.status ?? const FeedStatus(),
      ),
    );
  }

  Future<void> _refresh(FeedUpdateState previous) async {
    final preferences = await SharedPreferences.getInstance();
    state = AsyncData(
      FeedUpdateState(
        phase: FeedUpdatePhase.downloading,
        feed: previous.feed,
        status: previous.status,
      ),
    );
    try {
      final source = GtfsZipSource(transitConfig.url);
      final downloaded = await source.download(
        etag: preferences.getString('transit_etag'),
        lastModified: preferences.getString('transit_last_modified'),
        writeToFile: !kIsWeb,
      );
      final checkedAt = DateTime.now();
      if (downloaded.notModified) {
        final unchanged = FeedUpdateState(
          phase: FeedUpdatePhase.updated,
          feed: previous.feed,
          status: FeedStatus(
            source: transitConfig.sourceName,
            version: previous.status.version,
            downloadedAt: previous.status.downloadedAt,
            validUntil: previous.status.validUntil,
            etag: downloaded.etag,
            stopCount: previous.status.stopCount,
            routeCount: previous.status.routeCount,
            variantCount: previous.status.variantCount,
            tripCount: previous.status.tripCount,
            stopTimeCount: previous.status.stopTimeCount,
            shapePointCount: previous.status.shapePointCount,
            calendarCount: previous.status.calendarCount,
            warningCount: previous.status.warningCount,
            stale: isFeedExpired(previous.status.validUntil, checkedAt),
            synthetic: previous.status.synthetic,
          ),
        );
        await preferences.setInt(
          'transit_last_check_ms',
          checkedAt.millisecondsSinceEpoch,
        );
        state = AsyncData(unchanged);
        _lastGood = unchanged;
        return;
      }
      state = AsyncData(
        FeedUpdateState(
          phase: FeedUpdatePhase.processing,
          stage: 'validando_zip',
          progress: .05,
          feed: previous.feed,
          status: previous.status,
        ),
      );
      void reportProgress(String stage, double progress) {
        state = AsyncData(
          FeedUpdateState(
            phase: FeedUpdatePhase.processing,
            stage: stage,
            progress: progress,
            feed: previous.feed,
            status: previous.status,
          ),
        );
      }

      final parsed = downloaded.filePath == null
          ? kIsWeb
                ? await source.parseCompact(downloaded.bytes)
                : await source.parse(
                    downloaded.bytes,
                    streamStopTimes: true,
                    onProgress: reportProgress,
                  )
          : await source.parseFile(
              downloaded.filePath!,
              onProgress: reportProgress,
            );
      if (!kIsWeb) {
        await TransitDatabase().replaceFeed(
          parsed,
          sourceName: transitConfig.sourceName,
          etag: downloaded.etag,
          downloadedAt: checkedAt,
        );
      }
      if (downloaded.etag != null) {
        await preferences.setString('transit_etag', downloaded.etag!);
      }
      if (downloaded.lastModified != null) {
        await preferences.setString(
          'transit_last_modified',
          downloaded.lastModified!,
        );
      }
      await preferences.setInt(
        'transit_last_check_ms',
        checkedAt.millisecondsSinceEpoch,
      );
      final validUntil =
          parsed.feedInfo.endDate ??
          (parsed.calendars.isEmpty
              ? null
              : parsed.calendars
                    .map((c) => c.endDate)
                    .reduce((a, b) => a.isAfter(b) ? a : b));
      final updated = FeedUpdateState(
        phase: FeedUpdatePhase.updated,
        stage: 'actualizado',
        progress: 1,
        feed: parsed,
        status: FeedStatus(
          source: transitConfig.sourceName,
          version: parsed.feedInfo.version,
          downloadedAt: checkedAt,
          validUntil: validUntil,
          etag: downloaded.etag,
          stopCount: parsed.stops.length,
          routeCount: parsed.routes.length,
          variantCount: parsed.variants.length,
          tripCount: parsed.trips.length,
          stopTimeCount: parsed.stopTimeCount,
          shapePointCount: parsed.shapes.fold<int>(
            0,
            (count, shape) => count + shape.points.length,
          ),
          calendarCount: parsed.calendars.length,
          warningCount: parsed.warningCount,
          stale: isFeedExpired(validUntil, checkedAt),
          synthetic: parsed.feedInfo.synthetic,
        ),
      );
      state = AsyncData(updated);
      _lastGood = updated;
    } catch (error) {
      state = AsyncData(
        FeedUpdateState(
          phase: phaseForFeedError(error),
          message: error.toString(),
          feed: previous.feed,
          status: previous.status.copyWithStale(),
        ),
      );
    }
  }
}

extension on FeedStatus {
  FeedStatus copyWithStale() => FeedStatus(
    source: source,
    version: version,
    downloadedAt: downloadedAt,
    validUntil: validUntil,
    etag: etag,
    stopCount: stopCount,
    routeCount: routeCount,
    variantCount: variantCount,
    tripCount: tripCount,
    stopTimeCount: stopTimeCount,
    shapePointCount: shapePointCount,
    calendarCount: calendarCount,
    synthetic: synthetic,
    warningCount: warningCount,
    stale: isFeedExpired(validUntil, DateTime.now()) || stale,
  );
}
