import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'camera_models.dart';

abstract class CameraRepository {
  Future<void> initialize();
  List<CameraRecord> get records;
  bool get syncInProgress;
  bool get usingOfflineCache;
  String get attribution;
  Future<void> refreshAround(double latitude, double longitude);
}

class OsmCameraRepository implements CameraRepository {
  OsmCameraRepository({
    http.Client? client,
    FlutterSecureStorage? storage,
  })  : _client = client ?? http.Client(),
        _storage = storage ?? const FlutterSecureStorage();

  static const String _cacheKey = 'sc_drive_camera_cache_v1';
  static const double _syncRadiusMeters = 18000;
  static const double _resyncMovementMeters = 5500;
  static const Duration _maxCacheAge = Duration(hours: 12);
  static const int _maxCachedRecords = 600;
  static final Uri _overpassUri =
      Uri.parse('https://overpass-api.de/api/interpreter');

  final http.Client _client;
  final FlutterSecureStorage _storage;

  List<CameraRecord> _records = const <CameraRecord>[];
  double? _centerLatitude;
  double? _centerLongitude;
  DateTime? _syncedAt;
  bool _initialized = false;
  bool _syncInProgress = false;
  bool _lastSyncFailed = false;

  @override
  List<CameraRecord> get records => _records;

  @override
  bool get syncInProgress => _syncInProgress;

  @override
  bool get usingOfflineCache => _records.isNotEmpty && _lastSyncFailed;

  @override
  String get attribution => '© OpenStreetMap contributors';

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final cached = await _storage.read(key: _cacheKey);
      if (cached == null || cached.isEmpty) return;
      final envelope = CameraCacheEnvelope.decode(cached);
      _records = envelope.records;
      _centerLatitude = envelope.centerLatitude;
      _centerLongitude = envelope.centerLongitude;
      _syncedAt = envelope.syncedAt;
    } catch (_) {
      // Corrupt cache must never break Live Map. The next successful sync will
      // replace it atomically at the key-value level.
      _records = const <CameraRecord>[];
    }
  }

  @override
  Future<void> refreshAround(double latitude, double longitude) async {
    if (_syncInProgress || !_needsRefresh(latitude, longitude)) return;
    _syncInProgress = true;
    try {
      final query = '''
[out:json][timeout:14];
(
  node["highway"="speed_camera"](around:${_syncRadiusMeters.round()},$latitude,$longitude);
  node["enforcement"="maxspeed"](around:${_syncRadiusMeters.round()},$latitude,$longitude);
);
out body;
''';
      final response = await _client
          .post(_overpassUri, body: <String, String>{'data': query})
          .timeout(const Duration(seconds: 18));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Overpass HTTP ${response.statusCode}');
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final elements = decoded['elements'] as List<dynamic>? ?? const <dynamic>[];
      final now = DateTime.now().toUtc();
      final byId = <String, CameraRecord>{};
      for (final element in elements) {
        if (element is! Map<String, dynamic>) continue;
        final lat = (element['lat'] as num?)?.toDouble();
        final lon = (element['lon'] as num?)?.toDouble();
        final id = element['id'];
        if (lat == null || lon == null || id == null) continue;
        final tags = (element['tags'] as Map?)?.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            ) ??
            const <String, String>{};
        final record = CameraRecord(
          id: 'osm-node-$id',
          latitude: lat,
          longitude: lon,
          type: _cameraType(tags),
          speedLimitKph: _parseSpeedLimit(tags['maxspeed']),
          headingDeg: _parseHeading(
            tags['camera:direction'] ?? tags['direction'],
          ),
          roadName: tags['road_name'] ?? tags['name'] ?? tags['ref'],
          source: 'OPENSTREETMAP',
          confidence: tags['highway'] == 'speed_camera' ? 0.88 : 0.76,
          updatedAt: now,
        );
        byId[record.id] = record;
      }

      final sorted = byId.values.toList()
        ..sort((a, b) => _distanceMeters(
              latitude,
              longitude,
              a.latitude,
              a.longitude,
            ).compareTo(_distanceMeters(
              latitude,
              longitude,
              b.latitude,
              b.longitude,
            )));
      _records = sorted.take(_maxCachedRecords).toList(growable: false);
      _centerLatitude = latitude;
      _centerLongitude = longitude;
      _syncedAt = now;
      _lastSyncFailed = false;
      await _persist();
    } catch (_) {
      // Offline-first: retain the last known-good camera set.
      _lastSyncFailed = true;
    } finally {
      _syncInProgress = false;
    }
  }

  bool _needsRefresh(double latitude, double longitude) {
    final centerLat = _centerLatitude;
    final centerLon = _centerLongitude;
    final synced = _syncedAt;
    if (_records.isEmpty || centerLat == null || centerLon == null || synced == null) {
      return true;
    }
    if (DateTime.now().toUtc().difference(synced) >= _maxCacheAge) return true;
    return _distanceMeters(latitude, longitude, centerLat, centerLon) >=
        _resyncMovementMeters;
  }

  Future<void> _persist() async {
    try {
      final encoded = CameraCacheEnvelope(
        records: _records,
        centerLatitude: _centerLatitude,
        centerLongitude: _centerLongitude,
        syncedAt: _syncedAt,
      ).encode();
      await _storage.write(key: _cacheKey, value: encoded);
    } catch (_) {
      // Cache persistence is best effort. Live detection continues in memory.
    }
  }

  CameraType _cameraType(Map<String, String> tags) {
    final enforcement = tags['enforcement']?.toLowerCase();
    if (enforcement == 'traffic_signals') return CameraType.redLight;
    return CameraType.fixedSpeed;
  }

  int? _parseSpeedLimit(String? raw) {
    if (raw == null) return null;
    final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(raw);
    final value = double.tryParse(match?.group(1) ?? '');
    if (value == null || value <= 0) return null;
    if (raw.toLowerCase().contains('mph')) return (value * 1.609344).round();
    return value.round();
  }

  double? _parseHeading(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final normalized = raw.trim().toUpperCase();
    const cardinals = <String, double>{
      'N': 0,
      'NE': 45,
      'E': 90,
      'SE': 135,
      'S': 180,
      'SW': 225,
      'W': 270,
      'NW': 315,
    };
    if (cardinals.containsKey(normalized)) return cardinals[normalized];
    final numeric = double.tryParse(normalized.replaceAll('°', ''));
    if (numeric == null) return null;
    return (numeric % 360 + 360) % 360;
  }

  double _distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earth = 6371000.0;
    final p1 = lat1 * math.pi / 180;
    final p2 = lat2 * math.pi / 180;
    final dp = (lat2 - lat1) * math.pi / 180;
    final dl = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dp / 2) * math.sin(dp / 2) +
        math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
    return earth * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  void dispose() {
    _client.close();
  }
}
