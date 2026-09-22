# FLAME — Future-ready Language Assistant for Mother-tongue based Education

> **Smart India Hackathon 2026 — Team ForestFlame**
> **Problem Statement 26042: AI-Powered Vernacular Pedagogy and Real-Time Translation Tool for Mother Tongue-Based Primary Education**
> Package `com.flame.flame` · Version `1.0.0+1` · Android 7.0+ (API 24) · Offline-first · 2GB+ RAM tablets

<div align="center">

An offline-first Android app that helps teachers and students in primary classrooms translate between **Hindi** and **Santali (Ol Chiki)**, using on-device speech recognition and neural machine translation.

Teacher hosts a class on one phone, students join from their phones over the same Wi-Fi / hotspot — no internet, no cloud.

</div>

## ✨ Features

- 🔁 **Hindi ↔ Santali / Ol Chiki** offline translation (phrase cache + IndicTrans2 INT8 ONNX)
- 🎙️ **Speech-to-text** (offline Vosk Hindi `small-hi-0.22`)
- 🔊 **Speech-out** (Hindi system TTS + Santhali Piper VITS voice, never substituted)
- 🏫 **Live classroom**: teacher Create → code + `FLAME:CODE` QR → waiting → live → summary; student Join by code / scan → waiting → live
- 📚 **FLN classroom lexicon** — `assets/fln/corpus_pairs.json` + `fln_lexicon.json`
- 📷 **QR / barcode scanning** (`qr_flutter` + `mobile_scanner`)
- 🌐 **No internet required** — ASR/NMT/TTS run on-device; LAN text-only sync
- 🔤 **Ol Chiki rendering** — bundled `NotoSansOlChiki.ttf`

## 📦 Download

> APK only — no build required. Sideload it (enable *Install unknown apps*).

| Version | Package | Min Android |
|--------:|---------|-------------|
| [v1.0.0 · FLAME-v1.0.0.apk][release] | `com.flame.flame` | Android 7.0 (API 24) |

[release]: https://github.com/ganeshgawali2007-arch/FLAME-Future_ready-Language-Assistant_for-Mother_tongue_based-Education/releases/latest

## 🛠️ Tech Stack

| Component | Used for |
|-----------|----------|
| Flutter / Dart 3.13 | UI + app logic (`lib/`, `provider`, 17 screens) |
| ONNX Runtime | On-device NMT (IndicTrans2 `indic-indic-dist-320M` INT8) |
| Vosk | Offline Hindi STT (`assets/models/vosk-model-small-hi-0.22.zip`, 44.5 MB) |
| Piper VITS / flutter_tts | Santhali neural voice + Hindi system voice |
| SQLite (`sqflite`) | Lessons, knowledge base, sessions (local only) |
| QR (`qr_flutter` / `mobile_scanner`) | `FLAME:<CODE>` class join |
| `connectivity_plus`, `record` | LAN status, mic capture |

Native bridges: `MainActivity.kt`, `VoskAsrSession.kt`, `OnnxNmtSession.kt`, `SatTtsSession.kt` in `android/app/src/main/kotlin/com/flame/flame/`.

## 🚀 Getting Started

1. Install **Flutter** (stable, SDK `^3.13.3`).
2. Clone:
   ```bash
   git clone https://github.com/ganeshgawali2007-arch/FLAME-Future_ready-Language-Assistant_for-Mother_tongue_based-Education.git
   cd FLAME-Future_ready-Language-Assistant_for-Mother_tongue_based-Education
   ```
3. Run:
   ```bash
   flutter pub get
   flutter analyze
   flutter test
   flutter run
   ```
4. Release:
   ```bash
   flutter build apk --release --split-per-abi   # lean per-device
   flutter build apk --release                   # fat APK
   ```

## 📦 Models — what ships vs side-load

