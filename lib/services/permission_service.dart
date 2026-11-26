import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Permisos en tiempo de ejecución con diálogos informativos (RNF-02).
///
/// Nota: la biometría (USE_BIOMETRIC) es un permiso "normal" que se declara
/// en el AndroidManifest; el sistema muestra su propio diálogo de huella/rostro.
class PermissionService {
  /// Pide actividad física y ubicación. Devuelve true si se concedió al menos
  /// uno (la app sigue funcionando con los sensores disponibles).
  static Future<bool> requestAll(BuildContext context) async {
    final activity = await Permission.activityRecognition.status;
    final location = await Permission.locationWhenInUse.status;

    if (activity.isGranted && location.isGranted) return true;

    // 1) Diálogo informativo ANTES de pedir el permiso.
    final accept = await _showInfoDialog(context);
    if (accept != true) return false;

    // 2) Solicitud real del sistema.
    final result = await [
      Permission.activityRecognition,
      Permission.locationWhenInUse,
    ].request();

    final anyGranted = result.values.any((s) => s.isGranted);
    final permanentlyDenied = result.values.any((s) => s.isPermanentlyDenied);

    // 3) Si el usuario marcó "No volver a preguntar", ofrecer abrir ajustes.
    if (permanentlyDenied && context.mounted) {
      await _showSettingsDialog(context);
    }
    return anyGranted;
  }

  static Future<bool?> _showInfoDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Permisos necesarios'),
        content: const Text(
          'Para registrar tu entrenamiento necesitamos:\n\n'
              '• Actividad física: contar tus pasos.\n'
              '• Ubicación: dibujar tu ruta y calcular la distancia.\n\n'
              'Solo se usan mientras entrenas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Ahora no'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
  }

  static Future<void> _showSettingsDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Permiso denegado'),
        content: const Text(
          'Bloqueaste un permiso. Puedes activarlo manualmente en '
              'Ajustes > Aplicaciones > Fitness App > Permisos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
          FilledButton(
            onPressed: () {
              openAppSettings();
              Navigator.pop(ctx);
            },
            child: const Text('Abrir ajustes'),
          ),
        ],
      ),
    );
  }
}