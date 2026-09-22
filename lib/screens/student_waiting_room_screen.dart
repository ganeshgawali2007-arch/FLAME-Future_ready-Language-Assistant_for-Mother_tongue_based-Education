import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_strings.dart';
import '../models/enums.dart';
import '../services/classrooms/classroom_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/offline_badge.dart';
import '../widgets/waiting_pulse.dart';

/// Student waiting room.
///
/// Faithful to spec:
///   Teacher: {teacher}
///   Class:   {level} • {subject}
///   🟢 Connected Offline
///   "Waiting for your teacher to start..."
///   subtle pulse animation + a single "Leave Class" action.
class StudentWaitingRoomScreen extends StatefulWidget {
  const StudentWaitingRoomScreen({super.key});

  @override
  State<StudentWaitingRoomScreen> createState() =>
      _StudentWaitingRoomScreenState();
}

class _StudentWaitingRoomScreenState extends State<StudentWaitingRoomScreen> {
  Timer? _poll;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    // Watch for the teacher starting the class (offline broker).
    _poll = Timer.periodic(const Duration(seconds: 1), (_) {
      final classroom = context.read<ClassroomController>();
      if (classroom.isLive && classroom.phase == ClassroomPhase.live) {
        _poll?.cancel();
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/student-classroom');
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

    return Scaffold(
      appBar: AppBar(
        backgroundColor: FlameColors.deepEmber,
        foregroundColor: Colors.white,
        title: const Text('Classroom'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              const Align(
                alignment: Alignment.centerLeft,
                child: OfflineBadge(),
              ),
              const Spacer(),
              const Center(child: WaitingPulse()),
              const SizedBox(height: 30),
              Text(
                classroom.teacherName ?? 'Teacher',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: FlameColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${classroom.classLevel ?? ''} • ${classroom.subject ?? ''}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: FlameColors.inkSoft,
                ),
              ),
              const SizedBox(height: 16),
              const Center(
                child: _ConnectedOfflinePill(),
              ),
              const SizedBox(height: 20),
              Text(
                AppStrings.waitingTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: FlameColors.ink,
                ),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: _leaving
                    ? null
                    : () async {
                        final nav = Navigator.of(context);
                        final classroom =
                            context.read<ClassroomController>();
                        setState(() => _leaving = true);
                        await classroom.tts.stop();
                        if (!mounted) return;
                        classroom.leaveClass();
                        nav.pushNamedAndRemoveUntil('/home', (r) => false);
                      },
                child: const Text(AppStrings.leaveClass),
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectedOfflinePill extends StatelessWidget {
  const _ConnectedOfflinePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: FlameColors.readySoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, color: FlameColors.ready, size: 10),
          SizedBox(width: 8),
          Text(
            '🟢 Connected Offline',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: FlameColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}