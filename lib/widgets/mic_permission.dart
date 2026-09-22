import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_strings.dart';
import '../models/enums.dart';
import '../services/permissions/permission_service.dart';
import '../theme/app_theme.dart';

/// Pre-permission explainer — shown BEFORE the native Android prompt.
///
/// "Let FLAME hear you" → "Allow Microphone" → native request →
/// granted / denied / permanently denied. Never crashes.
class MicPermissionScreen extends StatefulWidget {
  const MicPermissionScreen({
    super.key,
    required this.onGranted,
    required this.permissions,
    this.headline,
    this.body,
  });

  final VoidCallback onGranted;
  final PermissionService permissions;
  final String? headline;
  final String? body;

  @override
  State<MicPermissionScreen> createState() => _MicPermissionScreenState();
}

class _MicPermissionScreenState extends State<MicPermissionScreen> {
  MicPermissionState _state = MicPermissionState.unknown;
  bool _busy = false;

  Future<void> _allow() async {
    setState(() => _busy = true);
    final got = await widget.permissions.requestMicrophone();
    if (!mounted) return;
    setState(() {
      _state = got;
      _busy = false;
    });
    if (got == MicPermissionState.granted) {
      widget.onGranted();
    }
  }

  Future<void> _openSettings() async {
    await widget.permissions.openSettings();
  }

  @override
  Widget build(BuildContext context) {
    if (_state == MicPermissionState.permanentlyDenied) {
      return _card(
        icon: Icons.mic_off,
        title: 'Microphone is turned off',
        message: AppStrings.errorMicPermanentlyDenied,
        action: FilledButton.icon(
          onPressed: _openSettings,
          icon: const Icon(Icons.settings, size: 18),
          label: const Text(AppStrings.openSettings),
        ),
      );
    }
    if (_state == MicPermissionState.denied) {
      return _card(
        icon: Icons.mic_none,
        title: 'Microphone needed again',
        message: AppStrings.errorMicDenied,
        action: FilledButton.icon(
          onPressed: _allow,
          icon: const Icon(Icons.mic, size: 18),
          label: const Text('Allow Microphone'),
        ),
      );
    }
    return _card(
      icon: Icons.record_voice_over,
      title: widget.headline ?? 'Let FLAME hear you',
      message: widget.body ??
          'FLAME uses your microphone to understand classroom speech and '
              'translate it into the student\'s language.',
      action: FilledButton.icon(
        onPressed: _busy ? null : _allow,
        icon: const Icon(Icons.mic, size: 18),
        label: _busy ? const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: Colors.white,
          ),
        ) : const Text('Allow Microphone'),
      ),
    );
  }

  Widget _card({
    required IconData icon,
    required String title,
    required String message,
    required Widget action,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: FlameColors.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: FlameColors.cream,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 40, color: FlameColors.ember),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: FlameColors.ink,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: FlameColors.inkSoft),
          ),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, child: action),
        ],
      ),
    );
  }
}

/// Convenience widget that wires MicPermissionScreen to the shared service.
class MicPermissionGate extends StatelessWidget {
  const MicPermissionGate({
    super.key,
    required this.onGranted,
    this.headline,
    this.body,
  });

  final VoidCallback onGranted;
  final String? headline;
  final String? body;

  @override
  Widget build(BuildContext context) {
    final service = context.read<PermissionService>();
    return MicPermissionScreen(
      onGranted: onGranted,
      permissions: service,
      headline: headline,
      body: body,
    );
  }
}