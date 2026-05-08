# flutter_geofire

A Flutter plugin for realtime geospatial location updates and proximity queries.

This package supports:
1. Firebase Realtime Database + GeoFire native behavior (default)
2. Optional backend adapters for Firestore, Supabase, Postgres, and MySQL
3. Advanced filtering/ranking helpers for ride-dispatch workflows
4. Typed event/candidate APIs to avoid stringly-typed map usage
5. Optional native location tracking (Android/iOS), including background-oriented modes

## Installation

In pubspec.yaml:

```yaml
dependencies:
  flutter_geofire: ^2.0.7
```

Then run:

```bash
flutter pub get
```

## iOS setup

Your app Podfile should include:

```ruby
target 'Runner' do
  use_frameworks!
  use_modular_headers!
  pod 'GeoFire'

  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
end
```

Notes:
1. Works with Swift and Objective-C host apps.
2. The plugin implementation is Swift with Objective-C bridge compatibility.
3. No custom GeoFire git fork is required.

## Android setup

No extra manual plugin registration is needed.

If you use native location tracking, request runtime location permissions in your app.

## Quickstart (Firebase default backend)

```dart
import 'package:flutter_geofire/flutter_geofire.dart';

Future<void> setup() async {
  final bool ok = await Geofire.initialize('drivers_live');
  if (!ok) {
    throw Exception('GeoFire initialize failed');
  }
}
```

Realtime Database rules must index g for your chosen path:

```json
{
  "rules": {
    ".read": true,
    ".write": true,
    "drivers_live": {
      ".indexOn": ["g"]
    }
  }
}
```

## Copy-Paste Templates

### Which template should I use?

| Scenario | Template | Key API |
|---|---|---|
| Driver app pushes lat/lng on each GPS tick from Dart | **A** | `Geofire.setLocation(...)` |
| Rider/passenger app queries and ranks nearby drivers | **B** | `Geofire.queryDriverCandidatesAtLocation(...)` |
| Driver app must track location in the background without Dart running | **C** | `Geofire.startNativeTrackingDetailed(...)` |
| You want Dart control but only need basic proximity events (no typed model) | **A** | `Geofire.queryAtLocation(...)` |
| You need custom score/rank logic beyond rating + priority | **B** | `Geofire.queryAtLocationAdvanced(...)` with `scoreBy:` |
| Android reliability matters most in background | **C** | set `useForegroundService: true` |
| iOS background with minimal battery use | **C** | set `useSignificantChanges: true` |

> Start with Template A + B for most apps. Add Template C only when Dart-side GPS is not reliable enough in background.

### Template A: Driver app publisher (Dart-driven updates)

```dart
import 'package:flutter_geofire/flutter_geofire.dart';

class DriverPublisher {
  static const String path = 'drivers_live';
  static const String driverId = 'driver_123';

  static Future<void> init() async {
    final bool ok = await Geofire.initialize(path);
    if (!ok) {
      throw Exception('GeoFire init failed');
    }
  }

  static Future<void> publish(double lat, double lng) async {
    await Geofire.setLocation(
      driverId,
      lat,
      lng,
      data: {
        'vehicleType': 'bike',
        'region': 'nairobi',
        'isVerified': true,
        'rating': 4.8,
        'activeTrips': 0,
        'priority': 2,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  static Future<void> remove() async {
    await Geofire.removeLocation(driverId);
  }
}
```

### Template B: Rider app consumer (ranked nearby candidates)

```dart
import 'dart:async';
import 'package:flutter_geofire/flutter_geofire.dart';

class RiderMatching {
  static const String path = 'drivers_live';
  StreamSubscription<List<GeofireDriverCandidate>>? _sub;

  Future<void> init() async {
    final bool ok = await Geofire.initialize(path);
    if (!ok) {
      throw Exception('GeoFire init failed');
    }
  }

  Future<void> start(double riderLat, double riderLng) async {
    await _sub?.cancel();
    _sub = Geofire.queryDriverCandidatesAtLocation(
      riderLat,
      riderLng,
      5,
      vehicleType: 'bike',
      region: 'nairobi',
      isVerified: true,
      minRating: 4.5,
      maxActiveTrips: 1,
      limit: 20,
    ).listen((candidates) {
      if (candidates.isEmpty) {
        return;
      }

      final best = candidates.first;
      print('Best: ${best.key}, score=${best.score}');
    });
  }

  Future<void> stop() async {
    await _sub?.cancel();
    await Geofire.stopListener();
  }
}
```

