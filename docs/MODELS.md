# FLAME Models

## Bundled (in git)

- `assets/models/vosk-model-small-hi-0.22.zip` — 42 MB zip / 78 MB unpacked, Apache-2.0. Auto-extracts on first use (~0.29 s).
- `assets/nmt/` — tokenizer only (`mt_merges_*`, `mt_vocab_*`), ~17 MB.
- `assets/fln/corpus_pairs.json` — 1.3 MB classroom phrases.
- `assets/fonts/NotoSansOlChiki.ttf` — 91 KB Ol Chiki font.

## Side-load via GitHub Releases (not in git)

GitHub rejects files >100 MB on push. These exceed it, so attach to a Release (2 GB limit):

- `nmt-model-pack.zip` (~312 MB):
  `encoder_model.onnx`, `encoder_model.onnx.data` (~114 MB), `decoder_model.onnx`, `decoder_with_past_model.onnx`, `decoder_shared.onnx.data` (~193 MB)
  → copy to `Android/data/com.flame.flame/files/nmt_model/` → Settings → Check for pack.
- `sat-tts-voice-pack.zip` (~60 MB):
  `sat_piper_model.onnx` (~60 MB) + `sat_piper_model.onnx.json`
  → copy to `.../files/sat_tts_voice/` → Settings → Check.
- `SHA256SUMS.txt` for all files.
- `FLAME-vX.Y.Z.apk` (do not commit APKs to git).

## Why

Keeps clone ~65 MB lean, matches the app's built-in side-load UX (`NmtModelPack.resolveModelDir()`, `SatTtsPack`, Offline Setup → Check). Current `v1.0.0` APK (390 MB) stays on Releases; packs go on the next models Release.

Hindi `hi-IN` voice is system TTS, not bundled — install via Android Settings → Text-to-speech.
