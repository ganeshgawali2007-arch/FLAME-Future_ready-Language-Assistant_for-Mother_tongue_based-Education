import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repositories/flm_repository.dart';
import '../models/entities.dart';
import '../services/classrooms/classroom_controller.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/recovery_view.dart';

/// Lesson + topic selection (teacher) before creating the classroom.
class LessonSelectionScreen extends StatefulWidget {
  const LessonSelectionScreen({super.key, required this.classArgs});

  final Map<String, Object> classArgs;

  @override
  State<LessonSelectionScreen> createState() => _LessonSelectionScreenState();
}

class _LessonSelectionScreenState extends State<LessonSelectionScreen> {
  List<Lesson>? _lessons;
  Lesson? _selectedLesson;
  List<Topic> _topics = [];
  Topic? _selectedTopic;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// The repository is opened lazily as a `Future` by the router, so the
  /// provider holds a `Future<FlmRepository>`; read the future and await it.
  Future<void> _load() async {
    setState(() => _loadFailed = false);
    try {
      final repo = await context.read<Future<FlmRepository>>();
      final lessons = await repo.lessons(
        classLevel: widget.classArgs['level'] as String?,
      );
      if (!mounted) return;
      setState(() {
        _loadFailed = false;
        _lessons = lessons;
        if (lessons.isNotEmpty) _selectedLesson = lessons.first;
      });
      await _loadTopics(repo);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _lessons = null;
        _loadFailed = true;
      });
    }
  }

  Future<void> _loadTopics(FlmRepository repo) async {
    if (_selectedLesson == null) return;
    try {
      final topics = await repo.topicsFor(_selectedLesson!.id);
      if (!mounted) return;
      setState(() {
        _topics = topics;
        _selectedTopic = topics.isNotEmpty ? topics.first : null;
      });
    } catch (_) {
      // Topic look-up failure must not dead-end the flow; the lesson tile
      // stays selectable and tapping it again retries the load.
      if (!mounted) return;
      setState(() => _topics = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose the lesson')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          children: [
            Text(
              '${widget.classArgs['level']} • ${widget.classArgs['subject']}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            const Text(
              'Lesson',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            if (_loadFailed)
              RecoveryView(
                message: 'FLAME could not open the lesson library.',
                hint: 'Check the app data and tap retry.',
                onRetry: _load,
              )
            else if (_lessons == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              ..._lessons!.map(
                (l) => _OptionTile(
                  title: l.title,
                  selected: _selectedLesson?.id == l.id,
                  onTap: () async {
                    setState(() {
                      _selectedLesson = l;
                      _selectedTopic = null;
                    });
                    final repo =
                        await context.read<Future<FlmRepository>>();
                    await _loadTopics(repo);
                  },
                ),
              ),
            if (_topics.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text(
                'Topic',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              ..._topics.map(
                (t) => _OptionTile(
                  title: t.title,
                  selected: _selectedTopic?.id == t.id,
                  onTap: () => setState(() => _selectedTopic = t),
                ),
              ),
            ],
            const SizedBox(height: 28),
            FilledButton(
              onPressed: (_selectedLesson == null || _selectedTopic == null)
                  ? null
                  : () => _create(context),
              child: const Text('Create Classroom'),
            ),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }

  Future<void> _create(BuildContext context) async {
    final args = widget.classArgs;
    final app = context.read<AppState>();
    final classroom = context.read<ClassroomController>();

    classroom.teacherCreatesClass(
      name: args['name'] as String,
      level: args['level'] as String,
      subjectName: args['subject'] as String,
      teacher: app.teacherName,
      lesson: _selectedLesson!.title,
      topic: _selectedTopic!.title,
    );

    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/teacher-classroom');
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: selected ? FlameColors.readySoft : Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? FlameColors.ready : FlameColors.line,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Icon(
                  selected ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: selected ? FlameColors.ready : FlameColors.line,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}