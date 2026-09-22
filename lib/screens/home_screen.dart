import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_strings.dart';
import '../models/enums.dart';
import '../services/offline_status_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/offline_badge.dart';

/// Role-aware home. Teacher: control-oriented. Student: very simple.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final isTeacher = app.role == UserRole.teacher;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [FlameColors.cream, Color(0xFFFFF1DE)],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
            children: [
              Row(
                children: [
                  const OfflineBadge(),
                  const Spacer(),
                  IconButton(
                    tooltip: AppStrings.settings,
                    onPressed: () =>
                        Navigator.of(context).pushNamed('/settings'),
                    icon: const Icon(
                      Icons.settings_outlined,
                      color: FlameColors.ink,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: FlameColors.flameGradient,
                    ),
                    child: Icon(
                      isTeacher ? Icons.person : Icons.child_care,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isTeacher
                              ? 'Hello, ${app.teacherName}'
                              : 'Hello, ${_studentGreeting(app)}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: FlameColors.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isTeacher
                              ? 'Your class is ready anytime.'
                              : 'Pick a classroom to continue.',
                          style: const TextStyle(
                            fontSize: 13,
                            color: FlameColors.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              if (isTeacher) ...[
                _ActionCard(
                  icon: Icons.add_circle,
                  title: AppStrings.createClass,
                  caption: 'New class, new code',
                  onTap: () => Navigator.of(context).pushNamed('/create-class'),
                ),
                const SizedBox(height: 14),
                _ActionCard(
                  icon: Icons.folder_open,
                  title: 'My Classes',
                  caption: 'Recent sessions',
                  onTap: () => Navigator.of(context).pushNamed('/my-classes'),
                ),
                _SpaceReviewHint(),
              ] else ...[
                _ActionCard(
                  icon: Icons.group_add,
                  title: AppStrings.joinClass,
                  caption: 'Enter your class code',
                  onTap: () => Navigator.of(context).pushNamed('/join'),
                ),
                const SizedBox(height: 14),
                _ActionCard(
                  icon: Icons.record_voice_over,
                  title: AppStrings.askFlame,
                  caption: 'Ask anything about your lesson',
                  onTap: () => Navigator.of(context).pushNamed('/ask-flame'),
                  gradient: const LinearGradient(
                    colors: [FlameColors.amber, FlameColors.flame],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _studentGreeting(AppState app) =>
      app.studentName.isEmpty ? 'Student' : app.studentName;
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.caption,
    required this.onTap,
    this.gradient,
  });

  final IconData icon;
  final String title;
  final String caption;
  final VoidCallback onTap;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: FlameColors.line),
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  gradient: gradient ?? FlameColors.flameGradient,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: FlameColors.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      caption,
                      style: const TextStyle(
                        fontSize: 13,
                        color: FlameColors.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: FlameColors.inkSoft),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpaceReviewHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final offline = context.watch<OfflineStatusService>();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          const Icon(Icons.wifi_off, size: 16, color: FlameColors.inkSoft),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              offline.mode == OfflineMode.ready
                  ? 'Classroom works with Wi-Fi and mobile data off.'
                  : 'Working offline right now...',
              style: const TextStyle(
                fontSize: 12,
                color: FlameColors.inkSoft,
              ),
            ),
          ),
        ],
      ),
    );
  }
}