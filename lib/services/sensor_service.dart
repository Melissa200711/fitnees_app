import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:pedometer/pedometer.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Maneja podómetro, acelerómetro, giroscopio y GPS.
///
/// - Cada sensor tiene un fallback: si falta o falla, su bandera *Ok pasa a
///   false y la app sigue funcionando (RNF-04).
/// - pause()/stop()/dispose() cancelan todos los listeners para ahorrar
///   batería (RNF-01).
/// - La UI se refresca cada 500 ms (no en cada evento) para no saturar el
///   hilo principal (RNF-03).
class SensorService extends ChangeNotifier {
  static const double stepLengthM = 0.762; // zancada promedio estimada

  // ---- Datos ----
  int steps = 0;
  double intensity = 0; // desviación de la gravedad (m/s²), suavizada
  String activityState = 'Descanso';
  double gx = 0, gy = 0, gz = 0; // velocidad angular (rad/s)
  String orientation = 'Estable';
  final List<LatLng> route = [];
  double gpsDistance = 0; // metros
  double speedKmh = 0;
  LatLng? current;

  double get stepDistance => steps * stepLengthM;
  Duration get elapsed => _clock.elapsed;

  // ---- Disponibilidad (fallbacks) ----
  bool pedometerOk = true;
  bool accelOk = true;
  bool gyroOk = true;
  bool gpsOk = true;

  // ---- Estado ----
  bool isTracking = false;
  bool isPaused = false;

  final Stopwatch _clock = Stopwatch();
  StreamSubscription<StepCount>? _stepSub;
  StreamSubscription<AccelerometerEvent>? _accSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  StreamSubscription<Position>? _gpsSub;
  Timer? _uiTimer;

  int _stepsAccum = 0; // pasos acumulados antes de una pausa
  int? _stepBaseline; // lectura inicial del contador del sistema
  double _smooth = 0;
  Position? _last;

  // ======================= Control =======================

  Future<void> start() async {
    _resetData();
    isTracking = true;
    isPaused = false;
    _clock
      ..reset()
      ..start();
    await _subscribeAll();
    _startUiTimer();
    notifyListeners();
  }

  /// Cancela listeners pero conserva los datos (app en segundo plano).
  void pause() {
    if (!isTracking || isPaused) return;
    _cancelStreams();
    _uiTimer?.cancel();
    _clock.stop();
    _stepsAccum = steps;
    isPaused = true;
    notifyListeners();
  }

  Future<void> resume() async {
    if (!isTracking || !isPaused) return;
    isPaused = false;
    _clock.start();
    await _subscribeAll();
    _startUiTimer();
    notifyListeners();
  }

  void stop() {
    _cancelStreams();
    _uiTimer?.cancel();
    _clock.stop();
    isTracking = false;
    isPaused = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _cancelStreams();
    _uiTimer?.cancel();
    super.dispose();
  }

  // ======================= Internos =======================

  void _resetData() {
    steps = 0;
    _stepsAccum = 0;
    _stepBaseline = null;
    intensity = 0;
    _smooth = 0;
    activityState = 'Descanso';
    gx = gy = gz = 0;
    orientation = 'Estable';
    route.clear();
    gpsDistance = 0;
    speedKmh = 0;
    _last = null;
    pedometerOk = true;
    accelOk = true;
    gyroOk = true;
    gpsOk = true;
  }

  void _startUiTimer() {
    _uiTimer?.cancel();
    _uiTimer = Timer.periodic(
      const Duration(milliseconds: 500),
          (_) => notifyListeners(),
    );
  }

  void _cancelStreams() {
    _stepSub?.cancel();
    _accSub?.cancel();
    _gyroSub?.cancel();
    _gpsSub?.cancel();
    _stepSub = _accSub = _gyroSub = _gpsSub = null;
    _last = null; // evita saltos de distancia al reanudar
  }

  Future<void> _subscribeAll() async {
    _subscribePedometer();
    _subscribeAccelerometer();
    _subscribeGyroscope();
    await _subscribeGps();
  }

  void _subscribePedometer() {
    _stepBaseline = null; // nueva lectura base al (re)suscribirse
    try {
      _stepSub = Pedometer.stepCountStream.listen(
            (event) {
          _stepBaseline ??= event.steps;
          steps = _stepsAccum + (event.steps - _stepBaseline!);
        },
        onError: (_) => pedometerOk = false,
        cancelOnError: true,
      );
    } catch (_) {
      pedometerOk = false;
    }
  }

  void _subscribeAccelerometer() {
    try {
      _accSub = accelerometerEventStream(
        samplingPeriod: SensorInterval.uiInterval,
      ).listen(
            (e) {
          final magnitude = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
          final deviation = (magnitude - 9.81).abs();
          _smooth = 0.9 * _smooth + 0.1 * deviation; // filtro pasa-bajas
          intensity = _smooth;
          // Umbrales aproximados: ajústalos probando en tu celular.
          if (_smooth < 0.5) {
            activityState = 'Descanso';
          } else if (_smooth < 2.0) {
            activityState = 'Caminata';
          } else {
            activityState = 'Trote';
          }
        },
        onError: (_) => accelOk = false,
        cancelOnError: true,
      );
    } catch (_) {
      accelOk = false;
    }
  }

  void _subscribeGyroscope() {
    try {
      _gyroSub = gyroscopeEventStream(
        samplingPeriod: SensorInterval.uiInterval,
      ).listen(
            (e) {
          gx = e.x;
          gy = e.y;
          gz = e.z;
          final w = sqrt(gx * gx + gy * gy + gz * gz);
          orientation = w > 1.0 ? 'Girando' : 'Estable';
        },
        onError: (_) => gyroOk = false,
        cancelOnError: true,
      );
    } catch (_) {
      gyroOk = false;
    }
  }

  Future<void> _subscribeGps() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        gpsOk = false;
        return;
      }
      _gpsSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5, // metros mínimos entre lecturas
        ),
      ).listen(
            (p) {
          if (p.accuracy > 50) return; // descarta lecturas imprecisas
          final point = LatLng(p.latitude, p.longitude);
          if (_last != null) {
            gpsDistance += Geolocator.distanceBetween(
              _last!.latitude,
              _last!.longitude,
              p.latitude,
              p.longitude,
            );
          }
          _last = p;
          current = point;
          route.add(point);
          speedKmh = p.speed * 3.6;
        },
        onError: (_) => gpsOk = false,
        cancelOnError: true,
      );
    } catch (_) {
      gpsOk = false;
    }
  }
}