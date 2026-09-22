package com.flame.flame

import android.content.res.AssetManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import org.vosk.Model
import org.vosk.Recognizer
import java.io.File
import java.io.FileNotFoundException
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStream
import java.util.zip.ZipInputStream

/**
 * Real, offline Hindi speech recognition driven by Vosk (Kaldi chain engine).
 *
 * Model: vosk-model-small-hi-0.22 (44.5 MB bundle, Apache-2.0) is shipped as a
 * zip asset and extracted once into app storage on first use. Recognition runs
 * on a dedicated background thread: 16 kHz mono PCM from the microphone is fed
 * into a streaming Recognizer; partial hypotheses and final results are emitted
 * over the `flame/asr/events` channel. Everything happens on-device — there is
 * no network path anywhere in this class.
 */
class VoskAsrSession(
    private val assets: AssetManager,
    private val filesDir: File,
    private val emit: (Map<String, Any?>) -> Unit,
) {
    companion object {
        private const val ASSET = "models/vosk-model-small-hi-0.22.zip"
        private const val MODEL_DIR = "vosk-model-small-hi-0.22"
        private const val SAMPLE_RATE = 16000
        private const val BUFFER_MS = 100
        private const val TAG = "VoskAsrSession"
    }

    private val modelDir: File get() = File(filesDir, MODEL_DIR)

    private fun modelComplete(): Boolean = File(modelDir, "am/final.mdl").isFile

    @Volatile private var extracting = false
    @Volatile private var installed = modelComplete()

    private val thread = HandlerThread("vosk-asr")
    private var handler: Handler? = null
    private val main = Handler(Looper.getMainLooper())

    private var model: Model? = null
    private var recognizer: Recognizer? = null
    private var audioRecord: AudioRecord? = null

    @Volatile private var listening = false
    @Volatile private var cancelRequested = false

    /** "ready" | "installing" | "missing". */
    fun state(): String = when {
        installed -> "ready"
        extracting -> "installing"
        else -> "missing"
    }

    /** Extract the bundled model once. Idempotent; returns immediately. */
    fun install() {
        if (installed || extracting) return
        extracting = true
        main.post { emit(mapOf("type" to "status", "state" to "installing")) }
        Thread {
            try {
                extract()
                installed = true
                main.post {
                    emit(mapOf("type" to "install", "state" to "installed"))
                    emit(mapOf("type" to "status", "state" to "ready"))
                }
            } catch (e: Exception) {
                Log.e(TAG, "install error", e)
                main.post {
                    emit(
                        mapOf(
                            "type" to "install",
                            "state" to "error",
                            "message" to (e.message ?: e.toString()),
                        )
                    )
                }
            } finally {
                extracting = false
            }
        }.start()
    }

    private fun openModelAsset(): InputStream {
        // In a Flutter release APK, pubspec assets are packed under
        // assets/flutter_assets/<pubspec-relative-path>. AssetManager only
        // opens paths relative to the APK's assets/ root, so the pubspec
        // path ("assets/models/...") is NOT directly openable. Use Flutter's
        // official lookup then a set of fallbacks observed in real APKs.
        val candidates = mutableListOf<String>()
        runCatching {
            FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(ASSET)
        }.onSuccess { key ->
            Log.i(TAG, "flutterLoader lookup key: $key")
            if (key.isNotBlank()) candidates.add(key)
        }.onFailure {
            Log.w(TAG, "flutterLoader lookup failed", it)
        }
        candidates.add("flutter_assets/assets/$ASSET")
        candidates.add("flutter_assets/$ASSET")
        candidates.add(ASSET)
        for (candidate in candidates.distinct()) {
            try {
                val stream = assets.open(candidate)
                Log.i(TAG, "opened model asset: $candidate")
                return stream
            } catch (_: IOException) {
                Log.w(TAG, "asset not found at: $candidate")
            }
        }
        throw FileNotFoundException("model asset not found: $ASSET")
    }

    private fun extract() {
        Log.i(TAG, "extract start filesDir=$filesDir")
        modelDir.mkdirs()
        val zip = ZipInputStream(openModelAsset())
        val buffer = ByteArray(64 * 1024)
        var written = 0L
        var count = 0
        while (true) {
            val entry = zip.nextEntry ?: break
            val raw = entry.name
            val relative = raw.removePrefix("$MODEL_DIR/")
            if (raw.contains("..") || relative.isEmpty()) {
                zip.closeEntry()
                continue
            }
            val target = File(modelDir, relative.replace('/', File.separatorChar))
            if (entry.isDirectory) {
                target.mkdirs()
                zip.closeEntry()
                continue
            }
            target.parentFile?.mkdirs()
            FileOutputStream(target).use { out ->
                var read = zip.read(buffer)
                while (read > 0) {
                    out.write(buffer, 0, read)
                    written += read
                    read = zip.read(buffer)
                }
            }
            count++
            zip.closeEntry()
        }
        zip.close()
        Log.i(TAG, "extract done files=$count bytes=$written dirExists=${modelDir.exists()}")
        if (!File(modelDir, "am/final.mdl").exists()) {
            throw IllegalStateException("model extract failed: am/final.mdl missing")
        }
    }

    /** Begin streaming recognition from the microphone (once). */
    fun start() {
        ensureThread()
        handler?.post {
            if (listening) return@post
            if (!installed) {
                main.post { emit(mapOf("type" to "error", "message" to "model not installed")) }
                return@post
            }
            cancelRequested = false
            recognitionLoop()
        }
    }

    /** Stop recording; a final result (if any) is still emitted. */
    fun stop(result: MethodChannel.Result) {
        ensureThread()
        handler?.post {
            val wasListening = listening
            listening = false
            main.post { result.success(wasListening) }
        }
    }

    /** Stop recording and discard the pending final result. */
    fun cancel() {
        ensureThread()
        handler?.post {
            cancelRequested = true
            listening = false
        }
    }

    /** Release the native model + recognizer so RAM returns to the app. */
    fun release() {
        ensureThread()
        handler?.post {
            cancelRequested = true
            listening = false
            runCatching { recognizer?.close() }
            runCatching { model?.close() }
            runCatching { audioRecord?.release() }
            recognizer = null
            model = null
            audioRecord = null
        }
    }

    private fun ensureThread() {
        if (!thread.isAlive) thread.start()
        if (handler == null) handler = Handler(thread.looper)
    }

    private fun recognitionLoop() {
        listening = true
        try {
            Log.i(TAG, "loading model from ${modelDir.absolutePath}")
            model = Model(modelDir.absolutePath)
            Log.i(TAG, "model loaded; creating recognizer")
            recognizer = Recognizer(model, SAMPLE_RATE.toFloat())
            Log.i(TAG, "recognizer created")
            val minBuf = AudioRecord.getMinBufferSize(
                SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
            )
            val bufSize = maxOf(minBuf * 2, SAMPLE_RATE * BUFFER_MS / 1000 * 2)
            audioRecord = AudioRecord(
                MediaRecorder.AudioSource.VOICE_RECOGNITION,
                SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufSize,
            )
            val buf = ByteArray(bufSize)
            audioRecord!!.startRecording()
            main.post { emit(mapOf("type" to "status", "state" to "listening")) }

            var lastPartial = ""
            while (listening) {
                val read = audioRecord!!.read(buf, 0, buf.size)
                if (read <= 0) {
                    Thread.sleep(20)
                    continue
                }
                if (recognizer!!.acceptWaveForm(buf, read)) {
                    val text = textOf(recognizer!!.result)
                    if (text.isNotEmpty()) {
                        main.post { emit(mapOf("type" to "final", "text" to text)) }
                    }
                } else {
                    val partial = textOf(recognizer!!.partialResult)
                    if (partial.isNotEmpty() && partial != lastPartial) {
                        lastPartial = partial
                        main.post { emit(mapOf("type" to "partial", "text" to partial)) }
                    }
                }
            }

            if (!cancelRequested) {
                val tail = textOf(recognizer!!.result)
                if (tail.isNotEmpty()) {
                    main.post { emit(mapOf("type" to "final", "text" to tail)) }
                }
            }
            Log.i(TAG, "recognition loop ended cleanly cancelled=$cancelRequested")
        } catch (e: Exception) {
            Log.e(TAG, "recognition error", e)
            main.post { emit(mapOf("type" to "error", "message" to (e.message ?: e.toString()))) }
        } finally {
            runCatching { audioRecord?.stop() }
            runCatching { audioRecord?.release() }
            audioRecord = null
            runCatching { recognizer?.close() }
            recognizer = null
            runCatching { model?.close() }
            model = null
            listening = false
            main.post { emit(mapOf("type" to "status", "state" to "idle")) }
        }
    }

    private fun textOf(json: String): String = try {
        JSONObject(json).optString("text", "").trim()
    } catch (_: Exception) {
        ""
    }
}