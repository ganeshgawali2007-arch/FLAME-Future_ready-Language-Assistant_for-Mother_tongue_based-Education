/// Consistent offline posture for the whole app.
///
/// Two states only:
///   - [OfflineMode.ready]   – "Offline Ready"
///   - [OfflineMode.working] – "Working Offline"
///
/// Absence of internet is *expected*; it is never surfaced as an error.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/enums.dart';

class OfflineStatusService extends ChangeNotifier {
  OfflineStatusService();

  OfflineMode _mode = OfflineMode.ready;
  int _activeJobs = 0;

  OfflineMode get mode => _mode;

  /// Begin an offline processing job (e.g. speech -> translation -> speech).
  void startJob() {
    _activeJobs += 1;
    if (_activeJobs > 0 && _mode != OfflineMode.working) {
      _mode = OfflineMode.working;
      notifyListeners();
    }
  }

  /// Finish an offline processing job.
  void endJob() {
    if (_activeJobs > 0) _activeJobs -= 1;
    if (_activeJobs == 0 && _mode != OfflineMode.ready) {
      _mode = OfflineMode.ready;
      notifyListeners();
    }
  }

  /// Runs [job], toggling the app-wide offline state around it.
  Future<T> runOfflineJob<T>(Future<T> Function() job) async {
    startJob();
    try {
      return await job();
    } finally {
      endJob();
    }
  }
}