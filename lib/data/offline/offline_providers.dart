import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_providers.dart';
import '../settings/settings_repository.dart';
import 'offline_repository.dart';
import 'offline_store.dart';
import 'offline_trip.dart';

final offlineStoreProvider = Provider<OfflineTripStore>(
  (ref) => createOfflineTripStore(ref.watch(prefsProvider)),
);
final offlineRepositoryProvider = Provider<OfflineTripRepository>(
  (ref) => OfflineTripRepository(
    store: ref.watch(offlineStoreProvider),
    weather: () => ref.read(weatherRepositoryProvider),
    now: ref.watch(weatherNowProvider),
  ),
);
final offlineEntriesProvider = FutureProvider<List<OfflineEntry>>(
  (ref) => ref.watch(offlineRepositoryProvider).list(),
);
final offlineTripProvider = FutureProvider.autoDispose
    .family<OfflineTrip?, String>(
      (ref, id) => ref.watch(offlineRepositoryProvider).load(id),
    );
