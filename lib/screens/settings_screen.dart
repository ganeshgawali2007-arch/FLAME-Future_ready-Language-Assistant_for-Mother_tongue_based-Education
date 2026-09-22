import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_strings.dart';
import '../models/enums.dart';
import '../services/model_manager.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/offline_badge.dart';

/// Settings — shows the consistent offline indicator and the honest status of
/// every offline component (ModelManager): Ready / Missing / Loading / Error.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final models = context.watch<ModelManagerController>();
    final app = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.settings)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const OfflineBadge(),
            const SizedBox(height: 6),
            const Text(
              'FLAME never needs the internet. Everything you see here '
              'is saved on this phone.',
              style: TextStyle(fontSize: 13, color: FlameColors.inkSoft),
            ),
            const SizedBox(height: 24),
            const Text(
              'Offline packs',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            ...FlmModelId.values.map((id) {
              final m = models.infoFor(id);
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: FlameColors.line),
                ),
                child: Row(
                  children: [
                    _stateIcon(m.state),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: FlameColors.ink,
                            ),
                          ),
                          if (m.storageRequiredMb != null &&
                              m.state != EngineStatus.ready &&
                              m.state != EngineStatus.installed)
                            Text(
                              'Needs ${m.storageRequiredMb} MB of free space to add.',
                              style: const TextStyle(
                                fontSize: 12,
                                color: FlameColors.inkSoft,
                              ),
                            ),
                          if (m.detail != null)
                            Text(
                              m.detail!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: FlameColors.inkSoft,
                              ),
                            ),
                          if (m.packPresent != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                m.packPresent!
                                    ? 'Pack on device: present'
                                    : 'Pack on device: absent',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: m.packPresent!
                                      ? FlameColors.ready
                                      : FlameColors.inkSoft,
                                ),
                              ),
                            ),
                          if (m.probeNote != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                'Probe: ${m.probeNote}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: FlameColors.error,
                                ),
                              ),
                            ),
                          if ((m.state == EngineStatus.missing ||
                              m.state == EngineStatus.unverified) &&
                              models.hasInstallChecker(id))
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: OutlinedButton.icon(
                                onPressed: () => models.recheckInstall(id),
                                icon: const Icon(Icons.refresh, size: 16),
                                label: const Text('Check'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: FlameColors.ember,
                                  side: const BorderSide(
                                      color: FlameColors.ember),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  textStyle: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    _stateLabel(m.state),
                  ],
                ),
              );
            }),
            const SizedBox(height: 8),
            const Text(
              'Language',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            _SettingTile(
              icon: Icons.translate,
              title: 'Direction',
              value: app.pair.label,
            ),
            const SizedBox(height: 12),
            _SettingTile(
              icon: Icons.person_outline,
              title: 'Teacher name',
              value: app.teacherName,
            ),
            const SizedBox(height: 24),
            Text(
              'Storage used: bundled content • ${models.totalStorageRequiredMb()} MB available to add later',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: FlameColors.inkSoft),
            ),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }

  Widget _stateIcon(EngineStatus s) {
    final (color, icon) = switch (s) {
      EngineStatus.ready || EngineStatus.installed =>
        (FlameColors.ready, Icons.check_circle),
      EngineStatus.loading => (FlameColors.amber, Icons.hourglass_top),
      EngineStatus.unverified =>
        (FlameColors.amber, Icons.help_outline),
      EngineStatus.error => (FlameColors.error, Icons.error_outline),
      _ => (FlameColors.inkSoft, Icons.cloud_off),
    };
    return Icon(icon, color: color, size: 24);
  }

  Widget _stateLabel(EngineStatus s) {
    final color = switch (s) {
      EngineStatus.ready || EngineStatus.installed => FlameColors.ready,
      EngineStatus.loading => FlameColors.amber,
      EngineStatus.unverified => FlameColors.amber,
      EngineStatus.error => FlameColors.error,
      _ => FlameColors.inkSoft,
    };
    return Text(
      switch (s) {
        EngineStatus.unverified => '⚠ Needs setup',
        EngineStatus.ready || EngineStatus.installed => '✓ ${s.label}',
        _ => s.label,
      },
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: FlameColors.line),
      ),
      child: Row(
        children: [
          Icon(icon, color: FlameColors.ember, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Text(value, style: const TextStyle(color: FlameColors.inkSoft)),
        ],
      ),
    );
  }
}