### Template C: Native tracker mode (platform-driven updates)

```dart
import 'package:flutter_geofire/flutter_geofire.dart';

class NativeTracker {
  static const String path = 'drivers_live';
  static const String driverId = 'driver_123';

  static Future<void> init() async {
    final bool ok = await Geofire.initialize(path);
    if (!ok) {
      throw Exception('GeoFire init failed');
    }
  }

  static Future<void> start() async {
    final GeofireNativeTrackingStartResult result =
        await Geofire.startNativeTrackingDetailed(
      GeofireNativeTrackingConfig(
        id: driverId,
        intervalMs: 10000,
        minDistanceMeters: 20,
        includeLocationMeta: true,
        allowBackground: true,
        useForegroundService: true,
        useSignificantChanges: false,
        foregroundNotificationTitle: 'Driver online',
        foregroundNotificationBody: 'Sharing live location',
        data: {
          'vehicleType': 'bike',
          'region': 'nairobi',
          'isVerified': true,
        },
      ),
    );

    print('started=${result.started}, reason=${result.reason}');
  }

  static Future<void> status() async {
    final Map<String, dynamic> status = await Geofire.nativeTrackingStatus();
    print(status);
  }

  static Future<void> stop() async {
    await Geofire.stopNativeTracking();
  }
}
```

## Core APIs

### 1. Set location

```dart
final bool? ok = await Geofire.setLocation(
  'driver_123',
  -1.286389,
  36.817223,
  data: {
    'vehicleType': 'bike',
    'region': 'nairobi',
    'isVerified': true,
    'rating': 4.8,
    'activeTrips': 0,
    'priority': 2,
  },
);
```

Notes:
1. data supports arbitrary key/value pairs.
2. Keys g and l are reserved by GeoFire and ignored in custom data.
3. Writes are queued and retried when Firebase connectivity recovers.

### 2. Get location

```dart
final Map<String, dynamic> location = await Geofire.getLocation('driver_123');
print(location);
```

### 3. Remove location

```dart
await Geofire.removeLocation('driver_123');
```

### 4. Proximity query stream

```dart
final sub = Geofire.queryAtLocation(-1.286389, 36.817223, 5).listen((event) {
  final callback = event['callBack'];
  switch (callback) {
    case Geofire.onKeyEntered:
    case Geofire.onKeyMoved:
    case Geofire.onKeyExited:
    case Geofire.onGeoQueryReady:
      break;
  }
});
```

Stop query listeners:

```dart
await Geofire.stopListener();
await sub.cancel();
```

## Ride-dispatch helpers

### Filtered query

```dart
Geofire.queryAtLocationFiltered(
  -1.286389,
  36.817223,
  5,
  equalsData: {
    'vehicleType': 'bike',
    'region': 'nairobi',
    'isVerified': true,
  },
).listen((event) {
  print(event);
});
```

### Advanced filtering + ranking

```dart
Geofire.queryAtLocationAdvanced(
  -1.286389,
  36.817223,
  5,
  equalsData: {'region': 'nairobi'},
  minData: {'rating': 4.5},
  maxData: {'activeTrips': 1},
  limit: 20,
  scoreBy: (event) {
    final data = (event['data'] as Map?) ?? {};
    final rating = (data['rating'] as num?)?.toDouble() ?? 0;
    final priority = (data['priority'] as num?)?.toDouble() ?? 0;
    return (priority * 2.0) + rating;
  },
).listen((event) {
  print(event);
});
```

### Typed driver events

```dart
Geofire.queryDriversAtLocationTyped(
  -1.286389,
  36.817223,
  5,
  vehicleType: 'bike',
  region: 'nairobi',
  isVerified: true,
  minRating: 4.5,
  maxActiveTrips: 1,
).listen((event) {
  if (event.type == GeofireEventType.keyEntered ||
      event.type == GeofireEventType.keyMoved) {
    print(event.key);
    print(event.data.rating);
  }
});
```

### Ranked candidate stream (best for rider assignment)

