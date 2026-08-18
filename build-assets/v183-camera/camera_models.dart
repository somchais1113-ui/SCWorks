import 'dart:convert';

enum CameraType {
  fixedSpeed,
  redLight,
  combined,
  averageSpeedStart,
  averageSpeedEnd,
  unknown,
}

enum CameraAlertPhase { hidden, entering, visible, near, passed, exiting }

class CameraRecord {
  const CameraRecord({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.type,
    required this.source,
    required this.confidence,
    required this.updatedAt,
    this.speedLimitKph,
    this.headingDeg,
    this.roadName,
  });

  final String id;
  final double latitude;
  final double longitude;
  final CameraType type;
  final int? speedLimitKph;
  final double? headingDeg;
  final String? roadName;
  final String source;
  final double confidence;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'lat': latitude,
        'lon': longitude,
        'type': type.name,
        'limit': speedLimitKph,
        'heading': headingDeg,
        'road': roadName,
        'source': source,
        'confidence': confidence,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  factory CameraRecord.fromJson(Map<String, dynamic> json) {
    final typeName = json['type']?.toString();
    final type = CameraType.values.firstWhere(
      (value) => value.name == typeName,
      orElse: () => CameraType.unknown,
    );
    return CameraRecord(
      id: json['id'].toString(),
      latitude: (json['lat'] as num).toDouble(),
      longitude: (json['lon'] as num).toDouble(),
      type: type,
      speedLimitKph: (json['limit'] as num?)?.round(),
      headingDeg: (json['heading'] as num?)?.toDouble(),
      roadName: json['road']?.toString(),
      source: json['source']?.toString() ?? 'UNKNOWN',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.5,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}

class CameraCacheEnvelope {
  const CameraCacheEnvelope({
    required this.records,
    this.centerLatitude,
    this.centerLongitude,
    this.syncedAt,
  });

  final List<CameraRecord> records;
  final double? centerLatitude;
  final double? centerLongitude;
  final DateTime? syncedAt;

  String encode() => jsonEncode(<String, dynamic>{
        'schema': 1,
        'centerLat': centerLatitude,
        'centerLon': centerLongitude,
        'syncedAt': syncedAt?.toUtc().toIso8601String(),
        'records': records.map((record) => record.toJson()).toList(),
      });

  factory CameraCacheEnvelope.decode(String value) {
    final raw = jsonDecode(value) as Map<String, dynamic>;
    final items = (raw['records'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(CameraRecord.fromJson)
        .toList(growable: false);
    return CameraCacheEnvelope(
      records: items,
      centerLatitude: (raw['centerLat'] as num?)?.toDouble(),
      centerLongitude: (raw['centerLon'] as num?)?.toDouble(),
      syncedAt: DateTime.tryParse(raw['syncedAt']?.toString() ?? ''),
    );
  }
}

class CameraAlertSnapshot {
  const CameraAlertSnapshot({
    required this.phase,
    required this.vehicleSpeedKph,
    required this.rawDistanceMeters,
    required this.displayDistanceMeters,
    required this.cachedCameraCount,
    required this.usingOfflineCache,
    required this.syncInProgress,
    this.camera,
  });

  const CameraAlertSnapshot.hidden({
    this.cachedCameraCount = 0,
    this.usingOfflineCache = false,
    this.syncInProgress = false,
  })  : phase = CameraAlertPhase.hidden,
        vehicleSpeedKph = 0,
        rawDistanceMeters = double.infinity,
        displayDistanceMeters = double.infinity,
        camera = null;

  final CameraAlertPhase phase;
  final CameraRecord? camera;
  final double vehicleSpeedKph;
  final double rawDistanceMeters;
  final double displayDistanceMeters;
  final int cachedCameraCount;
  final bool usingOfflineCache;
  final bool syncInProgress;

  bool get shouldRender => camera != null && phase != CameraAlertPhase.hidden;
  bool get isEnteringOrVisible =>
      phase == CameraAlertPhase.entering ||
      phase == CameraAlertPhase.visible ||
      phase == CameraAlertPhase.near ||
      phase == CameraAlertPhase.passed;
}
