import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../constants/app_strings.dart';
import '../services/classrooms/classroom_controller.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/recovery_view.dart';

class JoinClassroomScreen extends StatefulWidget {
  const JoinClassroomScreen({super.key});

  @override
  State<JoinClassroomScreen> createState() => _JoinClassroomScreenState();
}

class _JoinClassroomScreenState extends State<JoinClassroomScreen> {
  final TextEditingController _code = TextEditingController();
  bool _scanning = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join(String code) async {
    final classroom = context.read<ClassroomController>();
    final app = context.read<AppState>();
    final studentName = app.studentName.isEmpty ? 'Student' : app.studentName;
    var ok = classroom.studentJoins(code, studentName: studentName);
    if (!ok) {
      // Not a same-device session — try a real LAN-hosted classroom.
      final remote = await classroom.studentJoinsRemote(
        code,
        studentName: studentName,
      );
      ok = remote ?? false;
    }
    if (!ok) {
      setState(() {
        _scanning = false;
        _error = 'We couldn\'t find that class code. Check with your teacher.';
      });
      return;
    }
    if (!mounted) return;
    Navigator.of(context)
        .pushReplacementNamed('/student-waiting');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.joinClass)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          children: [
            const Text(
              'Enter your class code',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: FlameColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Your teacher shares this code or a QR picture.',
              style: TextStyle(fontSize: 14, color: FlameColors.inkSoft),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: 6,
              ),
              decoration: const InputDecoration(
                hintText: 'ABC123',
                hintStyle: TextStyle(letterSpacing: 0, fontSize: 20),
              ),
              onSubmitted: _join,
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              RecoveryView(
                message: _error!,
                onRetry: () => setState(() => _error = null),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                final code = _code.text.trim();
                if (code.isNotEmpty) _join(code);
              },
              child: const Text('Join Class'),
            ),
            const SizedBox(height: 22),
            const Row(
              children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('or', style: TextStyle(color: FlameColors.inkSoft)),
                ),
                Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _error = null;
                  _scanning = !_scanning;
                });
              },
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan QR code'),
            ),
            if (_scanning) ...[
              const SizedBox(height: 16),
              Container(
                height: 260,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: FlameColors.ember, width: 2),
                ),
                clipBehavior: Clip.antiAlias,
                child: MobileScanner(
                  onDetect: (capture) {
                    final raw = capture.barcodes
                        .map((b) => b.rawValue ?? '')
                        .where((v) => v.startsWith('FLAME:'))
                        .map((v) => v.substring(6))
                        .toList();
                    if (raw.isNotEmpty) {
                      _join(raw.first);
                    }
                  },
                ),
              ),
            ],
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }
}