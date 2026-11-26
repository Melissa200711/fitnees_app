import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/activity_record.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';

String _fmtDate(DateTime d) =>
    '${d.day}/${d.month}/${d.year} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';

String _fmtDuration(int seconds) {
  final m = (seconds ~/ 60).toString().padLeft(2, '0');
  final s = (seconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

String _fmtDistance(double meters) => meters >= 1000
    ? '${(meters / 1000).toStringAsFixed(2)} km'
    : '${meters.toStringAsFixed(0)} m';

/// Historial de carreras y estadísticas acumuladas (RF-06).
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = AuthService.currentUser ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Historial')),
      body: FutureBuilder<List<ActivityRecord>>(
        future: DatabaseService.getByUser(user),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('No se pudo leer el historial'));
          }
          final records = snapshot.data ?? [];
          if (records.isEmpty) {
            return const Center(
              child: Text('Aún no tienes entrenamientos guardados'),
            );
          }

          final totalSteps = records.fold<int>(0, (a, r) => a + r.steps);
          final totalDist =
          records.fold<double>(0, (a, r) => a + r.distanceMeters);

          return Column(
            children: [
              Card(
                margin: const EdgeInsets.all(12),
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _Stat('Sesiones', '${records.length}'),
                      _Stat('Pasos', '$totalSteps'),
                      _Stat('Distancia', _fmtDistance(totalDist)),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: records.length,
                  itemBuilder: (context, i) {
                    final r = records[i];
                    return ListTile(
                      leading: const Icon(Icons.directions_run),
                      title: Text(_fmtDate(r.date)),
                      subtitle: Text(
                        '${r.steps} pasos · ${_fmtDistance(r.distanceMeters)} · '
                            '${_fmtDuration(r.durationSeconds)}',
                      ),
                      trailing: const Icon(Icons.map_outlined),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RouteDetailScreen(record: r),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label),
      ],
    );
  }
}

/// Muestra la ruta guardada de una sesión.
class RouteDetailScreen extends StatelessWidget {
  final ActivityRecord record;
  const RouteDetailScreen({super.key, required this.record});

  @override
  Widget build(BuildContext context) {
    final points = record.routePoints;
    return Scaffold(
      appBar: AppBar(title: Text(_fmtDate(record.date))),
      body: points.isEmpty
          ? const Center(child: Text('Esta sesión no tiene ruta GPS'))
          : FlutterMap(
        options: MapOptions(
          initialCenter: points.first,
          initialZoom: 16,
          initialCameraFit: points.length >= 2
              ? CameraFit.coordinates(
            coordinates: points,
            padding: const EdgeInsets.all(40),
          )
              : null,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.fitness_app',
          ),
          if (points.length >= 2)
            PolylineLayer(
              polylines: [
                Polyline(
                  points: points,
                  strokeWidth: 5,
                  color: Colors.blue,
                ),
              ],
            ),
          MarkerLayer(
            markers: [
              Marker(
                point: points.first,
                width: 36,
                height: 36,
                child: const Icon(Icons.flag, color: Colors.green),
              ),
              Marker(
                point: points.last,
                width: 36,
                height: 36,
                child: const Icon(Icons.location_on, color: Colors.red),
              ),
            ],
          ),
        ],
      ),
    );
  }
}