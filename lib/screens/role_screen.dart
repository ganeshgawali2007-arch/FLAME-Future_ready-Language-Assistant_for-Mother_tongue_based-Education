import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_strings.dart';
import '../models/enums.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

class RoleScreen extends StatelessWidget {
  const RoleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Who are you?')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              const Text(
                'Choose how you will use FLAME',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: FlameColors.ink,
                ),
              ),
              const SizedBox(height: 24),
              _RoleCard(
                icon: Icons.school_outlined,
                label: AppStrings.roleTeacher,
                caption: 'Create classes, lead lessons, speak and translate.',
                gradient: FlameColors.flameGradient,
                onTap: () {
                  app.setRole(UserRole.teacher);
                  Navigator.of(context).pushNamed('/language');
                },
              ),
              const SizedBox(height: 16),
              _RoleCard(
                icon: Icons.child_care_outlined,
                label: AppStrings.roleStudent,
                caption: 'Join your class, listen, answer and ask FLAME.',
                gradient:
                    const LinearGradient(colors: [FlameColors.amber, FlameColors.flame]),
                onTap: () {
                  app.setRole(UserRole.student);
                  Navigator.of(context).pushNamed('/language');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.label,
    required this.caption,
    required this.gradient,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String caption;
  final Gradient gradient;
  final VoidCallback onTap;

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
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  gradient: gradient,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: Colors.white, size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: FlameColors.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      caption,
                      style: const TextStyle(
                        fontSize: 13,
                        color: FlameColors.inkSoft,
                        height: 1.35,
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