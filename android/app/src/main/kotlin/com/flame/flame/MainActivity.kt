package com.flame.flame

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val PERMISSION_CHANNEL = "flame/permissions"
        private const val ASR_CHANNEL = "flame/asr"
        private const val ASR_EVENTS = "flame/asr/events"
        private const val NMT_CHANNEL = "flame/nmt"
        private const val SAT_TTS_CHANNEL = "flame/sat_tts"
        private const val REQUEST_MIC = 4101
        private const val RECORD_AUDIO = Manifest.permission.RECORD_AUDIO
        private const val PREFS = "flame_permissions"
        private const val KEY_MIC_REQUESTED = "mic_requested"
    }

    private var micRequestResult: MethodChannel.Result? = null
    private var asrSession: VoskAsrSession? = null
    private var asrEvents: EventChannel.EventSink? = null
    private val nmtSession = OnnxNmtSession()
    private val satTtsSession = SatTtsSession()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        asrSession = VoskAsrSession(assets, filesDir) { event ->
            val sink = asrEvents
            if (sink != null && !isDestroyed) {
                sink.success(event)
            }
        }

        // Microphone permission (kept native — no permission_handler plugin).
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PERMISSION_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkMicrophone" -> result.success(micPermissionState())
                "requestMicrophone" -> requestMic(result)
                "openAppSettings" -> {
                    openAppSettings()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Streaming events: partial / final / error / status.
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ASR_EVENTS
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(
                arguments: Any?,
                events: EventChannel.EventSink?
            ) {
                asrEvents = events
            }

            override fun onCancel(arguments: Any?) {
                asrEvents = null
            }
        })

        // Real offline speech recognition (Vosk).
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ASR_CHANNEL
        ).setMethodCallHandler { call, result ->
            val session = asrSession ?: return@setMethodCallHandler result.error(
                "NO_SESSION", "ASR session unavailable", null
            )
            when (call.method) {
                "status" -> result.success(session.state())
                "install" -> {
                    session.install()
                    result.success(session.state())
                }
                "startListening" -> {
                    session.start()
                    result.success(true)
                }
                "stopListening" -> session.stop(result)
                "cancelListening" -> {
                    session.cancel()
                    result.success(true)
                }
                "release" -> {
                    session.release()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Real on-device translation runtime (IndicTrans2 INT8 ONNX).
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NMT_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(nmtSession.state())
                "load" -> {
                    val modelDir = call.argument<String>("modelDir")
                    if (modelDir.isNullOrBlank()) {
                        result.error("BAD_ARGS", "modelDir is required", null)
                    } else {
                        val start = call.argument<Number>("decoderStartId")?.toLong() ?: 2L
                        nmtSession.load(modelDir, start, result)
                    }
                }
                "startDecode" -> {
                    val ids = call.argument<List<Number>>("inputIds")
                    val mask = call.argument<List<Number>>("attentionMask")
                    if (ids.isNullOrEmpty() || mask.isNullOrEmpty()) {
                        result.error("BAD_ARGS", "inputIds/attentionMask required", null)
                    } else {
                        nmtSession.startDecode(
                            LongArray(ids.size) { ids[it].toLong() },
                            LongArray(mask.size) { mask[it].toLong() },
                            result
                        )
                    }
                }
                "step" -> {
                    val next = call.argument<Number>("nextId")
                    if (next == null) {
                        result.error("BAD_ARGS", "nextId is required", null)
                    } else {
                        nmtSession.step(next.toLong(), result)
                    }
                }
                "endDecode" -> nmtSession.endDecode(result)
                "release" -> nmtSession.release(result)
                else -> result.notImplemented()
            }
        }

        // Real offline Santhali speech synthesis (Piper-style VITS ONNX +
        // AudioTrack playback). Never routes through the Hindi system voice.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SAT_TTS_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(satTtsSession.state())
                "probeText" -> result.success(satTtsSession.probeText())
                "load" -> {
                    val modelDir = call.argument<String>("modelDir")
                    if (modelDir.isNullOrBlank()) {
                        result.error("BAD_ARGS", "modelDir is required", null)
                    } else {
                        satTtsSession.load(modelDir, result)
                    }
                }
                "synthesize" -> {
                    val text = call.argument<String>("text")
                    if (text.isNullOrEmpty()) {
                        result.error("BAD_ARGS", "text is required", null)
                    } else {
                        val play = call.argument<Boolean>("play") ?: true
                        satTtsSession.synthesize(text, play, result)
                    }
                }
                "stop" -> satTtsSession.stop(result)
                "release" -> satTtsSession.release(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun micPermissionState(): String {
        if (checkSelfPermission(RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            return "granted"
        }
        // A permission that was never asked for must not be reported as a
        // permanent denial: Android's shouldShowRequestPermissionRationale is
        // false both before the first request and after a "don't ask again",
        // so the two cases have to be told apart with an explicit record.
        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        if (!prefs.getBoolean(KEY_MIC_REQUESTED, false)) {
            return "notDetermined"
        }
        return if (!shouldShowRequestPermissionRationale(RECORD_AUDIO)) {
            // Android 11+ records a permanent "don't ask again" on the
            // activity's first show of the rationale.
            "permanentlyDenied"
        } else {
            "denied"
        }
    }

    private fun requestMic(result: MethodChannel.Result) {
        if (micRequestResult != null) {
            result.error("BUSY", "A permission request is already in progress.", null)
            return
        }
        if (micPermissionState() == "granted") {
            result.success("granted")
            return
        }
        // Remember that a real request was made so the state machine can
        // distinguish "never asked" from "don't ask again" later.
        getSharedPreferences(PREFS, MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_MIC_REQUESTED, true)
            .apply()
        micRequestResult = result
        requestPermissions(arrayOf(RECORD_AUDIO), REQUEST_MIC)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_MIC) return
        val pending = micRequestResult ?: return
        micRequestResult = null
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            pending.success("granted")
        } else {
            pending.success(
                if (!shouldShowRequestPermissionRationale(RECORD_AUDIO)) {
                    "permanentlyDenied"
                } else {
                    "denied"
                }
            )
        }
    }

    private fun openAppSettings() {
        startActivity(
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:$packageName")
            )
        )
    }
}