package com.flame.flame

import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Log
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.LongBuffer
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Real on-device Hindi↔Santhali translation runtime: IndicTrans2
 * indic-indic-dist-320M INT8 ONNX (MIT) executed by ONNX Runtime.
 *
 * Mirrors the verified host reference loop exactly:
 *   encoder(input_ids, attention_mask) -> last_hidden_state
 *   step 0: decoder([decoder_start], enc_hidden, enc_mask)
 *   step n: decoder_with_past([next], enc_mask, past_key_values)
 *   argmax per step (done natively — a 122k-float logits vector never
 *   crosses the platform channel).
 *
 * The model pack is side-loaded (not bundled): five files placed under the
 * app files dir by the user/system. All inference runs on a dedicated worker
 * thread; replies are posted back on the main thread. There is no network
 * path anywhere in this class.
 */
class OnnxNmtSession {
    companion object {
        private const val TAG = "OnnxNmtSession"
        private const val ENCODER = "encoder_model.onnx"
        private const val DECODER = "decoder_model.onnx"
        private const val DECODER_PAST = "decoder_with_past_model.onnx"
        private const val ENCODER_DATA = "encoder_model.onnx.data"
        private const val DECODER_DATA = "decoder_shared.onnx.data"
    }

    private val thread = HandlerThread("onnx-nmt")
    private var handler: Handler? = null
    private val main = Handler(Looper.getMainLooper())

    private var env: OrtEnvironment? = null
    private var encoder: OrtSession? = null
    private var decoder: OrtSession? = null
    private var decoderPast: OrtSession? = null
    private var numLayers = 0
    private var decoderStartId = 2L

    // Per-sentence decode state (native tensors stay on the worker side).
    private var encHidden: OnnxTensor? = null
    private var encMask: OnnxTensor? = null
    private var past: MutableList<OnnxTensor>? = null
    private val decoding = AtomicBoolean(false)

    private fun ensureThread() {
        if (!thread.isAlive) thread.start()
        if (handler == null) handler = Handler(thread.looper)
    }

    /** "ready" | "missing" — sessions loaded or not. */
    fun state(): String = if (decoderPast != null) "ready" else "missing"

    fun load(modelDir: String, decoderStart: Long, result: MethodChannel.Result) {
        ensureThread()
        handler?.post {
            try {
                if (decoderPast != null) {
                    Log.i(TAG, "load: already loaded")
                    reply(result, state())
                    return@post
                }
                val dir = File(modelDir)
                for (name in listOf(ENCODER, DECODER, DECODER_PAST, ENCODER_DATA, DECODER_DATA)) {
                    if (!File(dir, name).isFile) {
                        Log.e(TAG, "load: MISSING $name in $modelDir")
                        throw IllegalStateException("model pack incomplete: $name missing in $modelDir")
                    }
                }
                Log.i(TAG, "load: pack files verified in $modelDir")
                val environment = OrtEnvironment.getEnvironment()
                val opts = OrtSession.SessionOptions().apply {
                    setIntraOpNumThreads(4)
                    setOptimizationLevel(OrtSession.SessionOptions.OptLevel.ALL_OPT)
                }
                Log.i(TAG, "load: creating encoder session")
                val enc = environment.createSession(File(dir, ENCODER).absolutePath, opts)
                Log.i(TAG, "load: encoder session created; creating decoder sessions")
                val dec = environment.createSession(File(dir, DECODER).absolutePath, opts)
                val decPast = environment.createSession(File(dir, DECODER_PAST).absolutePath, opts)
                env = environment
                encoder = enc
                decoder = dec
                decoderPast = decPast
                numLayers = (dec.outputNames.size - 1) / 4
                decoderStartId = decoderStart
                Log.i(TAG, "NMT sessions ready; decoder layers=$numLayers eos-ish start=$decoderStart")
                reply(result, state())
            } catch (e: Exception) {
                Log.e(TAG, "load error", e)
                runCatching { encoder?.close() }
                runCatching { decoder?.close() }
                runCatching { decoderPast?.close() }
                encoder = null
                decoder = null
                decoderPast = null
                replyError(result, "LOAD_ERROR", e.message ?: e.toString())
            }
        }
    }

