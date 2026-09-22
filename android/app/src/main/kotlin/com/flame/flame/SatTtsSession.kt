package com.flame.flame

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Log
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.FloatBuffer
import java.nio.LongBuffer
import java.util.concurrent.atomic.AtomicBoolean
import org.json.JSONObject

/**
 * Real offline Santhali (Ol Chiki) speech synthesis: a Piper-style VITS model
 * (sat_piper_model.onnx + sat_piper_model.onnx.json) executed by ONNX Runtime.
 *
 * The model uses phoneme_type=text with a direct character->id map covering
 * the Ol Chiki block, so no espeak/phonemizer is involved: input text is
 * mapped char-by-char exactly per the shipped JSON config (never an invented
 * map). Single speaker, 16 kHz output.
 *
 * Playback goes through [AudioTrack] (STREAM_MUSIC semantics: usage MEDIA,
 * content SPEECH — the same route as system TTS) on the worker thread, so
 * synthesis + playback never block the UI thread. [stop] cancels an
 * in-flight utterance; [synthesize] with play=false runs inference only
 * (silent probe used by warm-up — no uninvited audio).
 *
 * There is no network path anywhere in this class, and Santhali audio is
 * never routed through the Hindi system voice.
 */
class SatTtsSession {
    companion object {
        private const val TAG = "SatTtsSession"
        private const val MODEL = "sat_piper_model.onnx"
        private const val CONFIG = "sat_piper_model.onnx.json"
        private const val PROBE_TEXT = "ᱥᱟᱱᱛᱟᱲᱤ"

        /** Refuse absurd inputs before allocating; VITS cost scales linearly. */
        private const val MAX_MAPPED_CHARS = 500

        /** Minimum audible probe output; shorter means the model misbehaved. */
        private const val MIN_PROBE_DURATION_MS = 200
    }

    private val thread = HandlerThread("sat-tts")
    private var handler: Handler? = null
    private val main = Handler(Looper.getMainLooper())

    private var session: OrtSession? = null
    private var phonemes: Map<String, Int> = emptyMap()
    private var sampleRate = 16000
    private var noiseScale = 0.667f
    private var lengthScale = 1.0f
    private var noiseW = 0.8f
    private var modelDir: String? = null

    private var track: AudioTrack? = null
    private val cancelled = AtomicBoolean(false)
    private val busy = AtomicBoolean(false)

    private fun ensureThread() {
        if (!thread.isAlive) thread.start()
        if (handler == null) handler = Handler(thread.looper)
    }

    /** "ready" | "missing" — session loaded or not. */
    fun state(): String = if (session != null) "ready" else "missing"

    /** The bundled probe phrase (used by warm-up; kept here, not in Dart). */
    fun probeText(): String = PROBE_TEXT

    fun load(modelDir: String, result: MethodChannel.Result) {
        ensureThread()
        handler?.post {
            try {
                if (session != null) {
                    Log.i(TAG, "load: already loaded")
                    reply(result, state())
                    return@post
                }
                val dir = File(modelDir)
                val modelFile = File(dir, MODEL)
                val configFile = File(dir, CONFIG)
                if (!modelFile.isFile) {
                    throw IllegalStateException("model pack incomplete: $MODEL missing in $modelDir")
                }
                if (!configFile.isFile) {
                    throw IllegalStateException("model pack incomplete: $CONFIG missing in $modelDir")
                }
                Log.i(TAG, "load: files verified in $modelDir "
                    + "(onnx=${modelFile.length()} config=${configFile.length()})")
                val parsed = parseConfig(configFile.readText())
                Log.i(TAG, "load: creating ORT session")
                val environment = OrtEnvironment.getEnvironment()
                val opts = OrtSession.SessionOptions().apply {
                    setIntraOpNumThreads(4)
                    setOptimizationLevel(OrtSession.SessionOptions.OptLevel.ALL_OPT)
                }
                val created = environment.createSession(modelFile.absolutePath, opts)
                session = created
                phonemes = parsed.phonemes
                sampleRate = parsed.sampleRate
                noiseScale = parsed.noiseScale
                lengthScale = parsed.lengthScale
                noiseW = parsed.noiseW
                this.modelDir = modelDir
                Log.i(TAG, "load: session ready sr=$sampleRate "
                    + "phonemes=${phonemes.size} scales=[$noiseScale,$lengthScale,$noiseW]")
                reply(result, state())
            } catch (e: Exception) {
                Log.e(TAG, "load error", e)
                runCatching { session?.close() }
                session = null
                phonemes = emptyMap()
                replyError(result, "LOAD_ERROR", e.message ?: e.toString())
            }
        }
    }

