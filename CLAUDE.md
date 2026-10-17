# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**Read `AGENTS.md` first.** It is the binding work protocol: iteration loop, CI-budget rules, things you must not do on your own, data-truthfulness red lines, and the pinned dependency versions. This file adds commands and architecture context and does not repeat that protocol.

TrailWeather (徒步天气) is a Flutter app for Android, iOS and Web. Users find hiking routes on a map, see the weather along the route by departure time, and compare several weather sources. The UI is in Chinese by default. Top product principle: **data truthfulness** (see the red lines in AGENTS.md, plus `docs/data-sources.md` and `docs/acceptance.md`).

## Commands

Local SDK is at `~/flutter-sdk` (Flutter 3.47.7 / Dart 3.13.5, China mirror). There is no emulator, so use it only for analyze/test:

```bash
export PATH="$HOME/flutter-sdk/bin:$PATH"
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn

flutter pub get
flutter analyze                                   # info-level lints also fail CI; keep this at zero issues
flutter test                                      # all tests; fixture-based, no network
flutter test test/weather                         # weather-source contract tests
flutter test test/unit/kml_import_test.dart       # single file
flutter test test/unit/geo_test.dart --plain-name "Geo.distanceM"   # single group/test by name
flutter run -d chrome                             # run Web locally
```

- Run analyze and test locally until both are clean before you push. CI runs cost budget.
- Network access (pub, gh, git push) needs the proxy exports listed in AGENTS.md.
- Platform dirs: only `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist` and `web/` are committed. Before any local build, run `flutter create --platforms=android,web --org dev.trailweather --project-name trailweather .` (it does not overwrite the committed custom files), then `python3 tool/apply_branding.py --platforms android web` and `python3 tool/configure_release.py --platform android`. The release app ID is `app.shanqing.hiking`, while the Kotlin package and namespace stay `dev.trailweather.trailweather`. Analyze/test do not need this step.
- Local Android device (since 2026-10-17): SDK at `/opt/homebrew/share/android-commandlinetools` (platform 36, build-tools 36.0.0, NDK 28.2.13676358, CMake 3.22.1; JDK 17 at `/Library/Java/JavaVirtualMachines/temurin-17.jdk`). The user's Xiaomi 12S (HyperOS 3, Android 15) is connected over USB with USB debugging, USB install and input injection enabled; adb is `$ANDROID_HOME/platform-tools/adb`. Build with `flutter build apk --profile --target-platform android-arm64` (debug and profile builds get the `.dev` application-id suffix, so they install next to the signed release) and export `JAVA_HOME`, `ANDROID_HOME` and `JAVA_TOOL_OPTIONS='-Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=7897 -Dhttp.proxyHost=127.0.0.1 -Dhttp.proxyPort=7897 -Dhttp.nonProxyHosts=mirrors.cloud.tencent.com|*.flutter-io.cn|localhost|127.0.0.1'` for Maven downloads. The local generated `android/gradle/wrapper/gradle-wrapper.properties` points at the Tencent mirror with Gradle's official SHA-256. `flutter create` also bumps transitive versions in `pubspec.lock`: run `git checkout pubspec.lock && flutter pub get --enforce-lockfile` afterwards. Prefer a local device build over a CI run when it can verify the change. To check animations, capture raw frames on the device (`screencap /data/local/tmp/fN.raw` in an `adb shell` loop) and pull them, because there is no ffmpeg.
- Android release signing: CI signs with the `ANDROID_*` GitHub Secrets when they are set (the user creates them with `tool/create_android_keystore.sh`), and falls back to debug signing otherwise. Never generate, read or upload the keystore or its passwords yourself.
- Lints: `flutter_lints` plus `strict-casts`, `prefer_single_quotes` and `unawaited_futures`.

## CI (`.github/workflows/`)

- `ci.yml` runs on push to `main`, on `pull_request` and on manual dispatch. It skips changes that only touch `**.md`, `docs/**` or `agent/**`. Steps: flutter create → analyze → test → web release → APK release → upload artifacts. `cancel-in-progress` is on per ref. **A push to a feature branch only triggers CI if a PR is open** (or via `gh workflow run`).
- `ios-build.yml` (iOS build) and `live-smoke.yml` (real-network smoke test that spends external API quota) only run when triggered manually.
- To check runs: `gh run list --limit 3`, `gh run watch`, `gh run view <id> --log-failed`.

## Architecture

