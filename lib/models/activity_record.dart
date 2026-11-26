import 'dart:convert';

import 'package:latlong2/latlong.dart';

/// Una sesión de entrenamiento guardada en SQLite.
class ActivityRecord {
  final int? id;
  final String user;
  final DateTime date;
  final int durationSeconds;
  final int steps;
  final double distanceMeters;

  /// Ruta guardada como JSON: [[lat, lng], [lat, lng], ...]
  final String routeJson;

  ActivityRecord({
    this.id,
    required this.user,
    required this.date,
    required this.durationSeconds,
    required this.steps,
    required this.distanceMeters,
    required this.routeJson,
  });

  /// Convierte la lista de puntos del GPS a texto JSON.
  static String encodeRoute(List<LatLng> points) =>
      jsonEncode(points.map((p) => [p.latitude, p.longitude]).toList());

  /// Convierte el JSON guardado de vuelta a puntos del mapa.
  List<LatLng> get routePoints {
    try {
      final list = jsonDecode(routeJson) as List<dynamic>;
      return list
          .map((e) => LatLng((e[0] as num).toDouble(), (e[1] as num).toDouble()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'user': user,
    'date': date.toIso8601String(),
    'duration': durationSeconds,
    'steps': steps,
    'distance': distanceMeters,
    'route': routeJson,
  };

  factory ActivityRecord.fromMap(Map<String, Object?> m) => ActivityRecord(
    id: m['id'] as int?,
    user: m['user'] as String,
    date: DateTime.parse(m['date'] as String),
    durationSeconds: m['duration'] as int,
    steps: m['steps'] as int,
    distanceMeters: (m['distance'] as num).toDouble(),
    routeJson: m['route'] as String,
  );
}