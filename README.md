<div align="center">

# FLAME

**Future-ready Language Assistant for Mother-tongue based Education**

An offline-first Android app that helps teachers and students in primary classrooms translate between **Hindi** and **Santali (Ol Chiki)**, using on-device speech recognition and neural machine translation.

</div>

## ✨ Features

- 🔁 **Hindi ↔ Santali / Ol Chiki** offline neural translation
- 🎙️ **Speech-to-text** (offline Vosk model for Hindi)
- 📚 **FLN classroom lexicon** — grade/subject/category tagged phrases for teachers
- 📖 **Story-book / PDF reader** rendering on device
- 📷 **Barcode scanning** (ML Kit)
- 🌐 **No internet required** — all AI models ship inside the APK

## 📦 Download

> APK only — no build required. Grab the latest release below and sideload it (enable *Install unknown apps* on Android).

| Version | Package | Min Android |
|--------:|---------|-------------|
| [v1.0.0 · FLAME-v1.0.0.apk][release] | `com.flame.flame` | Android 7.0 (API 24) |

[release]: https://github.com/ganeshgawali2007-arch/FLAME-Future_ready-Language-Assistant_for-Mother_tongue_based-Education/releases/latest

## 🛠️ Tech Stack

<p align="center">
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white">
  <img alt="Dart" src="https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white">
  <img alt="Android" src="https://img.shields.io/badge/Android-3DDC84?style=for-the-badge&logo=android&logoColor=white">
  <img alt="ONNX Runtime" src="https://img.shields.io/badge/ONNX%20Runtime-005CED?style=for-the-badge&logo=onnx&logoColor=white">
  <img alt="Vosk Offline Speech" src="https://img.shields.io/badge/Vosk%20Offline%20STT-6C5CE7?style=for-the-badge&logo=speakerdeck&logoColor=white">
  <img alt="ML Kit" src="https://img.shields.io/badge/Google%20ML%20Kit-4285F4?style=for-the-badge&logo=google&logoColor=white">
  <img alt="SQLite" src="https://img.shields.io/badge/SQLite-003B57?style=for-the-badge&logo=sqlite&logoColor=white">
  <img alt="PDFium" src="https://img.shields.io/badge/PDFium-EB4522?style=for-the-badge&logo=adobeacrobatreader&logoColor=white">
  <img alt="License MIT" src="https://img.shields.io/badge/License-MIT-green.svg?style=for-the-badge">
</p>

| Component | Used for |
|-----------|----------|
| Flutter / Dart | Cross-platform UI & application logic |
| ONNX Runtime | On-device neural machine translation engine |
| Vosk | Offline speech-to-text (Hindi) |
| ML Kit Barcode | Barcode / QR scanning |
| PDFium | Embedded story-book PDF rendering |
| SQLite | Local data storage |

## 🚀 Getting Started

1. Install **Flutter** (stable channel).
2. Clone this repo:
   ```bash
   git clone https://github.com/ganeshgawali2007-arch/FLAME-Future_ready-Language-Assistant_for-Mother_tongue_based-Education.git
   ```
3. Run on a connected device / emulator:
   ```bash
   flutter pub get
   flutter run
   ```

## 🤝 Contributing

Please open an [issue](https://github.com/ganeshgawali2007-arch/FLAME-Future_ready-Language-Assistant_for-Mother_tongue_based-Education/issues) for bugs, feature requests, or improvements.

## 📄 License

Distributed under the [MIT License](LICENSE).