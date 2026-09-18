package com.example.downoader

import android.content.Context
import android.content.Intent
import android.os.SystemClock
import androidx.core.content.FileProvider
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.abs

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
    private val playerClientArgs = listOf(
        "--extractor-args" to "youtube:player_client=default,tv_simply",
    )

    // Elk gelijktijdig fragment houdt een eigen buffer in het python-proces.
    // Op een telefoon is geheugen de schaarse resource — en geheugendruk was
    // precies wat de app liet afschieten — dus bewust laag.
    private val concurrencyArgs = listOf(
        "--concurrent-fragments" to "2",
    )

    // `--print` zet yt-dlp impliciet in quiet-modus (opts.quiet in
    // yt_dlp/__init__.py), en quiet zet noprogress aan. Zonder deze vlaggen
    // komt er dus geen enkele voortgangsregel binnen en blijft de balk op 0%
    // staan terwijl er wel gedownload wordt.
    private val outputArgs = listOf(
        "--no-quiet" to null,
        "--progress" to null,
        "--newline" to null,
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Python/ffmpeg/yt-dlp uitpakken kost seconden en ~100 MB schrijfwerk.
        // Dat mag niet pas op de Download-tik gebeuren: dan valt zware init
        // samen met het starten van het kindproces. Nu al starten, op de
        // achtergrond, precies een keer per proces.
        beginInit(this)

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
                    "probe" -> {
                        val url = call.argument<String>("url")
                        if (url.isNullOrBlank()) {
                            result.error("YTDLP_ERROR", "URL ontbreekt", null)
                        } else {
                            handleQuery(
                                url,
                                listOf("--flat-playlist" to null, "-J" to null) + playerClientArgs,
                                result,
                            )
                        }
                    }
                    "formats" -> {
                        val url = call.argument<String>("url")
                        if (url.isNullOrBlank()) {
                            result.error("YTDLP_ERROR", "URL ontbreekt", null)
                        } else {
                            handleQuery(
                                url,
                                listOf("--no-playlist" to null, "-J" to null) + playerClientArgs,
                                result,
                            )
                        }
                    }
                    "download" -> handleDownload(call, result)
                    "cancel" -> {
                        killRunningDownload()
                        result.success(null)
                    }
                    "openFile" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("OPEN_FAILED", "Pad ontbreekt", null)
                        } else {
                            try {
                                openFile(path)
                                result.success(null)
                            } catch (e: Exception) {
                                result.error("OPEN_FAILED", e.message, null)
                            }
                        }
                    }
                    "openFolder" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("OPEN_FAILED", "Pad ontbreekt", null)
                        } else {
                            try {
                                openFolder(path)
                                result.success(null)
                            } catch (e: Exception) {
                                result.error("OPEN_FAILED", e.message, null)
                            }
                        }
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
        // Alleen echte share/deeplink-URL's doorgeven. MAIN/LAUNCHER of lege
        // intents negeren — die kunnen de UI laten herladen terwijl het proces
        // blijft draaien.
        val payload = extractIncoming(intent) ?: return
        if (intentChannel != null) {
            intentChannel?.invokeMethod("incomingUrl", payload)
        } else {
            pendingIntent = payload
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        // FlutterActivity is een plain Activity (geen ComponentActivity), dus
        // geen onBackPressedDispatcher beschikbaar. super.onBackPressed()
        // delegeert al naar de Flutter-engine, die zelf via PopScope beslist
        // of de route popt — geen eigen finish-logica nodig.
        super.onBackPressed()
    }

    // Geen finish()-override meer. Die blokkeerde ook legitieme finish()-calls
    // van het framework, waardoor de oude activity als zombie bleef staan en het
    // systeem er een nieuwe instantie bovenop zette: splashscreen + volledige
    // Dart-herstart, terwijl de app niet helemaal sluit. Dat was een pleister op
    // de echte oorzaak (proces werd afgeschoten) en maakte hem onzichtbaar.

    override fun onDestroy() {
        // Activity weg = niemand luistert nog naar voortgang. Het kindproces
        // laten doorlopen levert alleen stapelende python-processen op bij een
        // volgende poging.
        if (!isChangingConfigurations) killRunningDownload()
        super.onDestroy()
    }

    private fun extractIncoming(intent: Intent?): Map<String, String>? {
        if (intent == null) return null
        val payload = parseIncoming(intent) ?: return null
        // Bij een activity-recreate levert het systeem dezelfde start-intent
        // opnieuw aan. Zonder deze check start Dart de download telkens opnieuw:
        // een lus die er uit ziet als "app herstart en downloadt weer niks".
        val key = payload["url"] ?: return payload
        if (key == consumedIntentUrl) return null
        consumedIntentUrl = key
        return payload
    }

    private fun parseIncoming(intent: Intent): Map<String, String>? {
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

    private fun YoutubeDLRequest.addOpt(option: String, value: String?) {
        if (value == null) {
            addOption(option)
        } else {
            addOption(option, value)
        }
    }

    private fun handleInit(result: MethodChannel.Result) {
        beginInit(this)
        Thread {
            try {
                awaitInit()
                runOnUiThread { result.success(null) }
            } catch (e: Throwable) {
                runOnUiThread {
                    result.error("INIT_FAILED", e.message ?: e.toString(), null)
                }
            }
        }.start()
    }

    private fun handleQuery(
        url: String,
        options: List<Pair<String, String?>>,
        result: MethodChannel.Result,
    ) {
        Thread {
            try {
                awaitInit()
                val request = YoutubeDLRequest(url)
                options.forEach { (opt, value) -> request.addOpt(opt, value) }
                val response = YoutubeDL.getInstance().execute(request, null, null)
                runOnUiThread { result.success(response.out) }
            } catch (e: Throwable) {
                runOnUiThread {
                    result.error("YTDLP_ERROR", e.message ?: "onbekende fout", null)
                }
            }
        }.start()
    }

    private fun handleDownload(
        call: io.flutter.plugin.common.MethodCall,
        result: MethodChannel.Result,
    ) {
        val url = call.argument<String>("url")
        val outputDir = call.argument<String>("outputDir")
        val format = call.argument<String>("format")
        if (url.isNullOrBlank() || outputDir.isNullOrBlank() || format.isNullOrBlank()) {
            result.error("DOWNLOAD_FAILED", "url/outputDir/format ontbreekt", null)
            return
        }
        if (!downloadRunning.compareAndSet(false, true)) {
            result.error("DOWNLOAD_FAILED", "Er loopt al een download", null)
            return
        }
        val isPlaylist: Boolean = call.argument("isPlaylist") ?: false
        val formatId: String? = call.argument("formatId")
        val appContext = applicationContext

        // Foreground service starten voordat het kindproces er is, niet erna:
        // juist het aanmaken van dat geheugenhongerige kindproces lokt de kill uit.
        DownloadKeepAliveService.start(appContext, "Bezig met downloaden...")

        Thread {
            try {
                awaitInit()
                File(outputDir).mkdirs()
                val request = YoutubeDLRequest(url)
                request.addOption("-o", "$outputDir/%(title)s.%(ext)s")
                request.addOption("--no-mtime")
                request.addOption("--print", "after_move:FILEPATH::%(filepath)s")
                request.addOption(if (isPlaylist) "--yes-playlist" else "--no-playlist")
                (outputArgs + playerClientArgs + concurrencyArgs).forEach { (opt, value) ->
                    request.addOpt(opt, value)
                }
                if (format == "mp3") {
                    request.addOption("-x")
                    request.addOption("--audio-format", "mp3")
                    request.addOption("--audio-quality", "0")
                } else {
                    request.addOption("-f", formatId ?: "bestvideo+bestaudio/best")
                    request.addOption("--merge-output-format", "mp4")
                }

                // Restant van een eerdere, afgebroken run opruimen: anders weigert
                // execute() de process-id en stapelen python-processen zich op.
                killRunningDownload()

                var lastEmit = 0L
                var lastProgress = -1f
                var lastNotification = 0L
                YoutubeDL.getInstance().execute(request, downloadProcessId) { progress, _, line ->
                    val text = line ?: ""
                    val important = text.contains(FILEPATH_MARKER) ||
                        text.startsWith("[download] Destination:") ||
                        text.startsWith("[ExtractAudio]") ||
                        text.startsWith("[Merger]") ||
                        text.startsWith("ERROR") ||
                        text.startsWith("WARNING")
                    val now = SystemClock.uptimeMillis()
                    // yt-dlp spuit met --newline een regel per voortgangstik uit.
                    // Elke regel ongefilterd naar de UI-thread pompen liet de main
                    // looper vollopen (ANR-gebied) en gaf een setState-rebuild per
                    // regel in Flutter.
                    if (!important &&
                        now - lastEmit < PROGRESS_THROTTLE_MS &&
                        abs(progress - lastProgress) < 1f
                    ) {
                        return@execute
                    }
                    lastEmit = now
                    lastProgress = progress
                    if (progress >= 0f && now - lastNotification > 2000L) {
                        lastNotification = now
                        DownloadKeepAliveService.start(
                            appContext,
                            "Bezig met downloaden... ${progress.toInt()}%",
                        )
                    }
                    runOnUiThread {
                        eventSink?.success(
                            mapOf(
                                "progress" to progress.toDouble(),
                                "line" to text,
                            ),
                        )
                    }
                }
                runOnUiThread { result.success(null) }
            } catch (e: Throwable) {
                // Throwable, niet Exception: een OutOfMemoryError of
                // UnsatisfiedLinkError uit het native deel liet de thread anders
                // stil doodgaan en de Dart-kant eeuwig wachten op een antwoord.
                runOnUiThread {
                    result.error("DOWNLOAD_FAILED", e.message ?: e.toString(), null)
                }
            } finally {
                downloadRunning.set(false)
                DownloadKeepAliveService.stop(appContext)
            }
        }.start()
    }

    private fun killRunningDownload() {
        try {
            YoutubeDL.getInstance().destroyProcessById(downloadProcessId)
        } catch (_: Throwable) {
        }
    }

    private fun openFile(path: String) {
        val file = File(path)
        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        val mimeType = contentResolver.getType(uri) ?: "*/*"
        // Geen FLAG_ACTIVITY_NEW_TASK: die zet onze activity naar de achtergrond
        // alsof de app minimaliseert. We zijn al een Activity.
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mimeType)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(intent)
    }

    private fun openFolder(path: String) {
        val parent = File(path).parentFile ?: File(path)
        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", parent)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "resource/folder")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        try {
            startActivity(intent)
        } catch (e: Exception) {
            // Geen bestandsbeheerder die mappen kan openen: open het bestand zelf.
            openFile(path)
        }
    }

    companion object {
        private const val FILEPATH_MARKER = "FILEPATH::"
        private const val PROGRESS_THROTTLE_MS = 250L
        private const val downloadProcessId = "downoader-download"

        // Proces-breed, niet per Activity: init en het kindproces overleven een
        // activity-recreate, dus de bewaking eromheen moet dat ook doen.
        private val initStarted = AtomicBoolean(false)
        private val initLatch = CountDownLatch(1)
        private val downloadRunning = AtomicBoolean(false)

        @Volatile
        private var initError: String? = null

        @Volatile
        private var consumedIntentUrl: String? = null

        fun beginInit(context: Context) {
            if (!initStarted.compareAndSet(false, true)) return
            val appContext = context.applicationContext
            Thread {
                try {
                    YoutubeDL.getInstance().init(appContext)
                    FFmpeg.init(appContext)
                    // Geen updateYoutubeDL: die download/uitpak kan het proces
                    // killen (app lijkt te minimaliseren) en racet met de
                    // download zelf. De gebundelde yt-dlp is genoeg voor beta.
                } catch (e: Throwable) {
                    initError = e.message ?: e.toString()
                } finally {
                    initLatch.countDown()
                }
            }.start()
        }

        fun awaitInit() {
            initLatch.await()
            initError?.let { throw IllegalStateException(it) }
        }
    }
}
