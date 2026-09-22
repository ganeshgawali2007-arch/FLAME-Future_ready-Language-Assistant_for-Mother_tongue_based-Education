/// Microphone permission orchestration.
///
/// Talks to the host Activity over a small MethodChannel (`flame/permissions`)
/// so the three outcome states (granted / denied / permanently denied) are
/// reported deterministically on Android and none of the request flow depends
/// on a third-party plugin. Never throws; falls back to a safe `denied`.
library;

import 'package:flutter/services.dart';

import '../../models/enums.dart';

class PermissionService {
  static const MethodChannel _channel = MethodChannel('flame/permissions');

  Future<MicPermissionState> requestMicrophone() => _invoke('requestMicrophone');

  Future<MicPermissionState> checkMicrophone() => _invoke('checkMicrophone');

  Future<bool> openSettings() async {
    try {
      await _channel.invokeMethod<void>('openAppSettings');
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<MicPermissionState> _invoke(String method) async {
    try {
      final value = await _channel.invokeMethod<String>(method);
      return switch (value) {
        'granted' => MicPermissionState.granted,
        'permanentlyDenied' => MicPermissionState.permanentlyDenied,
        'notDetermined' => MicPermissionState.notDetermined,
        _ => MicPermissionState.denied,
      };
    } catch (_) {
      return MicPermissionState.denied;
    }
  }
}