    fun synthesize(text: String, play: Boolean, result: MethodChannel.Result) {
        ensureThread()
        handler?.post {
            if (!busy.compareAndSet(false, true)) {
                replyError(result, "BUSY", "synthesis already in progress")
                return@post
            }
            cancelled.set(false)
            val sw = System.currentTimeMillis()
            try {
                val sess = session ?: throw IllegalStateException("sessions not loaded")
                val ids = tokenize(text)
                Log.i(TAG, "synthesize: chars=${text.length} ids=${ids.size} play=$play")
                val wav = runInference(sess, ids)
                val synthMs = System.currentTimeMillis() - sw
                val durationMs = (wav.size * 1000L) / sampleRate
                Log.i(TAG, "synthesize: inference done samples=${wav.size} "
                    + "durationMs=$durationMs synthMs=$synthMs "
                    + "peak=${"%.3f".format(peak(wav))}")
                var playMs = 0L
                var stopped = false
                if (play) {
                    if (cancelled.get()) {
                        stopped = true
                    } else {
                        val playStart = System.currentTimeMillis()
                        stopped = playPcm(wav)
                        playMs = System.currentTimeMillis() - playStart
                    }
                }
                val out = HashMap<String, Any>()
                out["status"] = if (stopped) "stopped" else "completed"
                out["sampleRate"] = sampleRate
                out["durationMs"] = durationMs
                out["synthMs"] = synthMs
                out["playMs"] = playMs
                reply(result, out)
            } catch (e: Exception) {
                Log.e(TAG, "synthesize error", e)
                val code = if (e is IllegalArgumentException) "BAD_TEXT" else "SYNTH_ERROR"
                replyError(result, code, e.message ?: e.toString())
            } finally {
                busy.set(false)
            }
        }
    }

    fun stop(result: MethodChannel.Result?) {
        ensureThread()
        // Flag first, then stop the track synchronously on this thread: that
        // unblocks a worker parked inside AudioTrack.write immediately (a
        // posted stop would queue behind the blocked worker). The worker loop
        // observes `cancelled` and finishes the in-flight reply itself.
        cancelled.set(true)
        val t = track
        runCatching { t?.pause() }
        runCatching { t?.flush() }
        runCatching { t?.stop() }
        main.post { result?.success(true) }
    }

    fun release(result: MethodChannel.Result?) {
        ensureThread()
        cancelled.set(true)
        handler?.post {
            try {
                track?.let {
                    runCatching { it.stop() }
                    runCatching { it.release() }
                }
            } finally {
                track = null
            }
            runCatching { session?.close() }
            session = null
            phonemes = emptyMap()
            modelDir = null
            result?.let { r -> reply(r, true) }
        }
    }

    // ----------------------------------------------------------------------

    private data class ParsedConfig(
        val phonemes: Map<String, Int>,
        val sampleRate: Int,
        val noiseScale: Float,
        val lengthScale: Float,
        val noiseW: Float,
    )

