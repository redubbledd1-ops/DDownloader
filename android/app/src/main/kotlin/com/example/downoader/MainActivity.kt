package com.example.downoader

import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.util.Log
import androidx.core.content.FileProvider
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import com.yausername.youtubedl_common.SharedPrefsHelper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
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
                    "version" -> {
                        val appContext = applicationContext
                        Thread {
                            val version = try {
                                ensureInit(appContext)
                                realYtDlpVersion()
                            } catch (_: Throwable) {
                                null
                            }
                            runOnUiThread { result.success(version) }
                        }.start()
                    }
                    "update" -> handleUpdate(result)
                    "shareText" -> {
                        val text = call.argument<String>("text")
                        if (text.isNullOrEmpty()) {
                            result.error("SHARE_FAILED", "Tekst ontbreekt", null)
                        } else {
                            try {
                                shareText(text, call.argument<String>("subject"))
                                result.success(null)
                            } catch (e: Exception) {
                                result.error("SHARE_FAILED", e.message, null)
                            }
                        }
                    }
                    "shareFile" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("SHARE_FAILED", "Pad ontbreekt", null)
                        } else {
                            try {
                                shareFile(path)
                                result.success(null)
                            } catch (e: Exception) {
                                result.error("SHARE_FAILED", e.message, null)
                            }
                        }
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
        val appContext = applicationContext
        Thread {
            try {
                ensureInit(appContext)
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
        val appContext = applicationContext
        Thread {
            try {
                ensureInit(appContext)
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
                ensureInit(appContext)
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
                        DownloadKeepAliveService.updateText(
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

    /**
     * Haalt de nieuwste yt-dlp op. De gebundelde versie veroudert snel: YouTube
     * breekt de extractie om de paar weken, en een yt-dlp van maanden oud geeft
     * "HTTP Error 403: Forbidden" of "Requested format is not available".
     *
     * Dit stond eerder uit omdat het downloaden/uitpakken het proces kon laten
     * afschieten. Met de foreground service eromheen is dat afgedekt.
     */
    private fun handleUpdate(result: MethodChannel.Result) {
        val appContext = applicationContext
        if (!updateRunning.compareAndSet(false, true)) {
            result.error("UPDATE_FAILED", "Bijwerken loopt al", null)
            return
        }
        DownloadKeepAliveService.start(appContext, "yt-dlp bijwerken...")
        Thread {
            try {
                ensureInit(appContext)
                val before = realYtDlpVersion()
                val stored = YoutubeDL.getInstance().version(appContext)
                if (before != null && before != stored) {
                    // checkForUpdate() vergelijkt de online tag met deze
                    // opgeslagen waarde en meldt ALREADY_UP_TO_DATE zodra ze
                    // gelijk zijn - ook als het binaire bestand daar niet bij
                    // past. Een afgebroken eerdere update laat precies die
                    // toestand achter: markering nieuw, binary oud. Leegmaken
                    // dwingt een echte download af.
                    Log.w(
                        LOG_TAG,
                        "yt-dlp markering ($stored) wijkt af van binary ($before), forceer update",
                    )
                    SharedPrefsHelper.update(appContext, DLP_VERSION_KEY, "")
                }
                YoutubeDL.getInstance().updateYoutubeDL(
                    appContext,
                    YoutubeDL.UpdateChannel.STABLE,
                )
                // Niet op de status-enum afgaan maar op wat er echt draait.
                val after = realYtDlpVersion()
                Log.i(LOG_TAG, "yt-dlp versie: $before -> $after")
                runOnUiThread {
                    result.success(
                        mapOf(
                            "updated" to (after != null && after != before),
                            "version" to (after ?: before),
                        ),
                    )
                }
            } catch (e: Throwable) {
                val detail = describe(e)
                Log.e(LOG_TAG, "yt-dlp update mislukt: $detail", e)
                runOnUiThread { result.error("UPDATE_FAILED", detail, null) }
            } finally {
                updateRunning.set(false)
                DownloadKeepAliveService.stop(appContext)
            }
        }.start()
    }

    /**
     * Vraagt het yt-dlp-bestand zelf om zijn versie, in plaats van de waarde die
     * de library in SharedPreferences bijhoudt. Die twee kunnen uit elkaar lopen
     * als een update halverwege afbreekt, en dan wijst alleen de binary de
     * waarheid aan.
     */
    private fun realYtDlpVersion(): String? = try {
        val request = YoutubeDLRequest(emptyList())
        request.addOption("--version")
        YoutubeDL.getInstance()
            .execute(request, null, null)
            .out
            .trim()
            .lineSequence()
            .map { it.trim() }
            .lastOrNull { it.isNotEmpty() }
    } catch (e: Throwable) {
        Log.w(LOG_TAG, "yt-dlp --version mislukt: ${e.message}")
        null
    }

    private fun killRunningDownload() {
        try {
            YoutubeDL.getInstance().destroyProcessById(downloadProcessId)
        } catch (_: Throwable) {
        }
    }

    // ACTION_SEND i.p.v. ACTION_VIEW: delen levert de share-sheet op (mail,
    // Drive, Bluetooth, Nearby Share, koppeling met de PC), terwijl VIEW op een
    // .txt of op "resource/folder" een lijst willekeurige apps geeft die er
    // niets mee kunnen.
    private fun shareText(text: String, subject: String?) {
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, text)
            if (!subject.isNullOrEmpty()) putExtra(Intent.EXTRA_SUBJECT, subject)
        }
        startActivity(Intent.createChooser(intent, subject ?: "Delen"))
    }

    private fun shareFile(path: String) {
        val file = File(path)
        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = contentResolver.getType(uri) ?: "text/plain"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(Intent.createChooser(intent, file.name))
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

        private const val LOG_TAG = "Downoader"
        private const val DLP_VERSION_KEY = "dlpVersion"

        // Proces-breed, niet per Activity: init en het kindproces overleven een
        // activity-recreate, dus de bewaking eromheen moet dat ook doen.
        private val warmUpStarted = AtomicBoolean(false)
        private val downloadRunning = AtomicBoolean(false)
        private val updateRunning = AtomicBoolean(false)

        @Volatile
        private var initDone = false

        @Volatile
        private var consumedIntentUrl: String? = null

        /** Warmt init op de achtergrond op; fouten komen pas bij ensureInit(). */
        fun beginInit(context: Context) {
            if (!warmUpStarted.compareAndSet(false, true)) return
            val appContext = context.applicationContext
            Thread {
                try {
                    ensureInit(appContext)
                } catch (_: Throwable) {
                    // Stil: de gebruiker krijgt de fout zodra hij iets doet.
                }
            }.start()
        }

        /**
         * Pakt python/ffmpeg/yt-dlp uit als dat nog niet gebeurd is.
         *
         * @Synchronized omdat de opwarm-thread en een Download-tik hier tegelijk
         * kunnen binnenkomen; de tweede wacht dan op de eerste. Belangrijk: een
         * MISLUKTE poging wordt niet gecachet. YoutubeDL.init() is zelf
         * idempotent, dus een volgende tik probeert het echt opnieuw - eerder
         * bleef een fout hangen tot de app herstart werd.
         */
        @Synchronized
        fun ensureInit(context: Context) {
            if (initDone) return
            val appContext = context.applicationContext
            try {
                YoutubeDL.getInstance().init(appContext)
                if (!pythonRuntimeIntact(appContext)) {
                    // init() pakt alleen uit als de map ontbreekt of als de
                    // opgeslagen versiemarkering veranderd is. Een map die wel
                    // bestaat maar incompleet is - proces gekilld tijdens het
                    // uitpakken, opslag vol, of prefs teruggezet uit een backup
                    // terwijl de payload in noBackupFiles staat - blijft dus
                    // voorgoed kapot. Symptoom: elke download faalt met
                    // "CANNOT LINK EXECUTABLE ... libpython3.x.so not found".
                    // De map weggooien maakt de conditie weer waar. init() zelf
                    // keert direct terug zodra initialized gezet is, maar
                    // initPython() is public en pakt wel opnieuw uit.
                    val pythonDir = pythonDir(appContext)
                    Log.w(LOG_TAG, "python-runtime incompleet, opnieuw uitpakken")
                    pythonDir.deleteRecursively()
                    YoutubeDL.getInstance().initPython(appContext, pythonDir)
                }
                if (!pythonRuntimeIntact(appContext)) {
                    throw IllegalStateException(
                        "Python-runtime onvolledig uitgepakt (libpython3*.so ontbreekt " +
                            "in ${pythonDir(appContext)}). Meestal te weinig vrije " +
                            "opslag: er is ongeveer 300 MB nodig.",
                    )
                }
                // Een lege ffmpeg-map net zo opruimen voordat FFmpeg.init()
                // concludeert dat uitpakken niet meer nodig is.
                val ffmpegDir = ffmpegDir(appContext)
                if (ffmpegDir.exists() && (ffmpegDir.list()?.size ?: 0) == 0) {
                    ffmpegDir.deleteRecursively()
                }
                FFmpeg.init(appContext)
                // Geen updateYoutubeDL: die download/uitpak kan het proces
                // killen (app lijkt te minimaliseren) en racet met de download
                // zelf. De gebundelde yt-dlp is genoeg voor beta.
                initDone = true
            } catch (e: Throwable) {
                val detail = describe(e)
                Log.e(LOG_TAG, "init mislukt: $detail", e)
                throw IllegalStateException(detail, e)
            }
        }

        private fun packagesDir(appContext: Context) =
            File(appContext.noBackupFilesDir, "youtubedl-android/packages")

        private fun pythonDir(appContext: Context) = File(packagesDir(appContext), "python")

        private fun ffmpegDir(appContext: Context) = File(packagesDir(appContext), "ffmpeg")

        /**
         * De libpython.so in nativeLibraryDir is maar een kleine starter. De
         * echte interpreter (libpython3.x.so) en libandroid-support.so komen
         * uit het uitgepakte usr/lib en worden via LD_LIBRARY_PATH gevonden.
         * Ontbreken die, dan faalt de dynamische linker met CANNOT LINK
         * EXECUTABLE nog voordat yt-dlp ook maar iets doet.
         */
        private fun pythonRuntimeIntact(appContext: Context): Boolean {
            val names = File(pythonDir(appContext), "usr/lib").list() ?: return false
            val interpreter = names.any { it.startsWith("libpython3") && it.contains(".so") }
            val support = names.any { it == "libandroid-support.so" }
            return interpreter && support
        }

        /**
         * youtubedl-android verpakt alles in YoutubeDLException("failed to
         * initialize", cause). Die tekst zegt niets, dus lopen we de cause-keten
         * af en plakken die aan elkaar - anders houdt de gebruiker een
         * onbruikbare foutmelding over.
         */
        private fun describe(error: Throwable): String {
            val parts = mutableListOf<String>()
            var current: Throwable? = error
            var guard = 0
            while (current != null && guard++ < 8) {
                val name = current.javaClass.simpleName
                val message = current.message
                parts += if (message.isNullOrBlank()) name else "$name: $message"
                if (current.cause === current) break
                current = current.cause
            }
            return parts.joinToString(" <- ")
        }
    }
}
