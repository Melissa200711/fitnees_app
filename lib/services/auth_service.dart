import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Registro, login con contraseña y login biométrico (RF-01).
class AuthService {
  static final LocalAuthentication _auth = LocalAuthentication();

  /// Usuario con sesión iniciada.
  static String? currentUser;

  static String _hash(String password) =>
      sha256.convert(utf8.encode(password)).toString();

  static Future<Map<String, dynamic>> _loadUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('users');
    if (raw == null) return {};
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  static Future<bool> userExists(String name) async {
    final users = await _loadUsers();
    return users.containsKey(name.trim().toLowerCase());
  }

  static Future<void> register({
    required String name,
    required String email,
    required String password,
    required bool biometric,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final users = await _loadUsers();
    final key = name.trim().toLowerCase();
    users[key] = {
      'name': name.trim(),
      'email': email.trim(),
      'hash': _hash(password),
      'biometric': biometric,
    };
    await prefs.setString('users', jsonEncode(users));
    if (biometric) {
      await prefs.setString('biometric_user', key);
    }
  }

  static Future<bool> loginWithPassword(String name, String password) async {
    final users = await _loadUsers();
    final key = name.trim().toLowerCase();
    final user = users[key] as Map<String, dynamic>?;
    if (user == null) return false;
    if (user['hash'] != _hash(password)) return false;
    currentUser = user['name'] as String;
    return true;
  }

  /// Login con huella/rostro. Devuelve false si falla o no hay usuario
  /// con biometría activada.
  static Future<bool> loginWithBiometric() async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString('biometric_user');
    if (key == null) return false;
    final ok = await authenticate('Verifica tu identidad para entrar');
    if (!ok) return false;
    final users = await _loadUsers();
    final user = users[key] as Map<String, dynamic>?;
    if (user == null) return false;
    currentUser = user['name'] as String;
    return true;
  }

  /// ¿El dispositivo tiene sensor biométrico con huella/rostro registrado?
  static Future<bool> hasBiometrics() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final supported = await _auth.isDeviceSupported();
      if (!canCheck || !supported) return false;
      final available = await _auth.getAvailableBiometrics();
      return available.isNotEmpty;
    } on PlatformException {
      return false;
    }
  }

  /// Muestra el diálogo del sistema para huella/rostro.
  static Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } on PlatformException {
      return false;
    }
  }

  static void logout() => currentUser = null;
}