    /** Parses the shipped Piper-style JSON; every value is validated, nothing
     * is defaulted except the three inference scales (config's own values). */
    private fun parseConfig(json: String): ParsedConfig {
        val root = JSONObject(json)
        val audio = root.optJSONObject("audio")
            ?: throw IllegalStateException("config: missing 'audio'")
        val sr = audio.optInt("sample_rate", -1)
        if (sr <= 0) throw IllegalStateException("config: bad sample_rate=$sr")
        val inference = root.optJSONObject("inference")
        val noise = inference?.optDouble("noise_scale", 0.667)?.toFloat() ?: 0.667f
        val length = inference?.optDouble("length_scale", 1.0)?.toFloat() ?: 1.0f
        val w = inference?.optDouble("noise_w", 0.8)?.toFloat() ?: 0.8f
        val idMap = root.optJSONObject("phoneme_id_map")
            ?: throw IllegalStateException("config: missing 'phoneme_id_map'")
        val map = HashMap<String, Int>()
        val keys = idMap.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            map[key] = idMap.getJSONArray(key).getInt(0)
        }
        for (marker in listOf("_", "^", "$", " ")) {
            if (!map.containsKey(marker)) {
                throw IllegalStateException("config: phoneme_id_map missing '$marker'")
            }
        }
        if (map.size < 32) {
            throw IllegalStateException("config: phoneme_id_map too small (${map.size})")
        }
        return ParsedConfig(map, sr, noise, length, w)
    }

    /**
     * Char-by-char mapping exactly per the shipped config (BOS ^, EOS $,
     * whitespace -> space id). Unknown characters are skipped and counted —
     * never crash on unexpected input, never invent phonemes.
     */
    private fun tokenize(text: String): IntArray {
        val map = phonemes
        if (map.isEmpty()) throw IllegalStateException("sessions not loaded")
        val bos = map["^"]!!
        val eos = map["$"]!!
        val space = map[" "]!!
        val ids = ArrayList<Int>(text.length + 2)
        ids.add(bos)
        var mapped = 0
        var skipped = 0
        var i = 0
        while (i < text.length) {
            val cp = text.codePointAt(i)
            i += Character.charCount(cp)
            val ch = String(Character.toChars(cp))
            val id = map[ch]
            if (id != null) {
                ids.add(id)
                if (!Character.isWhitespace(cp)) mapped++
            } else if (Character.isWhitespace(cp)) {
                ids.add(space)
            } else {
                skipped++
            }
        }
        ids.add(eos)
        Log.i(TAG, "tokenize: mapped=$mapped skipped=$skipped ids=${ids.size}")
        if (mapped == 0) {
            throw IllegalArgumentException(
                "no synthesizable Ol Chiki content (mapped=0 skipped=$skipped)")
        }
        if (mapped > MAX_MAPPED_CHARS) {
            throw IllegalArgumentException(
                "text too long (mapped=$mapped max=$MAX_MAPPED_CHARS)")
        }
        return ids.toIntArray()
    }

    private fun runInference(sess: OrtSession, ids: IntArray): FloatArray {
        val environment = OrtEnvironment.getEnvironment()
        val idsTensor = OnnxTensor.createTensor(
            environment, LongBuffer.wrap(ids.map { it.toLong() }.toLongArray()),
            longArrayOf(1, ids.size.toLong())
        )
        val lenTensor = OnnxTensor.createTensor(
            environment, LongBuffer.wrap(longArrayOf(ids.size.toLong())),
            longArrayOf(1)
        )
        val scalesTensor = OnnxTensor.createTensor(
            environment, FloatBuffer.wrap(floatArrayOf(noiseScale, lengthScale, noiseW)),
            longArrayOf(3)
        )
        var ortResult: OrtSession.Result? = null
        try {
            ortResult = sess.run(
                mapOf(
                    "input" to idsTensor,
                    "input_lengths" to lenTensor,
                    "scales" to scalesTensor,
                )
            )
            val tensor = ortResult.get(0) as OnnxTensor
            val buf = tensor.floatBuffer
            val out = FloatArray(buf.remaining())
            buf.get(out)
            return out
        } finally {
            runCatching { idsTensor.close() }
            runCatching { lenTensor.close() }
            runCatching { scalesTensor.close() }
            runCatching { ortResult?.close() }
        }
    }

    private fun peak(wav: FloatArray): Float {
        var best = 0f
        for (v in wav) {
            val a = kotlin.math.abs(v)
            if (a > best) best = a
        }
        return best
    }

    /**
     * Streams 16-bit PCM to the speaker. Returns true when cancelled
     * (stop() was called), false on natural completion.
     */
    private fun playPcm(wav: FloatArray): Boolean {
        val minBuf = AudioTrack.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build()
        val format = AudioFormat.Builder()
            .setSampleRate(sampleRate)
            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
            .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
            .build()
        val player = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            AudioTrack.Builder()
                .setAudioAttributes(attrs)
                .setAudioFormat(format)
                .setBufferSizeInBytes((minBuf * 2).coerceAtLeast(wav.size * 2))
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()
        } else {
            @Suppress("DEPRECATION")
            AudioTrack(
                android.media.AudioManager.STREAM_MUSIC,
                sampleRate,
                AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                (minBuf * 2).coerceAtLeast(wav.size * 2),
                AudioTrack.MODE_STREAM
            )
        }
        track = player
        try {
            player.play()
            val chunk = ShortArray(2048)
            var pos = 0
            while (pos < wav.size) {
                if (cancelled.get()) return true
                val n = minOf(chunk.size, wav.size - pos)
                for (i in 0 until n) {
                    val v = wav[pos + i].coerceIn(-1f, 1f)
                    chunk[i] = (v * 32767f).toInt().toShort()
                }
                var written = 0
                while (written < n) {
                    if (cancelled.get()) return true
                    val w = player.write(chunk, written, n - written)
                    if (w < 0) throw IllegalStateException("AudioTrack.write=$w")
                    written += w
                }
                pos += n
            }
            // MODE_STREAM write() returns after buffering, not after audibly
            // playing. "completed" must mean the speaker really finished, or
            // the queue would overlap the next utterance: wait until the play
            // head reaches the last frame (bounded by duration + margin).
            val deadline = System.currentTimeMillis() +
                (wav.size * 1000L / sampleRate) + 5000L
            while (!cancelled.get()) {
                val head = try {
                    player.playbackHeadPosition
                } catch (_: Exception) {
                    break
                }
                if (head >= wav.size) break
                if (System.currentTimeMillis() > deadline) break
                try {
                    Thread.sleep(20)
                } catch (_: InterruptedException) {
                    break
                }
            }
            return cancelled.get()
        } finally {
            runCatching { player.stop() }
            runCatching { player.flush() }
            runCatching { player.release() }
            if (track === player) track = null
        }
    }

    private fun reply(result: MethodChannel.Result, value: Any) {
        main.post { result.success(value) }
    }

    private fun replyError(result: MethodChannel.Result, code: String, message: String) {
        main.post { result.error(code, message, null) }
    }
}
