package com.example.flutter_application_1.screenhelper

import android.content.Context
import android.util.Log
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID

/**
 * 後端分析結果。
 * done／step／canTap 是 v2 新增欄位；舊後端沒回就當 false／0／false，行為退回單步模式。
 * targetText 要原樣塞回下一輪的 history，後端才知道前幾步已經指過什麼。
 */
sealed class HelperResult {
    data class Success(
        val speech: String,
        val nodeId: Int?,
        val targetText: String,
        val sensitive: Boolean,
        val done: Boolean = false,
        val step: Int = 0,
        val canTap: Boolean = false,
        val serverMs: Int = -1,
    ) : HelperResult()
    object AuthMissing : HelperResult()
    data class NetworkError(val reason: String) : HelperResult()
}

/** 「問家人」的送出結果。delivered=false 代表後端沒能通知到家人，message 仍可念給長輩聽。 */
sealed class FamilyResult {
    data class Done(val delivered: Boolean, val message: String) : FamilyResult()
    object AuthMissing : FamilyResult()
    data class NetworkError(val reason: String) : FamilyResult()
}

/** 呼叫 /api/screen_helper 底下的端點與讀取 Flutter 寫入的設定。需在背景執行緒呼叫。 */
object HelperApi {
    private const val TAG = "ScreenHelper"
    private const val DEFAULT_BASE = "https://localhost-0.tail5abf5e.ts.net"

    // Flutter shared_preferences 的檔名；key 一律帶 "flutter." 前綴。
    private const val PREFS = "FlutterSharedPreferences"

    fun baseUrl(ctx: Context): String {
        val v = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString("flutter.screen_helper_base_url", null)
        return (if (v.isNullOrBlank()) DEFAULT_BASE else v).trim().trimEnd('/')
    }

    fun token(ctx: Context): String? =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString("flutter.access_token", null)?.trim()?.takeIf { it.isNotEmpty() }

    /** TTS 串流網址（edge 引擎）。 */
    fun ttsUrl(ctx: Context, text: String): String =
        baseUrl(ctx) + "/api/voice/tts/stream?engine=edge&text=" +
            java.net.URLEncoder.encode(text, "UTF-8")

    /** multipart 表單組裝：文字欄位與可省略的 JPEG，全部在記憶體裡完成。 */
    private class Multipart {
        val boundary = "----uban" + UUID.randomUUID().toString().replace("-", "")
        private val body = ByteArrayOutputStream()

        fun text(name: String, value: String) {
            body.write("--$boundary\r\nContent-Disposition: form-data; name=\"$name\"\r\n\r\n".toByteArray())
            body.write(value.toByteArray(Charsets.UTF_8))
            body.write("\r\n".toByteArray())
        }

        fun jpeg(name: String, bytes: ByteArray) {
            body.write(
                ("--$boundary\r\nContent-Disposition: form-data; name=\"$name\"; filename=\"shot.jpg\"\r\n" +
                    "Content-Type: image/jpeg\r\n\r\n").toByteArray()
            )
            body.write(bytes)
            body.write("\r\n".toByteArray())
        }

        fun finish(): ByteArray {
            body.write("--$boundary--\r\n".toByteArray())
            return body.toByteArray()
        }
    }

    /** 送出 multipart POST，回傳 (HTTP 狀態碼, 回應本文；非 2xx 時為空字串)。網路例外由呼叫端接。 */
    private fun post(
        ctx: Context,
        token: String,
        path: String,
        readTimeoutMs: Int,
        build: Multipart.() -> Unit,
    ): Pair<Int, String> {
        val mp = Multipart().apply(build)
        val payload = mp.finish()
        var conn: HttpURLConnection? = null
        try {
            conn = (URL(baseUrl(ctx) + path).openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 10_000
                readTimeout = readTimeoutMs
                doOutput = true
                setRequestProperty("Authorization", "Bearer $token")
                setRequestProperty("Content-Type", "multipart/form-data; boundary=${mp.boundary}")
            }
            conn.setFixedLengthStreamingMode(payload.size)
            conn.outputStream.use { it.write(payload) }
            val code = conn.responseCode
            if (code !in 200..299) return code to ""
            val resp = conn.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
            return code to resp
        } finally {
            conn?.disconnect()
        }
    }

