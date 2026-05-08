# flutter_geofire

A Flutter plugin to use the [GeoFire Api](https://github.com/googlearchive/geofire)

For Flutter plugins for other products, see [mrdishant@github](https://github.com/mrdishant)

Note: This plugin is still under development, and some APIs might not be available yet. Feedback and Pull Requests are most welcome!

## iOS Installation
In your project's pod file add the below line

### pod 'GeoFire', :git => 'https://github.com/mrdishant/geofire-objc'

Example:
```
            target 'Runner' do
            use_frameworks!
            use_modular_headers!
            pod 'GeoFire', :git => 'https://github.com/mrdishant/geofire-objc'
            
            flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
            end
```


## Usage

GeoFire  — Realtime location queries with Firebase.

GeoFire is an open-source library that allows you to store and query a set of keys based on their geographic location.

At its heart, GeoFire simply stores locations with string keys. Its main benefit however, is the possibility of querying keys within a given geographic area - all in realtime.

GeoFire uses the Firebase database for data storage, allowing query results to be updated in realtime as they change. GeoFire selectively loads only the data near certain locations, keeping your applications light and responsive, even with extremely large datasets.

#### Quickstart

 Initalize GeoFire with path to keys in Realtime Database
    
    String pathToReference = "Sites";
    Intializing geoFire
    Geofire.initialize(pathToReference);
 
 Also don't forget to add indexOn in your Realtime Database rules
   
   Example: Just change the 'Sites' with your pathToReference
    
    
        {
          "rules": {
            ".read":true,
            ".write": true,
              "Sites": {
              ".indexOn": ["g"]
            }
          }
        }   
    
    
    
    
#### Setting location data

Here setLocation method is used and first is the unique id of the place and other two parameters are latitude and longitude of that place.

    bool response = await Geofire.setLocation(
            new DateTime.now().millisecondsSinceEpoch.toString(),
            30.730743,
            76.774948)

You can also attach unlimited custom fields using the optional `data` parameter:

    bool response = await Geofire.setLocation(
            new DateTime.now().millisecondsSinceEpoch.toString(),
            -1.286389,
            36.817223,
            data: {
              "accuracy": 5.0,
              "speed": 0.0,
              "bearing": 0.0,
              "altitude": 1661.0,
              "provider": "gps",
              "timestamp": 1746310000000,
              "driverId": "drv_123",
              "vehicleType": "bike",
              "region": "nairobi",
              "shiftId": "shift_456",
              "priority": 1,
              "isVerified": true
            })

The plugin stores these fields inside a single `data` child for each key.

Note: GeoFire reserves `g` and `l` internally for geohash and location. Those keys are ignored from custom data.

The plugin now enables Firebase offline persistence on startup and queues pending `setLocation(...)` writes (with or without `data`) locally, then retries them on the next `Geofire.initialize(...)`.
            
#### Retrieving a location

Retrieving a location for a single key in GeoFire happens like below:

    Map<String, dynamic> response =
            await Geofire.getLocation("AsH28LWk8MXfwRLfVxgx");
    
    print(response);
            
#### Geo Queries

GeoFire allows you to query all keys within a geographic area using GeoQuery objects. As the locations for keys change, the query is updated in realtime and fires events letting you know if any relevant keys have moved. GeoQuery parameters can be updated later to change the size and center of the queried area.

    Geofire.queryAtLocation(30.730743, 76.774948, 5).listen((map) {
            print(map);
            if (map != null) {
              var callBack = map['callBack'];
    
              //latitude will be retrieved from map['latitude']
              //longitude will be retrieved from map['longitude']
    
              switch (callBack) {
                case Geofire.onKeyEntered:
                  keysRetrieved.add(map["key"]);
                  break;
    
                case Geofire.onKeyExited:
                  keysRetrieved.remove(map["key"]);
                  break;
    
                case Geofire.onKeyMoved:
                // Update your key's location
                  break;
    
                case Geofire.onGeoQueryReady:
                // All Intial Data is loaded
                print(map['result'])
    
                  break;
              }
            }
    
            setState(() {});

`queryAtLocation(...)` is optimized for proximity events only.
It does not fetch each key's extra `data` by default, which reduces read costs and latency.

#### Geo Queries with filtering for ride apps

Query events now include your custom `data` payload for each key. You can filter using exact key/value matches:

    Geofire.queryAtLocationFiltered(
      -1.286389,
      36.817223,
      5,
      equalsData: {
        "isVerified": true,
        "vehicleType": "bike",
        "region": "nairobi"
      },
    ).listen((event) {
      print(event);
      // event["data"] contains your additional fields
      // use this to decide matching drivers for dispatch
    });

For more control, use advanced filters and ranking:

    Geofire.queryAtLocationAdvanced(
      -1.286389,
      36.817223,
      5,
      equalsData: {
        "isVerified": true,
        "region": "nairobi"
      },
      minData: {
        "rating": 4.5,
      },
      maxData: {
        "activeTrips": 1,
      },
      scoreBy: (event) {
        final data = (event["data"] as Map?) ?? {};
        final priority = (data["priority"] as num?)?.toDouble() ?? 0.0;
        final rating = (data["rating"] as num?)?.toDouble() ?? 0.0;
        return (priority * 2.0) + rating;
      },
      limit: 20,
    ).listen((event) {
      // decisions with richer context and ranking
      print(event);
    });

If this package is used in a driver app (publish via `setLocation`) and a user app (query nearby drivers), you can use a dedicated helper:

    Geofire.queryDriversAtLocation(
      -1.286389,
      36.817223,
      5,
      vehicleType: "bike",
      region: "nairobi",
      isVerified: true,
      minRating: 4.5,
      maxActiveTrips: 1,
      limit: 20,
    ).listen((event) {
      print(event);
      // event["data"] contains matching driver attributes
      // ideal for rider-side dispatch decisions
    });

To avoid map key strings in your app code, use the typed stream:

    Geofire.queryDriversAtLocationTyped(
      -1.286389,
      36.817223,
      5,
      vehicleType: "bike",
      region: "nairobi",
      isVerified: true,
      minRating: 4.5,
      maxActiveTrips: 1,
      limit: 20,
    ).listen((event) {
      if (event.type == GeofireEventType.keyEntered ||
          event.type == GeofireEventType.keyMoved) {
        print(event.key);
        print(event.data.vehicleType);
        print(event.data.rating);
        print(event.latitude);
        print(event.longitude);
      }
    });

For dispatch-focused rider logic, use the candidate stream API (already ranked):

    Geofire.queryDriverCandidatesAtLocation(
      -1.286389,
      36.817223,
      5,
      vehicleType: "bike",
      region: "nairobi",
      isVerified: true,
      minRating: 4.5,
      maxActiveTrips: 1,
      limit: 20,
    ).listen((candidates) {
      if (candidates.isEmpty) {
        return;
      }

      final best = candidates.first;
      print(best.key);
      print(best.score);
      print(best.distanceKm);
      print(best.data.vehicleType);
    });

### Driver app + rider app reference flow

Driver app:
1. `Geofire.initialize("drivers_live")`
2. Send frequent `Geofire.setLocation(driverId, lat, lng, data: {...})`
3. Keep driver attributes stable in `data` (vehicleType, isVerified, region, rating, activeTrips)

Rider app:
1. `Geofire.initialize("drivers_live")`
2. Query using `queryDriverCandidatesAtLocation(...)`
3. Use top candidate(s) for assignment and fallback to next candidates

Publishing tip for pub.dev:
1. Include a minimal and a full-feature example in your package `example/`
2. Document required Firebase rules (`.indexOn: ["g"]`) and expected `data` keys
3. Keep README snippets copy-paste ready with both driver and rider flows

Runnable demo:
1. Full driver/rider dispatch example is available in `example/lib/main.dart`

### pub.dev release checklist

Before release:
1. Update version in `pubspec.yaml`
2. Add release notes in `CHANGELOG.md`
3. Verify README examples compile against current API
4. Ensure `example/` runs and demonstrates the latest APIs

Validation commands (run from package root):

  flutter format lib example/lib
  flutter analyze
  flutter test
  flutter pub publish --dry-run

Publishing:
1. Commit version/changelog/docs updates
2. Tag the release in git (recommended)
3. Publish:

  flutter pub publish

Post-publish:
1. Confirm package page on pub.dev renders README correctly
2. Verify score checks (platform, docs, example)
3. Test install in a clean Flutter project

#### Stop Listening to Geo Query
To remove listeners to all queries:

    bool response = await Geofire.stopListener();

    print(response);

## Removing a location
To remove a location and delete it from the database simply pass the location's key to removeLocation:

    bool response = await Geofire.removeLocation("AsH28LWk8MXfwRLfVxgx");

    print(response);                

## Contributing
if you want to contribute to GeoFire, clone the repository and just start making pull requests.

    git clone 'https://github.com/mrdishant/flutter_geofire'

### This plugin is in development and suggestions are most welcome. Happy Coding and Be Exceptional !!


