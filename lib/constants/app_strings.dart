/// Single source of truth for FLAME wording.
///
/// UX rules applied here:
/// - "Offline Ready" / "Working Offline" are the ONLY offline phrasings.
/// - Offline is never presented as a failure.
/// - No technical terms (ASR / LLM / NMT / inference / model) reach children.
class AppStrings {
  AppStrings._();

  // Offline status terminology (app-wide, consistent).
  static const String offlineReady = 'Offline Ready';
  static const String workingOffline = 'Working Offline';
  static const String checkNoInternet = 'No internet needed';

  // Roles.
  static const String roleTeacher = 'Teacher';
  static const String roleStudent = 'Student';

  // Status chips used inside live sessions.
  static const String stateListening = 'Listening';
  static const String stateUnderstanding = 'Understanding';
  static const String stateTranslating = 'Translating';
  static const String stateSpeaking = 'Speaking';
  static const String stateReady = 'Ready';

  // Recovery / error messages (friendly, actionable).
  static const String errorMicRequired = 'Microphone access is required.';
  static const String errorMicDenied =
      'FLAME needs the microphone to hear you. Turn it on to continue.';
  static const String errorMicPermanentlyDenied =
      'Microphone access is turned off for FLAME. Open Android settings to allow it.';
  static const String errorSpeechNotReady =
      "The Hindi speech pack isn't ready yet.";
  static const String errorLanguagePackNotReady =
      "The Santhali language pack isn't ready.";
  static const String errorTranslationNotReady =
      'Translation isn’t available right now. Try again in a moment.';
  static const String errorTtsNotReady =
      "FLAME's voice isn't ready yet. You can still read the answer.";
  static const String errorStorage =
      'FLAME needs a little more room to save lessons. Please free some space.';
  static const String errorPlayback = 'Couldn\'t play the audio. Try again.';
  static const String errorStudentLost =
      'Student connection lost. Waiting to reconnect...';
  static const String errorTeacherLost =
      'Classroom connection lost. Waiting to reconnect...';
  static const String errorModelLoad =
      'Some lesson content took too long to open. Let\'s try again.';
  static const String errorClassEnded =
      'This class has ended. Your summary is ready.';

  // Waiting room.
  static const String waitingTitle = 'Waiting for your teacher to start...';
  static const String waitingConnected = 'Connected Offline';
  static const String leaveClass = 'Leave Class';

  // Ask FLAME.
  static const String askFlame = 'Ask FLAME';
  static const String askFlameSubtitle = 'Ask anything about your lesson.';
  static const String tapAndSpeak = 'Tap and Speak';
  static const String yourQuestion = 'Your Question';
  static const String listenBack = 'Listen';
  static const String replay = 'Replay';
  static const String askAgain = 'Ask Again';
  static const String newQuestion = 'New Question';
  static const String backToLesson = 'Back to Lesson';
  static const String typeQuestion = 'Type your question';

  // General actions.
  static const String retry = 'Try Again';
  static const String gotIt = 'Got it';
  static const String continueButton = 'Continue';
  static const String openSettings = 'Open Settings';
  static const String startClass = 'Start Class';
  static const String endClass = 'End Class';
  static const String createClass = 'Create Class';
  static const String joinClass = 'Join Class';
  static const String settings = 'Settings';
  static const String back = 'Back';
  static const String next = 'Next';

  static const String appName = 'FLAME';
  static const String appTagline =
      'Learn in your language, even without internet.';
}