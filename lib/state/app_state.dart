/// Global app state shared by all screens.
///
/// Owns role, onboarding, persisted name, and the shared services (SQLite
/// repository, translation engine, TTS, model manager, offline status).
/// Shared services are created lazily per screen where possible so memory on
/// 2–4 GB devices stays small (register/ask-flame load their own engines).
library;

import 'package:flutter/foundation.dart';

import '../models/enums.dart';

class AppState extends ChangeNotifier {
  AppState();

  bool _onboarded = false;
  UserRole? _role;
  String _teacherName = 'Priya Ma\'am';
  String _studentName = '';
  LanguagePair _pair = LanguagePair.hindiToSanthali;

  bool get onboarded => _onboarded;
  UserRole? get role => _role;
  String get teacherName => _teacherName;
  String get studentName => _studentName;
  LanguagePair get pair => _pair;

  void completeOnboarding() {
    _onboarded = true;
    notifyListeners();
  }

  void setRole(UserRole role) {
    _role = role;
    notifyListeners();
  }

  void setTeacherName(String name) {
    _teacherName = name;
    notifyListeners();
  }

  void setStudentName(String name) {
    _studentName = name;
    notifyListeners();
  }

  void setPair(LanguagePair pair) {
    _pair = pair;
    notifyListeners();
  }
}