| Pack | Status in this repo | Size | Install |
|------|---------------------|------|---------|
| Vosk Hindi `small-hi-0.22` | ✅ bundled `assets/models/vosk-model-small-hi-0.22.zip` | 42 MB zip / 78 MB unpacked | auto-extract on first use (0.29 s measured) |
| NMT tokenizer | ✅ bundled `assets/nmt/` (merges/vocab) | ~17 MB | ships with app |
| NMT INT8 ONNX (`encoder*.onnx*`, `decoder*.onnx*`) | ❌ **not in git** (312 MB, 2 files >100 MB GitHub limit) | ~312 MB | **GitHub Release** `nmt-model-pack.zip` → `Android/data/com.flame.flame/files/nmt_model/` → Settings → Check |
| Santhali Piper (`sat_piper_model.onnx` + `.json`) | ❌ **not in git** | ~60 MB + JSON | **GitHub Release** `sat-tts-voice-pack.zip` → `.../files/sat_tts_voice/` → Settings → Check |
| Hindi `hi-IN` voice | device system TTS | — | Android Settings → TTS → install hi-IN data |

Do not commit `*.onnx`, `*.onnx.data`, `*.apk` to git — attach to Releases (2 GB limit). See `docs/MODELS.md`.

## ⚡ Latency benchmarks (18 Sept 2026)

Full tables + method: [`docs/BENCHMARKS.md`](docs/BENCHMARKS.md).

Device: `ASUS_I003DD` — Snapdragon 865, Android 12 API 31 · App `com.flame.flame v1.0.0` · USB/adb, production-path self-tests.

| Stage | Input → Output | Latency |
|-------|----------------|---------|
| ASR | 4.44 s Hindi speech → `चारो किताब को लो` | 370 ms load + 870 ms recog |
| NMT | Hindi → Ol Chiki Santhali | **134 ms** (7 sentences: 63.7–138.5 ms, avg 93 ms) |
| TTS | Ol Chiki → 1.49 s Santhali WAV (peak 0.62) | 60 ms synthesis |
| **Full voice-to-voice** | 4.44 s in → 1.49 s out | **~1.9 s wall-clock (< 3.0 s target)** |

Device checks: cold start avg ~3026 ms (6 runs); Vosk extract 0.29 s.

> **Honest caveats:** ~1.9 s is a complete real-model host benchmark, not same-device live-mic on the ASUS. The ASUS session lacked the INT8 NMT + Santhali packs (probe `<100 ms, complete=false`) and `hi-IN` voice (`engineError -4`), so sub-3 s still needs validation on the target phone with all packs installed. Missing packs are reported as missing, never fabricated.

## 📶 Offline classroom (2 phones, no internet)

Same Wi-Fi / hotspot only. Teacher hosts ephemeral TCP + UDP `:40404`; student broadcasts `FLAME1 DISCOVER <CODE>`, gets `FLAME1 OFFER <port> <token>`, joins via TCP JSON (`join`/`joinAck` with 6-char code + 12-char token). Live turns are newline-JSON text (`turn` with `cid`/`seq`), relayed teacher→students, each side re-translates + re-speaks locally. Full spec: [`docs/OFFLINE_CONNECTIVITY.md`](docs/OFFLINE_CONNECTIVITY.md).

## 🖼️ UI screenshots

Placeholders + capture guide: [`docs/screenshots/README.md`](docs/screenshots/README.md). 17 routes: splash, welcome, role, language, offline-setup, home, create-class, lesson-select, teacher-classroom (waiting/live), join, student-waiting, student-classroom, live-session, summary, ask-flame, settings, my-classes.

## 🗂️ Project structure

```
lib/            # app.dart, main.dart, screens/, services/{asr,translation,tts,classrooms,...}, state/, widgets/
assets/fln/     # corpus_pairs.json, fln_lexicon.json
assets/models/  # vosk-model-small-hi-0.22.zip (bundled)
assets/nmt/     # tokenizer only (ONNX via Release)
assets/fonts/   # NotoSansOlChiki.ttf
android/        # MainActivity + Vosk/ONNX/SAT sessions, manifests
test/, integration_test/, test_data/, test_driver/
docs/           # OFFLINE_CONNECTIVITY.md, BENCHMARKS.md, MODELS.md, screenshots/
```

## 🤝 Contributing

Please open an [issue](https://github.com/ganeshgawali2007-arch/FLAME-Future_ready-Language-Assistant_for-Mother_tongue_based-Education/issues) for bugs, feature requests, or improvements.

## 📄 License

Distributed under the [MIT License](LICENSE). Models/fonts keep their own licenses (IndicTrans2 MIT, Vosk Apache-2.0, ONNX Runtime MIT, Noto Sans Ol Chiki OFL).
