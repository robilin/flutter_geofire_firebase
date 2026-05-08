# flutter_geofire example

This example demonstrates a realistic driver/rider flow for ride dispatch:

1. Driver app behavior: publish live location with metadata using `setLocation(..., data: ...)`
2. Rider app behavior: consume ranked candidates using `queryDriverCandidatesAtLocation(...)`

## Run the example

1. Configure Firebase in this example app (`google-services.json` / iOS setup).
2. Ensure your Realtime Database rules include `.indexOn: ["g"]` for the reference path.
3. Run:

```
flutter pub get
flutter run
```

## What to test in the UI

1. Tap `Publish Driver` to write demo driver location + metadata.
2. Observe `Best Candidate` and the `Candidate List` update in real time.
3. Tap `Remove Driver` and watch candidate updates.
4. Tap `Restart Query` to re-subscribe the rider query stream.

The implementation is in `example/lib/main.dart`.