```dart
Geofire.queryDriverCandidatesAtLocation(
  -1.286389,
  36.817223,
  5,
  vehicleType: 'bike',
  region: 'nairobi',
  isVerified: true,
  minRating: 4.5,
  maxActiveTrips: 1,
  limit: 20,
).listen((candidates) {
  if (candidates.isEmpty) return;
  final best = candidates.first;
  print(best.key);
  print(best.score);
});
```

## Native location tracking (optional)

Use native tracking when you want platform-side location collection instead of pushing every lat/lng from Dart.

### Start (simple bool)

```dart
final bool? started = await Geofire.startNativeTracking(
  GeofireNativeTrackingConfig(
    id: 'driver_123',
    intervalMs: 10000,
    minDistanceMeters: 20,
    includeLocationMeta: true,
    allowBackground: true,
    useForegroundService: true,   // Android option
    useSignificantChanges: false, // iOS option
    foregroundNotificationTitle: 'Driver online',
    foregroundNotificationBody: 'Sharing live location',
    data: {
      'vehicleType': 'bike',
      'region': 'nairobi',
    },
  ),
);
```

### Start (detailed reason codes)

```dart
final result = await Geofire.startNativeTrackingDetailed(
  GeofireNativeTrackingConfig(
    id: 'driver_123',
    allowBackground: true,
    useForegroundService: true,
  ),
);

print('started: ${result.started}, reason: ${result.reason}');
```

### Status and stop

```dart
final status = await Geofire.nativeTrackingStatus();
print(status);

await Geofire.stopNativeTracking();
```

Common reason codes include:
1. started
2. not_initialized
3. permission_denied
4. invalid_id
5. authorization_request_initiated (iOS)
6. foreground_service_start_failed (Android)

Background behavior notes:
1. Android reliability is strongest with foreground service mode enabled.
2. iOS background tracking requires proper Info.plist location usage keys and Background Modes.
3. Runtime permission prompts must be handled by your host app UX.

## Backend adapters (non-default backends)

By default, this package uses MethodChannelGeofireBackend (native Firebase behavior).

You can switch backend before initialize:

```dart
Geofire.configureBackend(
  SupabaseGeofireBackend(
    edgeFunctionBaseUrl: 'https://<project>.functions.supabase.co/geofire',
    anonKey: '<SUPABASE_ANON_KEY>',
  ),
);

await Geofire.initialize('drivers_live');
```

Built-in adapters:
1. MethodChannelGeofireBackend
2. FirestoreGeofireBackend
3. SupabaseGeofireBackend
4. PostgresGeofireBackend
5. MysqlGeofireBackend

Go starter backends:
1. backend_starters/postgres-go
2. backend_starters/mysql-go

### REST contract used by adapters

1. POST /initialize
2. POST /set-location
3. POST /remove-location
4. GET /get-location
5. GET /query

Expected /query row shape:

```json
[
  {
    "key": "driver_123",
    "latitude": -1.286389,
    "longitude": 36.817223,
    "data": {
      "vehicleType": "bike"
    }
  }
]
```

The package converts query rows into realtime-style callbacks:
1. onKeyEntered
2. onKeyMoved
3. onKeyExited
4. onGeoQueryReady

## Google Maps pattern (query by map center)

Use map camera center as query origin and restart on camera idle.

Best practices:
1. Re-query on onCameraIdle, not on every onCameraMove tick.
2. Cancel old stream before opening a new one.
3. Keep radius bounded for density.
4. Use data filters to reduce churn.

## Example app

A runnable dispatch demo is included in:
1. example/lib/main.dart
2. example/README.md

It demonstrates:
1. publish/remove driver location
2. ranked candidate stream
3. native tracking start/stop/status

## Troubleshooting

1. initialize returns false:
- Verify Firebase configuration and Realtime Database path.

2. Query returns no keys:
- Ensure rules include .indexOn: ["g"] for your path.

3. Native tracking start fails:
- Check runtime permissions, location services, and reason code from startNativeTrackingDetailed.

4. iOS background not updating:
- Verify Info.plist location usage strings and Background Modes capability.

5. Android background unstable:
- Enable useForegroundService and confirm notification/service permissions on device OS.

## pub.dev release checklist

1. Bump version in pubspec.yaml.
2. Update CHANGELOG.md.
3. Run flutter analyze.
4. Run flutter test.
5. Run flutter pub publish --dry-run.
6. Publish with flutter pub publish.

## Contributing

Pull requests and issue reports are welcome.
