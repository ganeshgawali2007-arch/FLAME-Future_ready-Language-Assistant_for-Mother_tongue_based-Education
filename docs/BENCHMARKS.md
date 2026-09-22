# FLAME End-to-End Latency Benchmark

Offline Hindi → Santhali voice-to-voice prototype · Benchmark date: 18 September 2026

## 1. Benchmark Configuration

| Item | Measured configuration |
|------|------------------------|
| Device | ASUS_I003DD — Qualcomm SM8250 “kona” / Snapdragon 865-series, 8-core CPU, Android 12 API 31 |
| Application | FLAME com.flame.flame v1.0.0, debug APK, versionCode 1 |
| Measurement method | Physical hardware; USB/adb driven; production-path self-tests and on-device shell measurements |
| ASR | Vosk Hindi small-hi-0.22 |
| NMT | IndicTrans2 HindiSanthali indic-indic-dist-320M, INT8 ONNX target |
| TTS | Santhali sat-piper VITS target; Hindi system Google TTS where applicable |

## 2. End-to-End Voice-to-Voice Input / Output

| Stage | Actual input | Actual output | Measured latency |
|-------|--------------|---------------|------------------|
| ASR | Real Hindi speech — 4.44 s utterance | चारो किताब को लो | 370 ms model load + 870 ms recognition |
| NMT | चारो किताब को लो | Ol Chiki Santhali (see §3 pattern) | 134 ms |
| TTS | Ol Chiki Santhali | Real 1.49 s Santhali WAV; non-silence, peak 0.62 | 60 ms synthesis |
| Full cycle | 4.44 s real Hindi speech | 1.49 s real Santhali speech | ~1.9 s wall-clock |

## 3. NMT Sentence-Level Input / Output Benchmark

| # | Hindi input | Total |
|---|-------------|-------|
| 1 | चलो बच्चों, किताब खोलो। | 138.5 ms |
| 2 | सभी बच्चे बैठ जाएँ। | 66.6 ms |
| 3 | आज हम गिनती सीखेंगे। | 81.4 ms |
| 4 | बच्चे मैदान में खेल रहे हैं। | 112.2 ms |
| 5 | यह एक गाय है। | 81.3 ms |
| 6 | अपना नाम बताओ। | 63.7 ms |
| 7 | धन्यवाद, अब तुम बैठ सकते हो। | 108.1 ms |

NMT total input/output: 63.7–138.5 ms; average 93 ms across 7 real classroom sentences.

## 4. Latency Budget

| Component | Measured value | Contribution to target |
|-----------|----------------|------------------------|
| ASR | 370 ms load + 870 ms recognition | Dominant measured compute stage |
| NMT | 134 ms host FP32 reference | Low relative to 3 s budget |
| TTS | 60 ms synthesis | Low relative to 3 s budget |
| Full measured chain | ~1.9 s wall-clock | Within 3 s target in the complete host benchmark |

## 5. Sub-3-Second Target

| Metric | Observed | Target |
|--------|----------|--------|
| Complete voice-to-voice wall time | ~1.9 s | < 3.0 s |
| Real input | 4.44 s Hindi speech | Live microphone input |
| Real output | 1.49 s Santhali speech | Audible Santhali playback |

## 6. Device Validation Status

| Test | ASUS_I003DD result |
|------|--------------------|
| Cold start | 6 runs: 3021 / 3024 / 3026 / 3027 / 3029 / 3044 ms; average ~3026 ms |
| Vosk model extraction | 42 MB zip → 78 MB unpacked in 0.29 s |
| NMT INT8 pack | Absent on ASUS during this session; pack resolution probe <100 ms, complete=false |
| Santhali TTS pack | Absent on ASUS during this session; expected sat_piper_model.onnx ~60 MB + JSON |
| Hindi system TTS | hi-IN voice data not installed; measured attempts failed with engineError -4 |
| On-device NMT reference | Prior Motorola Edge 60 Pro measurements with packs: 150–535 ms/sentence INT8 |

## 7. Honest Caveats

The ~1.9 s voice-to-voice figure is a complete real-model host benchmark, not a same-device live-microphone measurement on the ASUS device.
The ASUS session lacked the on-device INT8 NMT and Santhali voice packs, so the final sub-3-second target still requires validation on the target phone with all packs installed.

## 8. Measurement Basis

All reported benchmark values are from real hardware/model execution described in the source benchmark. The host end-to-end test used a real 4.44 s Hindi recording, the same Vosk model, the IndicTrans2 ONNX graphs with the exact tokenizer and greedy decode pipeline, and the Santhali Piper/VITS voice. The ASUS device session was performed through adb and app self-tests; missing model/voice packs were reported as missing rather than replaced by fabricated timings.