    fun startDecode(inputIds: LongArray, mask: LongArray, result: MethodChannel.Result) {
        ensureThread()
        handler?.post {
            try {
                val environment = env ?: throw IllegalStateException("sessions not loaded")
                val enc = encoder ?: throw IllegalStateException("sessions not loaded")
                val dec = decoder ?: throw IllegalStateException("sessions not loaded")
                endDecodeLocked()
                Log.i(TAG, "startDecode: input_ids=${inputIds.toList()} ids=${inputIds.size}")

                val idsTensor = OnnxTensor.createTensor(
                    environment, LongBuffer.wrap(inputIds), longArrayOf(1, inputIds.size.toLong())
                )
                val maskTensor = OnnxTensor.createTensor(
                    environment, LongBuffer.wrap(mask), longArrayOf(1, mask.size.toLong())
                )
                var encResult: OrtSession.Result? = null
                var decResult: OrtSession.Result? = null
                var startTensor: OnnxTensor? = null
                try {
                    Log.i(TAG, "startDecode: encoder.run")
                    encResult = enc.run(
                        mapOf("input_ids" to idsTensor, "attention_mask" to maskTensor)
                    )
                    val hidden = encResult.get(0) as OnnxTensor
                    Log.i(TAG, "startDecode: encoder done (last_hidden_state ${hidden.info.shape.contentToString()})")
                    startTensor = OnnxTensor.createTensor(
                        environment, LongBuffer.wrap(longArrayOf(decoderStartId)), longArrayOf(1, 1)
                    )
                    Log.i(TAG, "startDecode: decoder step0 run start=$decoderStartId")
                    decResult = dec.run(
                        mapOf(
                            "input_ids" to startTensor,
                            "encoder_hidden_states" to hidden,
                            "encoder_attention_mask" to maskTensor,
                        )
                    )
                    val next = argmax(decResult.get(0) as OnnxTensor)
                    Log.i(TAG, "startDecode: decoder step0 next=$next presentOutputs=${decResult.size() - 1}")
                    // Keep encoder outputs + present k/v alive for the steps.
                    encHidden = hidden
                    encMask = maskTensor
                    past = takePast(decResult)
                    decoding.set(true)
                    replyLong(result, next)
                } finally {
                    runCatching { idsTensor.close() }
                    runCatching { startTensor?.close() }
                    // encResult/decResult intentionally NOT closed: their
                    // tensors live on as encHidden/past. The logits tensor
                    // (index 0) is closed inside argmax.
                }
            } catch (e: Exception) {
                Log.e(TAG, "startDecode error", e)
                endDecodeLocked()
                replyError(result, "DECODE_ERROR", e.message ?: e.toString())
            }
        }
    }

    fun step(nextId: Long, result: MethodChannel.Result) {
        ensureThread()
        handler?.post {
            try {
                val environment = env ?: throw IllegalStateException("sessions not loaded")
                val decPast = decoderPast ?: throw IllegalStateException("sessions not loaded")
                val mask = encMask ?: throw IllegalStateException("no active decode")
                val currentPast = past ?: throw IllegalStateException("no active decode")
                Log.i(TAG, "step: in=$nextId pastLayers=${numLayers} pastTensors=${currentPast.size}")

                var inputTensor: OnnxTensor? = null
                var stepResult: OrtSession.Result? = null
                try {
                    inputTensor = OnnxTensor.createTensor(
                        environment, LongBuffer.wrap(longArrayOf(nextId)), longArrayOf(1, 1)
                    )
                    val feeds = HashMap<String, OnnxTensor>(2 + currentPast.size)
                    feeds["input_ids"] = inputTensor
                    feeds["encoder_attention_mask"] = mask
                    for (i in 0 until numLayers) {
                        val base = i * 4
                        feeds["past_key_values.$i.decoder.key"] = currentPast[base]
                        feeds["past_key_values.$i.decoder.value"] = currentPast[base + 1]
                        feeds["past_key_values.$i.encoder.key"] = currentPast[base + 2]
                        feeds["past_key_values.$i.encoder.value"] = currentPast[base + 3]
                    }
                    stepResult = decPast.run(feeds)
                    val next = argmax(stepResult.get(0) as OnnxTensor)
                    val newPast = takePast(stepResult)
                    // Replace past: close the previous generation's tensors.
                    for (t in currentPast) runCatching { t.close() }
                    past = newPast
                    Log.i(TAG, "step: next=$next")
                    replyLong(result, next)
                } finally {
                    runCatching { inputTensor?.close() }
                }
            } catch (e: Exception) {
                Log.e(TAG, "step error", e)
                endDecodeLocked()
                replyError(result, "DECODE_ERROR", e.message ?: e.toString())
            }
        }
    }

    fun endDecode(result: MethodChannel.Result?) {
        ensureThread()
        handler?.post {
            endDecodeLocked()
            result?.let { r -> reply(r, true) }
        }
    }

    fun release(result: MethodChannel.Result?) {
        ensureThread()
        handler?.post {
            endDecodeLocked()
            runCatching { encoder?.close() }
            runCatching { decoder?.close() }
            runCatching { decoderPast?.close() }
            encoder = null
            decoder = null
            decoderPast = null
            numLayers = 0
            result?.let { r -> reply(r, true) }
        }
    }

    // ----------------------------------------------------------------------

    /** Outputs 1..n of a decoder run are the present k/v tensors (kept). */
    private fun takePast(result: OrtSession.Result): MutableList<OnnxTensor> {
        val out = ArrayList<OnnxTensor>(numLayers * 4)
        for (i in 1 until result.size()) {
            out.add(result.get(i) as OnnxTensor)
        }
        return out
    }

    /** Greedy argmax over the last position's logits; closes the tensor. */
    private fun argmax(logits: OnnxTensor): Long {
        val buf = logits.floatBuffer
        var best = 0
        var bestVal = Float.NEGATIVE_INFINITY
        for (i in 0 until buf.capacity()) {
            val v = buf.get(i)
            if (v > bestVal) {
                bestVal = v
                best = i
            }
        }
        runCatching { logits.close() }
        return best.toLong()
    }

    private fun endDecodeLocked() {
        past?.let { for (t in it) runCatching { t.close() } }
        past = null
        runCatching { encHidden?.close() }
        runCatching { encMask?.close() }
        encHidden = null
        encMask = null
        decoding.set(false)
    }

    private fun reply(result: MethodChannel.Result, value: Any) {
        main.post { result.success(value) }
    }

    private fun replyLong(result: MethodChannel.Result, value: Long) {
        main.post { result.success(value) }
    }

    private fun replyError(result: MethodChannel.Result, code: String, message: String) {
        main.post { result.error(code, message, null) }
    }
}