```
lib/core/        geo (haversine, RDP simplify), units, gcj02, WxHttp (dio + 429/5xx backoff), CacheStore (TTL/LRU/namespaces over shared_preferences)
lib/data/        business layer; app_providers.dart is the Riverpod wiring hub
  weather/       WeatherProvider adapters → WeatherRepository → ETA / risk rules
  routes/        HikingRoute model, RouteFileImport (GPX/KML/KMZ/GeoJSON), incoming files, Overpass discovery, planet trails, exporter
  settings/      AppSettings + favorites (Notifier + shared_preferences)
  monetization/  subscription models/repository (paywall, pro benefits)
lib/ui/          screens (trips home, map, route detail, settings, import, planet, planner, onboarding, paywall); router.dart (shell); strings.dart
```

- **Riverpod wiring:** `lib/data/app_providers.dart` defines the service/provider graph. `prefsProvider` must be overridden with a real `SharedPreferences` instance (`main.dart` does this; tests override it the same way). Override these providers in tests instead of hitting the network.
- **Weather pipeline:** `WeatherProvider.fetchPoints(points, startUtc, endUtc)` is the adapter interface (Open-Meteo `best_match` and `ecmwf_ifs025`, MET Norway, QWeather). `defaultWeatherProviders()` is the registry, and its order sets the default primary source. `WeatherRepository` samples route nodes, merges nearby nodes into approximate grid cells (0.1°) within a single query, applies the cache, fetches, and attaches provenance. The cache key uses request coordinates, never the merged grid. Metered sources (`caps.onDemandOnly`, currently meteoblue at 8000 credits per call) are never fetched automatically: route weather and the home location chip use `primaryProviderId()`, and node-compare / point-weather cards show an `OnDemandQueryPrompt`. Sources with `caps.usesElevation` get node elevations via `fetchPointsAt`, and the cache key then includes elevation. Stale data is readable for up to 6h, labelled as stale, and refreshed in the background.
- **Provenance model:** every `WxSourceResult` carries a `WxProvenance` (`weather_models.dart`). It keeps request coordinates, returned coordinates, granularity, resolution, data kind, model run and license as separate fields. All variable values are `double?`. `WxVar.windGust`/`windSpeed` and `precipProb`/`precip` are distinct keys. Internal units are °C, m/s, mm and m; each adapter converts from its source units. All times are UTC internally.
- **Out-of-range requests** throw `WxOutOfRange`, and the UI shows "no data for this date" instead of extrapolating.
- **Map:** flutter_map 8 (pure Dart, same on all three platforms). The business layer only emits `HikingRoute`/`RouteNode`/`WxSourceResult`; `ui/map` only renders and handles hit-testing. The default basemap is AMap (GCJ-02, hence `core/gcj02.dart`), with OSM available in Settings.
- **Routing:** go_router in `ui/router.dart`. A `StatefulShellRoute` gives three bottom-nav branches: Trips (`/`, home), Map (`/map`), Settings (`/settings`). Detail, import, planner and similar pages are top-level routes pushed above the shell. `/route/:routeId` receives the route through `state.extra` (`RouteDetailArgs`) and redirects to `/` without it. The router is created once in `appRouterProvider` (`app.dart`); never build it inside `build`.
- **Product direction:** `docs/redesign-v2.md` (track-first "weather window" app; map discovery is secondary).
- **Incoming files ("Open with"):** Android `MainActivity.kt` (committed, `flutter create` leaves it alone) passes VIEW/SEND URIs over the `trailweather/incoming_file` MethodChannel; `IncomingFileListener` parses them with `RouteFileImport` and reuses `confirmAndSaveImportedRoute`. iOS is not wired yet.
- **Request discipline:** no weather requests while the map is being dragged. The time slider only previews loaded data and fetches on `onChangeEnd`. Overpass rotates mirrors because the main instance often returns 504.
- **Strings:** all user-visible text goes through `S` constants in `lib/ui/strings.dart`. Do not inline UI text in business code.
- **Tests:** source contract tests use fixtures copied from real API responses (`test/weather/`). The other suites are `test/unit`, `test/widget` and `test/integration/core_flow_test.dart`.

## Project state files

`agent/tasks.json` (task status, priority P0–P3), `agent/progress.md` (one section per round), `agent/blockers.md`, `agent/decisions.md` (record dependency or approach changes here). Update these after a verified iteration, as AGENTS.md describes. Product and architecture rationale lives in `docs/` (`architecture.md`, `data-sources.md`, `acceptance.md`).
