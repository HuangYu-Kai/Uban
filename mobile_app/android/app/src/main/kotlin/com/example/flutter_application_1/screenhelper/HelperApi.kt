package com.example.flutter_application_1.screenhelper

import android.content.Context
import android.util.Log
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID

/** 後端分析結果。 */
sealed class HelperResult {
    data class Success(val speech: String, val nodeId: Int?, val sensitive: Boolean) : HelperResult()
    object AuthMissing : HelperResult()
    data class NetworkError(val reason: String) : HelperResult()
}

/** 呼叫 /api/screen_helper/analyze 與讀取 Flutter 寫入的設定。需在背景執行緒呼叫。 */
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

    fun analyze(
        ctx: Context,
        jpeg: ByteArray?,
        nodesJson: String,
        pkg: String,
        question: String?,
    ): HelperResult {
        val token = token(ctx) ?: return HelperResult.AuthMissing
        val boundary = "----uban" + UUID.randomUUID().toString().replace("-", "")
        var conn: HttpURLConnection? = null
        return try {
            conn = (URL(baseUrl(ctx) + "/api/screen_helper/analyze").openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 10_000
                readTimeout = 50_000  // 後端呼叫 Ollama 上限 45 秒
                doOutput = true
                setRequestProperty("Authorization", "Bearer $token")
                setRequestProperty("Content-Type", "multipart/form-data; boundary=$boundary")
            }
            val body = ByteArrayOutputStream()
            fun text(name: String, value: String) {
                body.write("--$boundary\r\nContent-Disposition: form-data; name=\"$name\"\r\n\r\n".toByteArray())
                body.write(value.toByteArray(Charsets.UTF_8))
                body.write("\r\n".toByteArray())
            }
            if (jpeg != null) {
                body.write(
                    ("--$boundary\r\nContent-Disposition: form-data; name=\"image\"; filename=\"shot.jpg\"\r\n" +
                        "Content-Type: image/jpeg\r\n\r\n").toByteArray()
                )
                body.write(jpeg)
                body.write("\r\n".toByteArray())
            }
            text("nodes", nodesJson)
            text("package", pkg)
            if (!question.isNullOrBlank()) text("question", question)
            body.write("--$boundary--\r\n".toByteArray())
            conn.setFixedLengthStreamingMode(body.size())
            conn.outputStream.use { body.writeTo(it) }

            val code = conn.responseCode
            if (code == 401 || code == 403) return HelperResult.AuthMissing
            if (code !in 200..299) return HelperResult.NetworkError("http $code")
            val resp = conn.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
            val json = JSONObject(resp)
            val speech = json.optString("speech", "").trim()
            if (speech.isEmpty()) return HelperResult.NetworkError("empty speech")
            val nodeId = if (json.isNull("node_id")) null else json.optInt("node_id", -1).takeIf { it >= 0 }
            Log.i(TAG, "analyze ok: node=$nodeId elapsed=${json.optInt("elapsed_ms")}ms")
            HelperResult.Success(speech, nodeId, json.optBoolean("sensitive", false))
        } catch (e: Exception) {
            Log.w(TAG, "analyze failed", e)
            HelperResult.NetworkError(e.javaClass.simpleName)
        } finally {
            conn?.disconnect()
        }
    }
}
