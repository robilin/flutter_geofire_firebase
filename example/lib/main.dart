import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_geofire/flutter_geofire.dart';

const String _pathToReference = 'drivers_live';
const String _demoDriverId = 'driver_demo_001';

const double _driverLat = -1.286389;
const double _driverLng = 36.817223;

const double _riderLat = -1.2855;
const double _riderLng = 36.8168;

void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const GeofireDispatchDemoPage(),
      theme: ThemeData(primarySwatch: Colors.indigo),
    );
  }
}

class GeofireDispatchDemoPage extends StatefulWidget {
  const GeofireDispatchDemoPage({Key? key}) : super(key: key);

  @override
  State<GeofireDispatchDemoPage> createState() =>
      _GeofireDispatchDemoPageState();
}

class _GeofireDispatchDemoPageState extends State<GeofireDispatchDemoPage> {
  final List<GeofireDriverCandidate> _candidates = <GeofireDriverCandidate>[];

  StreamSubscription<List<GeofireDriverCandidate>>? _candidateSubscription;

  bool _initialized = false;
  String _status = 'Initializing...';

  @override
  void initState() {
    super.initState();
    _initializeAndStartQuery();
  }

  @override
  void dispose() {
    _candidateSubscription?.cancel();
    Geofire.stopListener();
    super.dispose();
  }

  Future<void> _initializeAndStartQuery() async {
    final bool ok = await Geofire.initialize(_pathToReference);
    if (!mounted) {
      return;
    }

    if (!ok) {
      setState(() {
        _status = 'Initialization failed';
      });
      return;
    }

    setState(() {
      _initialized = true;
      _status = 'Ready';
    });

    await _candidateSubscription?.cancel();
    _candidateSubscription = Geofire.queryDriverCandidatesAtLocation(
      _riderLat,
      _riderLng,
      5,
      vehicleType: 'bike',
      region: 'nairobi',
      isVerified: true,
      minRating: 4.0,
      maxActiveTrips: 1,
      limit: 20,
    ).listen((List<GeofireDriverCandidate> candidates) {
      if (!mounted) {
        return;
      }

      setState(() {
        _candidates
          ..clear()
          ..addAll(candidates);
        _status = 'Live query running';
      });
    }, onError: (Object error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _status = 'Query error: $error';
      });
    });
  }

  Future<void> _publishDemoDriverLocation() async {
    if (!_initialized) {
      return;
    }

    final bool? response = await Geofire.setLocation(
      _demoDriverId,
      _driverLat,
      _driverLng,
      data: <String, dynamic>{
        'driverId': _demoDriverId,
        'vehicleType': 'bike',
        'region': 'nairobi',
        'isVerified': true,
        'rating': 4.8,
        'activeTrips': 0,
        'priority': 2,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _status = response == true
          ? 'Driver location published'
          : 'Failed to publish driver location';
    });
  }

  Future<void> _removeDemoDriverLocation() async {
    final bool? response = await Geofire.removeLocation(_demoDriverId);
    if (!mounted) {
      return;
    }

    setState(() {
      _status = response == true
          ? 'Driver location removed'
          : 'Failed to remove driver location';
    });
  }

  @override
  Widget build(BuildContext context) {
    final GeofireDriverCandidate? bestCandidate =
        _candidates.isEmpty ? null : _candidates.first;

    return Scaffold(
      appBar: AppBar(
        title: const Text('GeoFire Driver/Rider Demo'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'Status',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(_status),
                    const SizedBox(height: 8),
                    Text('Matched candidates: ${_candidates.length}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                ElevatedButton(
                  onPressed: _initialized ? _publishDemoDriverLocation : null,
                  child: const Text('Publish Driver'),
                ),
                ElevatedButton(
                  onPressed: _initialized ? _removeDemoDriverLocation : null,
                  child: const Text('Remove Driver'),
                ),
                OutlinedButton(
                  onPressed: _initializeAndStartQuery,
                  child: const Text('Restart Query'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (bestCandidate != null)
              Card(
                color: Colors.indigo.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'Best Candidate',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text('Key: ${bestCandidate.key}'),
                      Text('Score: ${bestCandidate.score.toStringAsFixed(2)}'),
                      Text(
                          'Distance: ${bestCandidate.distanceKm.toStringAsFixed(2)} km'),
                      Text('Vehicle: ${bestCandidate.data.vehicleType ?? '-'}'),
                      Text('Rating: ${bestCandidate.data.rating ?? '-'}'),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            const Text(
              'Candidate List',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _candidates.isEmpty
                  ? const Center(child: Text('No matched drivers yet'))
                  : ListView.separated(
                      itemCount: _candidates.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (BuildContext context, int index) {
                        final GeofireDriverCandidate candidate =
                            _candidates[index];
                        return ListTile(
                          dense: true,
                          title: Text(candidate.key),
                          subtitle: Text(
                            'score ${candidate.score.toStringAsFixed(2)} | '
                            'distance ${candidate.distanceKm.toStringAsFixed(2)} km | '
                            'rating ${candidate.data.rating ?? '-'}',
                          ),
                          trailing:
                              Text(candidate.data.vehicleType ?? 'unknown'),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
