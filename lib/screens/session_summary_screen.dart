import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/classrooms/classroom_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/offline_badge.dart';

/// Session summary shown after the teacher ends the class.
///
/// Pure on-device statistics from the local transcript + student list.
class SessionSummaryScreen extends StatelessWidget {
  const SessionSummaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final classroom = context.watch<ClassroomController>();

    final turns = classroom.transcript;
    final teacherTurns =
        turns.where((u) => u.speaker.index == 0).length;
    final studentTurns =
        turns.where((u) => u.speaker.index == 1).length;
    final joined = classroom.joinedStudents.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session Complete'),
        backgroundColor: FlameColors.deepEmber,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const OfflineBadge(),
            const SizedBox(height: 28),
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: FlameColors.flameGradient,
              ),
              child: const Icon(Icons.emoji_events, color: Colors.white, size: 46),
            ),
            const SizedBox(height: 18),
            const Text(
              'Great class, everyone!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: FlameColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${classroom.className ?? 'Class'} • ${classroom.lessonTitle}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: FlameColors.inkSoft),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                _StatCard(icon: Icons.groups, value: '$joined', label: 'students'),
                const SizedBox(width: 12),
                _StatCard(icon: Icons.record_voice_over, value: '$teacherTurns', label: 'teacher lines'),
                const SizedBox(width: 12),
                _StatCard(icon: Icons.child_care, value: '$studentTurns', label: 'student lines'),
              ],
            ),
            const SizedBox(height: 28),
            const Text(
              'Everything was translated offline.',
              style: TextStyle(fontSize: 14, color: FlameColors.inkSoft),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                Navigator.of(context)
                    .pushNamedAndRemoveUntil('/home', (r) => false);
              },
              child: const Text('Done'),
            ),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: FlameColors.line),
        ),
        child: Column(
          children: [
            Icon(icon, color: FlameColors.ember),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: FlameColors.ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                color: FlameColors.inkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}