import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_strings.dart';
import '../models/enums.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final isTeacher = app.role == UserRole.teacher;
    return Scaffold(
      appBar: AppBar(title: const Text('Your language')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 8),
          children: [
            const Text(
              'FLAME works in your language',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: FlameColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isTeacher
                  ? 'आप हिंदी में बोलेंगे और कक्षा संथाली में सुनेगी।'
                  : 'आप संथाली में सीखेंगे और सवाल का जवाब देंगे।',
              style: const TextStyle(fontSize: 14, color: FlameColors.inkSoft),
            ),
            const SizedBox(height: 24),
            _PairTile(
              pair: LanguagePair.hindiToSanthali,
              selected: app.pair == LanguagePair.hindiToSanthali,
              onTap: () => app.setPair(LanguagePair.hindiToSanthali),
            ),
            const SizedBox(height: 12),
            _PairTile(
              pair: LanguagePair.santhaliToHindi,
              selected: app.pair == LanguagePair.santhaliToHindi,
              onTap: () => app.setPair(LanguagePair.santhaliToHindi),
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pushNamed('/offline-setup');
              },
              child: const Text(AppStrings.continueButton),
            ),
          ],
        ),
      ),
    );
  }
}

class _PairTile extends StatelessWidget {
  const _PairTile({
    required this.pair,
    required this.selected,
    required this.onTap,
  });

  final LanguagePair pair;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? FlameColors.readySoft : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? FlameColors.ready : FlameColors.line,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: FlameColors.cream,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.translate,
                  color: FlameColors.ember,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  pair.label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: FlameColors.ink,
                  ),
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle, color: FlameColors.ready)
              else
                const Icon(Icons.circle_outlined, color: FlameColors.line),
            ],
          ),
        ),
      ),
    );
  }
}