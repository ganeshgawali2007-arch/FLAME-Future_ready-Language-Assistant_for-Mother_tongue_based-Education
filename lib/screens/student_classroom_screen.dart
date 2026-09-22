import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_strings.dart';
import '../models/enums.dart';
import '../services/classrooms/classroom_controller.dart';
import '../services/offline_status_service.dart';
import '../theme/app_theme.dart';
import '../widgets/offline_badge.dart';
import 'live_session_screen.dart';

/// Student's live classroom view.
///
/// Very simple: teacher avatar/name, live modes surfaced exactly as the
/// teacher pushes them, a big Ask FLAME button, and graceful handling when
/// the classroom disconnects or ends.
class StudentClassroomScreen extends StatefulWidget {
  const StudentClassroomScreen({super.key});

  @override
  State<StudentClassroomScreen> createState() => _StudentClassroomScreenState();
}

class _StudentClassroomScreenState extends State<StudentClassroomScreen> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 1), (_) {
      final classroom = context.read<ClassroomController>();
      if (classroom.phase == ClassroomPhase.ended) {
        _poll?.cancel();
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/summary');
        }
      }
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final classroom = context.watch<ClassroomController>();
    final offline = context.watch<OfflineStatusService>();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: FlameColors.deepEmber,
        foregroundColor: Colors.white,
        title: Text(classroom.teacherName ?? 'Classroom'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: AppStrings.leaveClass,
            onPressed: () {
              classroom.tts.stop();
              classroom.leaveClass();
              Navigator.of(context)
                  .pushNamedAndRemoveUntil('/home', (r) => false);
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 4),
            child: Row(
              children: [
                OfflineBadge(mode: offline.mode),
                const Spacer(),
                Text(
                  '${classroom.classLevel ?? ''} • ${classroom.subject ?? 'Class'}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: FlameColors.inkSoft,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: LiveSessionView(
              key: ValueKey('${classroom.classCode}-${classroom.activeMode}'),
              classroom: classroom,
              offline: offline,
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 6, 22, 14),
              child: FilledButton.icon(
                onPressed: () =>
                    Navigator.of(context).pushNamed('/ask-flame'),
                icon: const Icon(Icons.record_voice_over),
                label: const Text(AppStrings.askFlame),
              ),
            ),
          ),
        ],
      ),
    );
  }
}