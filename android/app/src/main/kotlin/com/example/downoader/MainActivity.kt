package com.example.downoader

import android.content.Intent
import androidx.core.content.FileProvider
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "downoader/ytdlp"
    private val progressChannelName = "downoader/ytdlp/progress"
    private val intentChannelName = "downoader/intent"
    private var eventSink: EventChannel.EventSink? = null
    private var intentChannel: MethodChannel? = null
    private var pendingIntent: Map<String, String>? = null

    // android-client levert sinds YouTube's PO/SABR-wijzigingen alleen nog
    // progressive 360p (format 18). default+tv_simply geeft weer alle
    // resoluties (tot 4K). NIET android_vr forceren: die eist inmiddels ook
    // GVS PO-token → HTTP 403.
    private val speedOptions = listOf(
        "--extractor-args",
        "youtube:player_client=default,tv_simply",
    )
    private val concurrencyOptions = listOf("--concurrent-fragments", "4")

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, progressChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "init" -> handleInit(result)
                    "probe" -> handleQuery(call.argument("url")!!, listOf("--flat-playlist", "-J") + speedOptions, result)
                    "formats" -> handleQuery(call.argument("url")!!, listOf("--no-playlist", "-J") + speedOptions, result)
                    "download" -> handleDownload(call, result)
                    "openFile" -> {
                        openFile(call.argument("path")!!)
                        result.success(null)
                    }
                    "openFolder" -> {
                        openFolder(call.argument("path")!!)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        intentChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, intentChannelName)
        intentChannel?.setMethodCallHandler { call, result ->
            if (call.method == "getInitialUrl") {
                val payload = pendingIntent ?: extractIncoming(intent)
                pendingIntent = null
                result.success(payload)
            } else {
                result.notImplemented()
            }
        }
        if (pendingIntent == null) {
            pendingIntent = extractIncoming(intent)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val payload = extractIncoming(intent) ?: return
        if (intentChannel != null) {
            intentChannel?.invokeMethod("incomingUrl", payload)
        } else {
            pendingIntent = payload
        }
    }

    private fun extractIncoming(intent: Intent?): Map<String, String>? {
        if (intent == null) return null
        if (Intent.ACTION_SEND == intent.action) {
            val text = intent.getStringExtra(Intent.EXTRA_TEXT) ?: return null
            val url = Regex("https?://\\S+").find(text)?.value ?: text.trim()
            if (url.isEmpty()) return null
            return mapOf("url" to url)
        }
        val data = intent.data ?: return null
        if (data.scheme == "downoader") {
            val url = data.getQueryParameter("url") ?: return null
            val format = data.getQueryParameter("format")
            return if (format.isNullOrEmpty()) {
                mapOf("url" to url)
            } else {
                mapOf("url" to url, "format" to format)
            }
        }
        val asString = data.toString()
        if (asString.startsWith("http://") || asString.startsWith("https://")) {
            return mapOf("url" to asString)
        }
        return null
    }

    private fun handleInit(result: MethodChannel.Result) {
        Thread {
            try {
                YoutubeDL.getInstance().init(applicationContext)
                FFmpeg.init(applicationContext)
                try {
                    // YouTube wijzigt regelmatig zijn anti-bot checks; een verouderde
                    // meegeleverde yt-dlp-versie geeft dan 403 op elke download.
                    YoutubeDL.getInstance().updateYoutubeDL(applicationContext)
                } catch (_: Exception) {
                    // Geen netwerk of al up-to-date: doorgaan met de meegeleverde versie.
                }
                runOnUiThread { result.success(null) }
            } catch (e: Exception) {
                runOnUiThread { result.error("INIT_FAILED", e.message, null) }
            }
        }.start()
    }

    private fun handleQuery(url: String, options: List<String>, result: MethodChannel.Result) {
        Thread {
            try {
                val request = YoutubeDLRequest(url)
                options.forEach { request.addOption(it) }
                val response = YoutubeDL.getInstance().execute(request, null, null)
                runOnUiThread { result.success(response.out) }
            } catch (e: Exception) {
                runOnUiThread { result.error("YTDLP_ERROR", e.message ?: "onbekende fout", null) }
            }
        }.start()
    }

    private fun handleDownload(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        val url: String = call.argument("url")!!
        val outputDir: String = call.argument("outputDir")!!
        val isPlaylist: Boolean = call.argument("isPlaylist") ?: false
        val format: String = call.argument("format")!!
        val formatId: String? = call.argument("formatId")

        Thread {
            try {
                val request = YoutubeDLRequest(url)
                request.addOption("-o", "$outputDir/%(title)s.%(ext)s")
                request.addOption("--newline")
                request.addOption("--no-mtime")
                request.addOption("--print", "after_move:FILEPATH::%(filepath)s")
                request.addOption(if (isPlaylist) "--yes-playlist" else "--no-playlist")
                (speedOptions + concurrencyOptions).forEach { request.addOption(it) }
                if (format == "mp3") {
                    request.addOption("-x")
                    request.addOption("--audio-format", "mp3")
                    request.addOption("--audio-quality", "0")
                } else {
                    request.addOption("-f", formatId ?: "bestvideo+bestaudio/best")
                    request.addOption("--merge-output-format", "mp4")
                }

                YoutubeDL.getInstance().execute(request, null) { progress, _, line ->
                    runOnUiThread {
                        eventSink?.success(mapOf("progress" to progress.toDouble(), "line" to (line ?: "")))
                    }
                }
                runOnUiThread { result.success(null) }
            } catch (e: Exception) {
                runOnUiThread { result.error("DOWNLOAD_FAILED", e.message ?: "onbekende fout", null) }
            }
        }.start()
    }

    private fun openFile(path: String) {
        val file = File(path)
        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        val mimeType = contentResolver.getType(uri) ?: "*/*"
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mimeType)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    private fun openFolder(path: String) {
        val parent = File(path).parentFile ?: File(path)
        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", parent)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "resource/folder")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            startActivity(intent)
        } catch (e: Exception) {
            // Geen bestandsbeheerder die mappen kan openen: open het bestand zelf.
            openFile(path)
        }
    }
}
