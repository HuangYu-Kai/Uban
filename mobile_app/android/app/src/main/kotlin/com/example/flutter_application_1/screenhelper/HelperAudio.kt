package com.example.flutter_application_1.screenhelper

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import java.util.Locale

/**
 * 小嘎語音的依序播放佇列（主執行緒使用）。
 * 項目一個接一個播：預錄音檔（raw）或 TTS 串流；串流失敗或 0 秒就改用系統 TextToSpeech。
 */
class HelperAudio(private val ctx: Context) {
    private companion object { const val TAG = "ScreenHelper" }

    private sealed class Item {
        class Raw(val resId: Int) : Item()
        class Speak(val text: String) : Item()
    }

    private val main = Handler(Looper.getMainLooper())
    private val queue = ArrayDeque<Item>()
    private var playing = false
    private var player: MediaPlayer? = null
    private var generation = 0 // stopAll 後讓舊的回呼失效

    private val audioManager = ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val attrs = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_ASSISTANT)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        .build()
    private var focusRequest: AudioFocusRequest? = null

    private var tts: TextToSpeech? = null
    private var ttsReady = false

    init {
        tts = TextToSpeech(ctx) { status ->
            ttsReady = status == TextToSpeech.SUCCESS
            if (ttsReady) {
                tts?.language = Locale.TAIWAN
                tts?.setAudioAttributes(attrs)
            } else Log.w(TAG, "TTS init failed: $status")
        }
    }

    fun playRaw(resId: Int) = enqueue(Item.Raw(resId))

    fun speak(text: String) = enqueue(Item.Speak(text))

    private fun enqueue(item: Item) {
        queue.addLast(item)
        if (!playing) next()
    }

    private fun next() {
        val item = queue.removeFirstOrNull()
        if (item == null) {
            playing = false
            abandonFocus()
            return
        }
        playing = true
        requestFocus()
        val gen = generation
        when (item) {
            is Item.Raw -> playRawItem(item.resId, gen)
            is Item.Speak -> playStream(item.text, gen)
        }
    }

    private fun advance(gen: Int) {
        if (gen != generation) return
        releasePlayer()
        next()
    }

    private fun playRawItem(resId: Int, gen: Int) {
        try {
            val mp = MediaPlayer()
            player = mp
            mp.setAudioAttributes(attrs)
            val afd = ctx.resources.openRawResourceFd(resId)
            mp.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
            afd.close()
            mp.setOnCompletionListener { advance(gen) }
            mp.setOnErrorListener { _, _, _ -> advance(gen); true }
            mp.setOnPreparedListener { it.start() }
            mp.prepareAsync()
        } catch (e: Exception) {
            Log.w(TAG, "playRaw failed", e)
            advance(gen)
        }
    }

    private fun playStream(text: String, gen: Int) {
        var fellBack = false
        val fallback = {
            if (!fellBack && gen == generation) {
                fellBack = true
                releasePlayer()
                speakWithTts(text, gen)
            }
        }
        try {
            val mp = MediaPlayer()
            player = mp
            mp.setAudioAttributes(attrs)
            mp.setDataSource(HelperApi.ttsUrl(ctx, text))
            // 串流 MP3 沒有 Content-Length，duration 常是 -1，不能拿來判斷有沒有聲音；
            // 改看實際播了多久：伺服器回 200 但 0 bytes 時會幾乎立刻播完。
            var startedAt = 0L
            mp.setOnPreparedListener {
                startedAt = android.os.SystemClock.elapsedRealtime()
                it.start()
            }
            mp.setOnCompletionListener {
                val playedMs = android.os.SystemClock.elapsedRealtime() - startedAt
                if (playedMs < 300) fallback() else if (!fellBack) advance(gen)
            }
            mp.setOnErrorListener { _, _, _ -> fallback(); true }
            mp.prepareAsync()
        } catch (e: Exception) {
            Log.w(TAG, "stream failed", e)
            fallback()
        }
    }

    private fun speakWithTts(text: String, gen: Int) {
        val t = tts
        if (t == null || !ttsReady) {
            Log.w(TAG, "TTS not ready, skip")
            advance(gen)
            return
        }
        t.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) {}
            override fun onDone(utteranceId: String?) { main.post { advance(gen) } }
            @Deprecated("Deprecated in Java")
            override fun onError(utteranceId: String?) { main.post { advance(gen) } }
        })
        t.speak(text, TextToSpeech.QUEUE_FLUSH, null, "helper_$gen")
    }

    private fun releasePlayer() {
        player?.let {
            runCatching {
                it.setOnCompletionListener(null)
                it.setOnErrorListener(null)
                it.release()
            }
        }
        player = null
    }

    private fun requestFocus() {
        if (focusRequest != null) return
        val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
            .setAudioAttributes(attrs)
            .setOnAudioFocusChangeListener { }
            .build()
        focusRequest = req
        audioManager.requestAudioFocus(req)
    }

    private fun abandonFocus() {
        focusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
        focusRequest = null
    }

    fun stopAll() {
        generation++
        queue.clear()
        releasePlayer()
        runCatching { tts?.stop() }
        playing = false
        abandonFocus()
    }

    fun release() {
        stopAll()
        runCatching { tts?.shutdown() }
        tts = null
    }
}