    /**
     * 分析目前畫面。goal／historyJson 只在「帶步驟」模式才有值：
     * goal 是長輩一開始說的目標，historyJson 是前幾步 [{"speech","target"}]（≤8 筆），
     * 後端靠它判斷已經做到哪、這步要指哪裡、是否已完成。
     */
    fun analyze(
        ctx: Context,
        jpeg: ByteArray?,
        nodesJson: String,
        pkg: String,
        question: String?,
        goal: String? = null,
        historyJson: String? = null,
    ): HelperResult {
        val token = token(ctx) ?: return HelperResult.AuthMissing
        return try {
            val (code, resp) = post(ctx, token, "/api/screen_helper/analyze", 50_000) {  // 後端呼叫 Ollama 上限 45 秒
                if (jpeg != null) jpeg("image", jpeg)
                text("nodes", nodesJson)
                text("package", pkg)
                if (!question.isNullOrBlank()) text("question", question)
                if (!goal.isNullOrBlank()) text("goal", goal)
                if (!historyJson.isNullOrBlank()) text("history", historyJson)
            }
            if (code == 401 || code == 403) return HelperResult.AuthMissing
            if (code !in 200..299) return HelperResult.NetworkError("http $code")
            val json = JSONObject(resp)
            val speech = json.optString("speech", "").trim()
            if (speech.isEmpty()) return HelperResult.NetworkError("empty speech")
            val nodeId = if (json.isNull("node_id")) null else json.optInt("node_id", -1).takeIf { it >= 0 }
            val serverMs = json.optInt("elapsed_ms", -1)
            Log.i(TAG, "analyze ok: node=$nodeId elapsed=${serverMs}ms")
            HelperResult.Success(
                speech = speech,
                nodeId = nodeId,
                targetText = if (json.isNull("target_text")) "" else json.optString("target_text", ""),
                sensitive = json.optBoolean("sensitive", false),
                done = json.optBoolean("done", false),
                step = json.optInt("step", 0),
                canTap = json.optBoolean("can_tap", false),
                serverMs = serverMs,
            )
        } catch (e: Exception) {
            Log.w(TAG, "analyze failed", e)
            HelperResult.NetworkError(e.javaClass.simpleName)
        }
    }

    /**
     * 暖機：叫後端先把模型載進記憶體，長輩第一次按才不用吃冷啟動（實測第一次 28 秒、之後約 10 秒）。
     * 結果一律忽略，失敗也不影響正常使用。
     */
    fun warm(ctx: Context) {
        val token = token(ctx) ?: return
        try {
            val (code, _) = post(ctx, token, "/api/screen_helper/warm", 45_000) {}
            Log.i(TAG, "warm http $code")
        } catch (e: Exception) {
            Log.i(TAG, "warm failed: ${e.javaClass.simpleName}")
        }
    }

    /**
     * 問家人：把長輩的問題與小嘎剛說的話送給家屬。sensitive=true 時不帶截圖——
     * 付款、密碼等畫面的內容不可離開手機。
     */
    fun askFamily(
        ctx: Context,
        question: String,
        pkg: String,
        appLabel: String,
        helperSpeech: String,
        sensitive: Boolean,
        jpeg: ByteArray?,
    ): FamilyResult {
        val token = token(ctx) ?: return FamilyResult.AuthMissing
        return try {
            val (code, resp) = post(ctx, token, "/api/screen_helper/ask_family", 20_000) {
                text("question", question)
                text("package", pkg)
                text("app_label", appLabel)
                text("helper_speech", helperSpeech)
                text("sensitive", sensitive.toString())
                if (jpeg != null && !sensitive) jpeg("image", jpeg)
            }
            if (code == 401 || code == 403) return FamilyResult.AuthMissing
            if (code !in 200..299) return FamilyResult.NetworkError("http $code")
            val json = JSONObject(resp)
            val delivered = json.optBoolean("delivered", false)
            val msg = json.optString("message", "").trim().ifEmpty {
                if (delivered) "好，我已經請家人幫忙看了喔。" else "我暫時聯絡不到家人，您可以直接打電話給他們喔。"
            }
            Log.i(TAG, "ask_family delivered=$delivered")
            FamilyResult.Done(delivered, msg)
        } catch (e: Exception) {
            Log.w(TAG, "ask_family failed", e)
            FamilyResult.NetworkError(e.javaClass.simpleName)
        }
    }
}
