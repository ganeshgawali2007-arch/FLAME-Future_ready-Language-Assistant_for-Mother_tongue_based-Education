import 'package:flutter/material.dart';

import '../constants/app_strings.dart';
import '../theme/app_theme.dart';

class CreateClassScreen extends StatefulWidget {
  const CreateClassScreen({super.key});

  @override
  State<CreateClassScreen> createState() => _CreateClassScreenState();
}

class _CreateClassScreenState extends State<CreateClassScreen> {
  final TextEditingController _name = TextEditingController();
  String _level = 'Class 3';
  String _subject = 'EVS';

  static const _levels = ['Class 1', 'Class 2', 'Class 3', 'Class 4', 'Class 5'];
  static const _subjects = ['EVS', 'Hindi', 'Mathematics', 'Science'];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.createClass)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          children: [
            const Text(
              'Tell us about the class',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: FlameColors.ink,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Class name',
                hintText: 'e.g. Class 3 • EVS',
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'Class',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: FlameColors.ink,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final l in _levels)
                  _ChoiceChip(
                    label: l,
                    selected: _level == l,
                    onSelected: () => setState(() => _level = l),
                  ),
              ],
            ),
            const SizedBox(height: 22),
            const Text(
              'Subject',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: FlameColors.ink,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final s in _subjects)
                  _ChoiceChip(
                    label: s,
                    selected: _subject == s,
                    onSelected: () => setState(() => _subject = s),
                  ),
              ],
            ),
            const SizedBox(height: 30),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pushNamed(
                  '/lesson-select',
                  arguments: {
                    'name': _name.text.trim().isEmpty
                        ? '$_level • $_subject'
                        : _name.text.trim(),
                    'level': _level,
                    'subject': _subject,
                  },
                );
              },
              child: const Text(AppStrings.next),
            ),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSelected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? FlameColors.ember : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? FlameColors.ember : FlameColors.line,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : FlameColors.ink,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}