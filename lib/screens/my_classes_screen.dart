import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/enums.dart';
import '../services/classrooms/classroom_controller.dart';
import '../theme/app_theme.dart';

/// Teacher's recent sessions list (from local SQLite history), with an entry
/// to resume the current session or start a fresh one.
class MyClassesScreen extends StatelessWidget {
  const MyClassesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final classroom = context.watch<ClassroomController>();

    return Scaffold(
      appBar: AppBar(title: const Text('My Classes')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (classroom.classCode != null &&
                classroom.phase != ClassroomPhase.notCreated) ...[
              _activeCard(context, classroom),
              const SizedBox(height: 20),
            ],
            const Text(
              'Start a new class',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pushNamed('/create-class'),
              icon: const Icon(Icons.add),
              label: const Text('Create Class'),
            ),
            const SizedBox(height: 24),
            const Text(
              'History',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            if (classroom.phase == ClassroomPhase.ended)
              _historyTile(
                classroom.classCode!,
                '${classroom.className} • ${classroom.lessonTitle}',
              )
            else
              const Text(
                'Finished classes will appear here.',
                style: TextStyle(color: FlameColors.inkSoft),
              ),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }

  Widget _activeCard(BuildContext context, ClassroomController classroom) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: FlameColors.flameGradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Active now',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            classroom.className ?? '',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Code: ${classroom.classCode}',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.white),
                  onPressed: () => Navigator.of(context)
                      .pushReplacementNamed('/teacher-classroom'),
                  child: const Text('Resume', style: TextStyle(color: FlameColors.ember)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _historyTile(String code, String title) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: FlameColors.line),
      ),
      child: Row(
        children: [
          const Icon(Icons.history, color: FlameColors.inkSoft),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}