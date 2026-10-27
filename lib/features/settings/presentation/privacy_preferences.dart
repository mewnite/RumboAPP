import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final liveBusesEnabledProvider =
    AsyncNotifierProvider<LiveBusesEnabledController, bool>(
      LiveBusesEnabledController.new,
    );

class LiveBusesEnabledController extends AsyncNotifier<bool> {
  static const preferenceKey = 'live_buses_enabled';

  @override
  Future<bool> build() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(preferenceKey) ?? true;
  }

  Future<void> setEnabled(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(preferenceKey, enabled);
    state = AsyncData(enabled);
  }
}
