/// Domain enums shared across FLAME.
library;

/// Who is using the app right now.
enum UserRole { teacher, student }

/// Languages FLAME currently supports.
enum AppLanguage { hindi, santhali }

/// One translation direction.
enum LanguagePair {
  hindiToSanthali('Hindi → Santhali'),
  santhaliToHindi('Santhali → Hindi');

  const LanguagePair(this.label);
  final String label;

  AppLanguage get source =>
      this == hindiToSanthali ? AppLanguage.hindi : AppLanguage.santhali;
  AppLanguage get target =>
      this == hindiToSanthali ? AppLanguage.santhali : AppLanguage.hindi;
}

/// Overall offline connection posture.
enum OfflineMode {
  /// Normal state — everything works with no internet.
  ready,

  /// Actively running an offline job (speech / translation / speech out).
  working,
}

/// Lifecycle of an offline component (speech pack, translation, voice, content).
enum EngineStatus {
  installed('Installed'),
  loading('Loading'),
  ready('Ready'),
  missing('Missing'),
  error('Error'),

  /// Component exists on the platform but FLAME has not yet probed it, so
  /// nothing is claimed. Used e.g. for the Hindi system voice before the
  /// first real check — never reported as Installed on faith.
  unverified('Needs setup');

  const EngineStatus(this.label);
  final String label;
}

/// Permissions around the microphone.
enum MicPermissionState {
  /// Not yet known (pre-check).
  unknown,

  /// The permission has never been requested on this device.
  notDetermined,

  granted,
  denied,

  /// The user answered "don't ask again" (Android permanent denial).
  permanentlyDenied
}

/// Phase of a classroom session.
enum ClassroomPhase { notCreated, waiting, live, ended }

/// Modes inside a live classroom.
enum LiveMode {
  listening('Live Listening'),
  translating('Live Translating'),
  speaking('Live Speaking');

  const LiveMode(this.label);
  final String label;
}

/// Who produced a message inside a session.
enum SpeakerRole { teacher, student, flame }

/// Progress of the Ask FLAME voice interaction.
enum VoiceBotPhase {
  idle,
  listening,
  understanding,
  answering,
  speaking,
  done,
  error;

  String get statusText => switch (this) {
        VoiceBotPhase.listening => 'Listening...',
        VoiceBotPhase.understanding => 'Understanding...',
        VoiceBotPhase.answering => 'Answering...',
        VoiceBotPhase.speaking => 'Speaking...',
        _ => '',
      };
}

/// Result of asking FLAME.
class AskFlameResult {
  AskFlameResult({
    required this.question,
    required this.answerHindi,
    required this.answerSanthali,
    required this.spokenText,
    required this.answerLevel,
    required this.fromKnowledgeBase,
  });

  final String question;
  final String answerHindi;
  final String answerSanthali;

  /// Text actually handed to the speaker (current voice packs read Hindi).
  final String spokenText;
  final String answerLevel;
  final bool fromKnowledgeBase;
}