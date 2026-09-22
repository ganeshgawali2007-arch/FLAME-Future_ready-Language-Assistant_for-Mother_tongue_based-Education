import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../constants/app_strings.dart';
import '../models/enums.dart';
import '../services/classrooms/classroom_controller.dart';
import '../services/offline_status_service.dart';
import '../theme/app_theme.dart';
import '../widgets/offline_badge.dart';
import '../widgets/recovery_view.dart';
import 'live_session_screen.dart';

/// Teacher classroom — control oriented.
///
/// Phase waiting: class code + QR for students, joined list, Start Class.
/// Phase live:    mode control (Listening / Translating / Speaking),
///                live transcript, End Class.
/// Phase ended:   session summary.
class TeacherClassroomScreen extends StatelessWidget {
  const TeacherClassroomScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final classroom = context.watch<ClassroomController>();
    final offline = context.watch<OfflineStatusService>();

    return Scaffold(
      appBar: AppBar(
        title: Text(classroom.className ?? AppStrings.createClass),
        backgroundColor: FlameColors.deepEmber,
        foregroundColor: Colors.white,
        actions: [
          if (classroom.isLive)
            TextButton(
              onPressed: () => _end(context, classroom),
              child: const Text(
                AppStrings.endClass,
                style: TextStyle(color: Colors.white),
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: switch (classroom.phase) {
        ClassroomPhase.notCreated => const _NoClass(),
        ClassroomPhase.waiting => _WaitingView(
            classroom: classroom,
            offline: offline,
          ),
        ClassroomPhase.live => _LiveControlView(
            classroom: classroom,
            offline: offline,
          ),
        ClassroomPhase.ended => const _EndedView(),
      },
    );
  }

  Future<void> _end(BuildContext context, ClassroomController classroom) async {
    await classroom.tts.stop();
    if (!context.mounted) return;
    classroom.endClass();
    Navigator.of(context).pushNamed('/summary');
  }
}

class _NoClass extends StatelessWidget {
  const _NoClass();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: RecoveryView(
        message: 'No active class. Please create a class first.',
        onRetry: () => Navigator.of(context).pushNamed('/create-class'),
      ),
    );
  }
}

class _WaitingView extends StatelessWidget {
  const _WaitingView({required this.classroom, required this.offline});

  final ClassroomController classroom;
  final OfflineStatusService offline;

  @override
  Widget build(BuildContext context) {
    final code = classroom.classCode ?? '------';
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const OfflineBadge(),
        const SizedBox(height: 20),
        Text(
          '${classroom.classLevel} • ${classroom.subject}',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: FlameColors.inkSoft,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          classroom.lessonTitle,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: FlameColors.ink,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Topic: ${classroom.topicTitle}',
          style: const TextStyle(fontSize: 14, color: FlameColors.inkSoft),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: FlameColors.line),
          ),
          child: Column(
            children: [
              const Text(
                'Share this code with your class',
                style: TextStyle(fontSize: 14, color: FlameColors.inkSoft),
              ),
              const SizedBox(height: 10),
              Text(
                code,
                style: const TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 6,
                  color: FlameColors.ember,
                ),
              ),
              const SizedBox(height: 18),
              QrImageView(
                data: 'FLAME:$code',
                version: QrVersions.auto,
                size: 170,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: FlameColors.ember,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: FlameColors.deepEmber,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Or scan this QR code to join',
                style: TextStyle(fontSize: 13, color: FlameColors.inkSoft),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _StudentsRow(students: classroom.joinedStudents),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => classroom.startClass(),
          child: const Text(AppStrings.startClass),
        ),
        const SizedBox(height: 28),
      ],
    );
  }
}

class _StudentsRow extends StatelessWidget {
  const _StudentsRow({required this.students});

  final List<String> students;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FlameColors.cream,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.group, color: FlameColors.ember),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              students.isEmpty
                  ? 'No students joined yet — they are still on the way.'
                  : '${students.length} student${students.length == 1 ? '' : 's'} joined: '
                      '${students.join(', ')}',
              style: const TextStyle(fontSize: 14, color: FlameColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveControlView extends StatelessWidget {
  const _LiveControlView({required this.classroom, required this.offline});

  final ClassroomController classroom;
  final OfflineStatusService offline;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Row(
            children: [
              OfflineBadge(mode: offline.mode),
              const Spacer(),
              Text(
                classroom.classCode ?? '',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  color: FlameColors.ember,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              Expanded(
                child: _ModeButton(
                  liveMode: LiveMode.listening,
                  classroom: classroom,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ModeButton(
                  liveMode: LiveMode.translating,
                  classroom: classroom,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ModeButton(
                  liveMode: LiveMode.speaking,
                  classroom: classroom,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: LiveSessionView(
            key: ValueKey(classroom.activeMode),
            classroom: classroom,
            offline: offline,
          ),
        ),
      ],
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({required this.liveMode, required this.classroom});

  final LiveMode liveMode;
  final ClassroomController classroom;

  @override
  Widget build(BuildContext context) {
    final selected = classroom.activeMode == liveMode;
    return GestureDetector(
      onTap: () => classroom.setMode(liveMode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? FlameColors.ember : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? FlameColors.ember : FlameColors.line,
          ),
        ),
        child: Column(
          children: [
            Icon(
              _icon(liveMode),
              color: selected ? Colors.white : FlameColors.inkSoft,
              size: 22,
            ),
            const SizedBox(height: 4),
            Text(
              liveMode.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : FlameColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _icon(LiveMode mode) => switch (mode) {
        LiveMode.listening => Icons.hearing,
        LiveMode.translating => Icons.translate,
        LiveMode.speaking => Icons.mic,
      };
}

class _EndedView extends StatelessWidget {
  const _EndedView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.flag, size: 48, color: FlameColors.ember),
          SizedBox(height: 12),
          Text('Class ended', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          SizedBox(height: 6),
          Text('Your summary is ready.', style: TextStyle(color: FlameColors.inkSoft)),
        ],
      ),
    );
  }
}