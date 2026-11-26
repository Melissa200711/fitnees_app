import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/activity_record.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/permission_service.dart';
import '../services/sensor_service.dart';
import 'history_screen.dart';
import 'login_screen.dart';

/// Interfaz 3: Dashboard con pasos, actividad, giroscopio, GPS y mapa.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  final SensorService _s = SensorService();
  final MapController _map = MapController();
  bool _mapReady = false;
  bool _autoPaused = false; // pausado por irse a segundo plano
  LatLng? _lastCentered;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _s.addListener(_onSensorUpdate);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _s.removeListener(_onSensorUpdate);
    _s.dispose(); // libera listeners de sensores y GPS
    _map.dispose();
    super.dispose();
  }

  /// Libera listeners al ir a segundo plano y los retoma al volver.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      if (_s.isTracking && !_s.isPaused) {
        _s.pause();
        _autoPaused = true;
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_autoPaused) {
        _autoPaused = false;
        _s.resume();
      }
    }
  }

  void _onSensorUpdate() {
    if (!mounted) return;
    setState(() {});
    final pos = _s.current;
    if (_mapReady && pos != null && pos != _lastCentered) {
      _lastCentered = pos;
      _map.move(pos, _map.camera.zoom);
    }
  }

  // ---------------- Acciones ----------------

  Future<void> _start() async {
    final granted = await PermissionService.requestAll(context);
    if (!granted || !mounted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sin permisos no se pueden medir pasos ni ruta'),
          ),
        );
      }
      return;
    }
    await _s.start();
  }

  Future<void> _stop() async {
    _s.stop();
    final user = AuthService.currentUser ?? 'desconocido';
    final distance =
    _s.gpsDistance > 0 ? _s.gpsDistance : _s.stepDistance; // fallback
    final record = ActivityRecord(
      user: user,
      date: DateTime.now(),
      durationSeconds: _s.elapsed.inSeconds,
      steps: _s.steps,
      distanceMeters: distance,
      routeJson: ActivityRecord.encodeRoute(_s.route),
    );
    await DatabaseService.insert(record);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Actividad guardada en el historial')),
    );
  }

  void _logout() {
    _s.stop();
    AuthService.logout();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  // ---------------- UI ----------------

  String _fmtTime(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final distanceM = _s.gpsDistance > 0 ? _s.gpsDistance : _s.stepDistance;

    return Scaffold(
      appBar: AppBar(
        title: Text('Hola, ${AuthService.currentUser ?? ''}'),
        actions: [
          IconButton(
            tooltip: 'Historial',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HistoryScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            if (_s.isTracking) _warnings(),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.6,
              children: [
                _MetricCard(
                  icon: Icons.directions_walk,
                  label: 'Pasos',
                  value: _s.pedometerOk ? '${_s.steps}' : 'No disponible',
                ),
                _MetricCard(
                  icon: Icons.timer_outlined,
                  label: 'Tiempo',
                  value: _fmtTime(_s.elapsed),
                ),
                _MetricCard(
                  icon: Icons.straighten,
                  label: 'Distancia',
                  value: distanceM >= 1000
                      ? '${(distanceM / 1000).toStringAsFixed(2)} km'
                      : '${distanceM.toStringAsFixed(0)} m',
                ),
                _MetricCard(
                  icon: Icons.speed,
                  label: 'Velocidad',
                  value: _s.gpsOk
                      ? '${_s.speedKmh.toStringAsFixed(1)} km/h'
                      : 'Sin GPS',
                ),
                _MetricCard(
                  icon: Icons.bolt,
                  label: 'Actividad',
                  value: _s.accelOk
                      ? '${_s.activityState}\n(${_s.intensity.toStringAsFixed(2)} m/s²)'
                      : 'No disponible',
                ),
                _MetricCard(
                  icon: Icons.screen_rotation,
                  label: 'Giroscopio',
                  value: _s.gyroOk
                      ? '${_s.orientation}\nX ${_s.gx.toStringAsFixed(1)} '
                      'Y ${_s.gy.toStringAsFixed(1)} '
                      'Z ${_s.gz.toStringAsFixed(1)}'
                      : 'No disponible',
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 300,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter:
                    _s.current ?? const LatLng(19.4326, -99.1332),
                    initialZoom: 16,
                    onMapReady: () => _mapReady = true,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.fitness_app',
                    ),
                    if (_s.route.length >= 2)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: List.of(_s.route),
                            strokeWidth: 5,
                            color: Colors.blue,
                          ),
                        ],
                      ),
                    if (_s.current != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _s.current!,
                            width: 40,
                            height: 40,
                            child: const Icon(
                              Icons.my_location,
                              color: Colors.red,
                              size: 32,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            _buttons(),
          ],
        ),
      ),
    );
  }

  /// Avisos cuando falta algún sensor (RNF-04).
  Widget _warnings() {
    final missing = <String>[
      if (!_s.pedometerOk) 'podómetro',
      if (!_s.accelOk) 'acelerómetro',
      if (!_s.gyroOk) 'giroscopio',
      if (!_s.gpsOk) 'GPS',
    ];
    if (missing.isEmpty) return const SizedBox.shrink();
    return Card(
      color: Colors.amber.shade100,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Text(
          'No disponible: ${missing.join(', ')}. '
              'La app continúa con los demás sensores.',
        ),
      ),
    );
  }

  Widget _buttons() {
    if (!_s.isTracking) {
      return SizedBox(
        height: 52,
        child: FilledButton.icon(
          onPressed: _start,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Iniciar entrenamiento'),
        ),
      );
    }
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed: _s.isPaused ? _s.resume : _s.pause,
              icon: Icon(_s.isPaused ? Icons.play_arrow : Icons.pause),
              label: Text(_s.isPaused ? 'Reanudar' : 'Pausar'),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SizedBox(
            height: 52,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: _stop,
              icon: const Icon(Icons.stop),
              label: const Text('Terminar'),
            ),
          ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: scheme.onPrimaryContainer),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}