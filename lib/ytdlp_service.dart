import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'models.dart';
import 'settings.dart';

// Oudere installaties waarbij de gebruiker yt-dlp zelf naar deze plek had
// gezet blijven werken. Release-builds bundelen yt-dlp/ffmpeg/deno in
// `{installDir}/tools/` naast de exe (zie scripts/build-windows-installer.ps1).
const String _legacyYtDlpPath = r'C:\Program Files\yt-dlpd.exe';

// yt-dlp's eigen "latest"-release-alias: altijd de nieuwste standalone exe,
// geen versienummer nodig. yt-dlp breekt regelmatig door YouTube-wijzigingen
// en heeft daarom vaak updates nodig — zelf bundelen zou na verloop van
// tijd stilzwijgend kapot gaan.
const String _ytDlpDownloadUrl =
    'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe';

// Portable, statisch gelinkte Windows-build (GPL, BtbN's altijd-actuele
// "latest" release-tag). Gebruikt als het systeem geen eigen ffmpeg heeft.
const String _ffmpegDownloadUrl =
    'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip';

// Portable Deno-build (single exe), gebruikt als JS-runtime voor yt-dlp's
// nsig-oplosser (zie hieronder bij _ensureJsRuntimeArgs).
const String _denoDownloadUrl =
    'https://github.com/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip';

const MethodChannel _androidChannel = MethodChannel('downoader/ytdlp');
const EventChannel _androidProgressChannel = EventChannel(
  'downoader/ytdlp/progress',
);

final RegExp _percentRegex = RegExp(r'\[download\]\s+([\d.]+)%');
const String _filepathMarker = 'FILEPATH::';

// Forceert echte UTF-8-output van yt-dlp (Python-exe) i.p.v. de Windows-
// systeem-codepage, die niet-ASCII tekens in titels/output kan verminken.
final Map<String, String> _ytDlpEnvironment = {
  ...Platform.environment,
  'PYTHONUTF8': '1',
  'PYTHONIOENCODING': 'utf-8',
};

/// Haalt het pad uit een FILEPATH::-regel en knipt mojibake (U+FFFD) weg.
String? _extractFilepath(String line) {
  final idx = line.indexOf(_filepathMarker);
  if (idx < 0) return null;
  var path = line.substring(idx + _filepathMarker.length).trim();
  final bad = path.indexOf('\uFFFD');
  if (bad >= 0) path = path.substring(0, bad).trim();
  if (path.isEmpty) return null;
  // Alleen accepteren als het bestand echt bestaat — voorkomt dat een
  // corrupte/incomplete stdout-regel in de downloadlijst belandt.
  if (!File(path).existsSync()) return null;
  return path;
}

// android-client levert sinds YouTube's PO/SABR-wijzigingen alleen nog
// progressive 360p (format 18). default+tv_simply geeft weer alle
// resoluties (tot 4K). tv_simply-HTTPS kan een PO-token-waarschuwing
// geven maar wordt dan overgeslagen; andere clients in default blijven werken.
// NIET android_vr forceren: die eist inmiddels ook GVS PO-token → HTTP 403.
const List<String> _playerClientArgs = [
  '--extractor-args',
  'youtube:player_client=default,tv_simply',
];
// Op Windows: 1 fragment tegelijk. Concurrent fragments houden .part-handles
// langer open en botsen met Defender/OneDrive (WinError 32 bij rename).
const List<String> _concurrencyArgs = ['--concurrent-fragments', '1'];

// YouTube's tijdelijke bot-check/rate-limit ("The page needs to be
// reloaded", HTTP 429/403) lost meestal vanzelf op na een korte pauze —
// dit is geen echte downloadlimiet van yt-dlp of deze app, maar aan
// YouTube's kant. Op zulke fouten proberen we het na een korte pauze
// gewoon opnieuw i.p.v. de gebruiker meteen een foutmelding te tonen.
const List<Duration> _transientRetryDelays = [
  Duration(seconds: 5),
  Duration(seconds: 15),
];

bool _isTransientYtDlpError(String output) {
  final s = output.toLowerCase();
  return s.contains('the page needs to be reloaded') ||
      s.contains('http error 429') ||
      s.contains('http error 403') ||
      s.contains('unable to download webpage') ||
      s.contains('connection reset') ||
      s.contains('temporary failure in name resolution');
}

Future<List<String>> _cookiesArgs() async {
  final browser = await Settings.getCookiesBrowser();
  final value = browser.ytDlpValue;
  return value == null ? [] : ['--cookies-from-browser', value];
}

class YtDlpException implements Exception {
  final String message;
  YtDlpException(this.message);
  @override
  String toString() => message;
}

class PlaylistProbeResult {
  final bool isPlaylist;
  final int entryCount;
  final Map<String, dynamic> data;
  PlaylistProbeResult({
    required this.isPlaylist,
    required this.entryCount,
    required this.data,
  });
}

class YtDlpService {
  bool _androidReady = false;

  // Enkel nog relevant voor Android: op desktop wordt yt-dlp bij het
  // eerste gebruik automatisch gedownload (zie ensureYtDlp hieronder), dus
  // daar is niets meer dat blijvend "niet beschikbaar" kan zijn.
  String get unavailableMessage =>
      'yt-dlp kon niet worden geïnitialiseerd op dit toestel.';

  Future<bool> exeExists() async {
    if (Platform.isAndroid) {
      if (_androidReady) return true;
      try {
        await ensureYtDlp();
        return true;
      } catch (_) {
        return false;
      }
    }
    return true;
  }

  String? _resolvedYtDlpPath;
  String? _bundledFfmpegDir;
  String? _jsRuntimeArg;
  bool _jsRuntimeChecked = false;

  /// Map met meegeleverde tools naast de exe (`{installDir}/tools`).
  String get _installToolsDir =>
      p.join(File(Platform.resolvedExecutable).parent.path, 'tools');

  Future<String?> _firstExistingFile(List<String> candidates) async {
    for (final path in candidates) {
      if (await File(path).exists()) return path;
    }
    return null;
  }

  // Volgorde: tools naast de geïnstalleerde exe → APPDATA → legacy pad →
  // eenmalig downloaden naar APPDATA (alleen als niets gebundeld is, bv. dev).
  Future<String> ensureYtDlp({void Function(String)? onLog}) async {
    if (Platform.isAndroid) {
      // Android draait via youtubedl-android (MethodChannel), geen .exe.
      if (!_androidReady) {
        await _androidChannel.invokeMethod('init');
        _androidReady = true;
      }
      return 'android';
    }
    if (_resolvedYtDlpPath != null) return _resolvedYtDlpPath!;

    final supportDir = await getApplicationSupportDirectory();
    final appDataYtDlp = p.join(supportDir.path, 'yt-dlp', 'yt-dlp.exe');
    final found = await _firstExistingFile([
      p.join(_installToolsDir, 'yt-dlp.exe'),
      appDataYtDlp,
      _legacyYtDlpPath,
    ]);
    if (found != null) {
      _resolvedYtDlpPath = found;
      return found;
    }

    onLog?.call('yt-dlp niet gevonden, laatste versie downloaden...');
    final targetFile = File(appDataYtDlp);
    await targetFile.parent.create(recursive: true);

    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(_ytDlpDownloadUrl));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw YtDlpException(
          'yt-dlp-download mislukt (HTTP ${response.statusCode}).',
        );
      }
      final total = response.contentLength;
      final bytes = <int>[];
      var received = 0;
      var lastPct = -1;
      await for (final chunk in response) {
        bytes.addAll(chunk);
        received += chunk.length;
        if (total > 0) {
          final pct = (received / total * 100).floor();
          if (pct != lastPct && pct % 10 == 0) {
            lastPct = pct;
            onLog?.call('yt-dlp downloaden... $pct%');
          }
        }
      }
      await targetFile.writeAsBytes(bytes);
      onLog?.call('yt-dlp geïnstalleerd.');
    } catch (e) {
      if (await targetFile.exists()) {
        try {
          await targetFile.delete();
        } catch (_) {}
      }
      if (e is YtDlpException) rethrow;
      throw YtDlpException('Kon yt-dlp niet downloaden: $e');
    } finally {
      client.close(force: true);
    }

    _resolvedYtDlpPath = targetFile.path;
    return _resolvedYtDlpPath!;
  }

  Future<String?> _resolveBundledFfmpegDir() async {
    if (_bundledFfmpegDir != null) return _bundledFfmpegDir;

    final candidates = <String>[
      _installToolsDir,
    ];
    final supportDir = await getApplicationSupportDirectory();
    candidates.add(p.join(supportDir.path, 'ffmpeg'));

    for (final dir in candidates) {
      if (await File(p.join(dir, 'ffmpeg.exe')).exists() &&
          await File(p.join(dir, 'ffprobe.exe')).exists()) {
        _bundledFfmpegDir = dir;
        return dir;
      }
    }
    return null;
  }

  // ffmpeg is nodig voor mp3-extractie en voor het samenvoegen van losse
  // video/audio-streams. Android heeft dit al gebundeld via youtubedl-android.
  // Op Windows/desktop: gebruik systeem-ffmpeg als aanwezig, anders eenmalig
  // een portable build downloaden naar de app-datamap. Retourneert de map
  // om als --ffmpeg-location mee te geven, of null (systeem-PATH is prima).
  Future<String?> ensureFfmpeg({void Function(String)? onLog}) async {
    if (Platform.isAndroid) return null;

    final bundled = await _resolveBundledFfmpegDir();
    if (bundled != null) return bundled;

    try {
      final result = await Process.run('ffmpeg', ['-version']);
      if (result.exitCode == 0) return null;
    } catch (_) {
      // niet op PATH, hieronder bundelen.
    }

    onLog?.call('ffmpeg niet gevonden, portable versie downloaden...');
    final supportDir = await getApplicationSupportDirectory();
    final targetDir = Directory(p.join(supportDir.path, 'ffmpeg'));
    await targetDir.create(recursive: true);

    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(_ffmpegDownloadUrl));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw YtDlpException(
          'ffmpeg-download mislukt (HTTP ${response.statusCode}).',
        );
      }
      final total = response.contentLength;
      final bytes = <int>[];
      var received = 0;
      var lastPct = -1;
      await for (final chunk in response) {
        bytes.addAll(chunk);
        received += chunk.length;
        if (total > 0) {
          final pct = (received / total * 100).floor();
          if (pct != lastPct && pct % 10 == 0) {
            lastPct = pct;
            onLog?.call('ffmpeg downloaden... $pct%');
          }
        }
      }

      onLog?.call('ffmpeg uitpakken...');
      final archive = ZipDecoder().decodeBytes(bytes);
      var foundFfmpeg = false;
      var foundFfprobe = false;
      for (final file in archive.files) {
        if (!file.isFile) continue;
        final name = file.name.replaceAll('\\', '/');
        if (name.endsWith('/bin/ffmpeg.exe')) {
          await File(
            p.join(targetDir.path, 'ffmpeg.exe'),
          ).writeAsBytes(file.content as List<int>);
          foundFfmpeg = true;
        } else if (name.endsWith('/bin/ffprobe.exe')) {
          await File(
            p.join(targetDir.path, 'ffprobe.exe'),
          ).writeAsBytes(file.content as List<int>);
          foundFfprobe = true;
        }
      }
      if (!foundFfmpeg || !foundFfprobe) {
        throw YtDlpException(
          'ffmpeg.exe/ffprobe.exe niet gevonden in download.',
        );
      }
      onLog?.call('ffmpeg geïnstalleerd.');
      _bundledFfmpegDir = targetDir.path;
      return targetDir.path;
    } finally {
      client.close(force: true);
    }
  }

  // yt-dlp lost YouTube's "n"-throttling (nsig) sinds kort niet meer intern
  // op: er moet een externe JS-runtime aanwezig zijn, anders worden hoge
  // resoluties stilzwijgend overgeslagen en blijft alleen 144p/240p over.
  // Deno is de door yt-dlp aanbevolen runtime; als die niet op het systeem
  // staat downloaden we eenmalig een portable build naar de app-datamap
  // (zelfde patroon als ensureFfmpeg hierboven).
  Future<List<String>> _ensureJsRuntimeArgs({void Function(String)? onLog}) async {
    if (Platform.isAndroid) return [];
    if (_jsRuntimeChecked) {
      return _jsRuntimeArg == null ? [] : ['--js-runtimes', _jsRuntimeArg!];
    }
    _jsRuntimeChecked = true;

    final supportDir = await getApplicationSupportDirectory();
    final candidates = <String>[
      p.join(_installToolsDir, 'deno.exe'),
      p.join(supportDir.path, 'deno', 'deno.exe'),
    ];
    for (final path in candidates) {
      if (await File(path).exists()) {
        _jsRuntimeArg = 'deno:$path';
        return ['--js-runtimes', _jsRuntimeArg!];
      }
    }

    try {
      final result = await Process.run('deno', ['--version']);
      if (result.exitCode == 0) {
        _jsRuntimeArg = 'deno';
        return ['--js-runtimes', _jsRuntimeArg!];
      }
    } catch (_) {
      // niet op PATH, hieronder downloaden.
    }

    final bundled = File(p.join(supportDir.path, 'deno', 'deno.exe'));
    try {
      onLog?.call('JavaScript-runtime (deno) niet gevonden, portable versie downloaden...');
      await bundled.parent.create(recursive: true);
      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse(_denoDownloadUrl));
        final response = await request.close();
        if (response.statusCode != 200) {
          throw YtDlpException(
            'deno-download mislukt (HTTP ${response.statusCode}).',
          );
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk);
        }
        final archive = ZipDecoder().decodeBytes(bytes);
        var found = false;
        for (final file in archive.files) {
          if (!file.isFile) continue;
          if (file.name.toLowerCase().replaceAll('\\', '/') == 'deno.exe') {
            await bundled.writeAsBytes(file.content as List<int>);
            found = true;
            break;
          }
        }
        if (!found) {
          throw YtDlpException('deno.exe niet gevonden in download.');
        }
      } finally {
        client.close(force: true);
      }
      onLog?.call('JavaScript-runtime geïnstalleerd.');
      _jsRuntimeArg = 'deno:${bundled.path}';
      return ['--js-runtimes', _jsRuntimeArg!];
    } catch (e) {
      onLog?.call(
        'Waarschuwing: kon geen JS-runtime installeren ($e), hoge resoluties kunnen ontbreken.',
      );
      _jsRuntimeArg = null;
      return [];
    }
  }

  Future<PlaylistProbeResult> probePlaylist(String url) async {
    final jsArgs = await _ensureJsRuntimeArgs();
    final cookiesArgs = await _cookiesArgs();
    final Map<String, dynamic> data = Platform.isAndroid
        ? jsonDecode(await _androidQuery(url, 'probe'))
        : await _desktopQuery(url, [
            '--flat-playlist',
            '-J',
            ..._playerClientArgs,
            ...jsArgs,
            ...cookiesArgs,
            url,
          ]);
    final entries = data['entries'];
    final isPlaylist = data['_type'] == 'playlist' || entries is List;
    final count = entries is List ? entries.length : 1;
    return PlaylistProbeResult(
      isPlaylist: isPlaylist,
      entryCount: count,
      data: data,
    );
  }

  Future<List<FormatInfo>> fetchFormats(String url) async {
    final jsArgs = await _ensureJsRuntimeArgs();
    final cookiesArgs = await _cookiesArgs();
    final Map<String, dynamic> data = Platform.isAndroid
        ? jsonDecode(await _androidQuery(url, 'formats'))
        : await _desktopQuery(url, [
            '--no-playlist',
            '-J',
            ..._playerClientArgs,
            ...jsArgs,
            ...cookiesArgs,
            url,
          ]);
    return parseFormats(data);
  }

  // Bij een gewone (niet-playlist) URL geeft de --flat-playlist probe-call al
  // dezelfde volledige extractie terug als een losse formats-call zou doen.
  // Die data hergebruiken we hier, zodat we geen tweede yt-dlp-aanroep (en
  // dus geen tweede netwerk-rondtrip) nodig hebben.
  List<FormatInfo> parseFormats(Map<String, dynamic> data) {
    final List formats = data['formats'] ?? [];
    var infos = formats
        .whereType<Map>()
        .map((f) => FormatInfo.fromJson(f.cast<String, dynamic>()))
        .where((f) => f.hasVideo)
        .toList();

    if (infos.isEmpty) {
      // Sommige (vooral niet-YouTube) extractors leveren geen "formats"
      // array, maar wel bruikbare info op het hoofdniveau van de JSON.
      final rootInfo = FormatInfo.fromJson(data);
      if (rootInfo.hasVideo && (data['url'] != null || data['ext'] != null)) {
        infos = [rootInfo];
      }
    }

    infos.sort((a, b) => (b.height ?? 0).compareTo(a.height ?? 0));
    return infos;
  }

  Future<String> _androidQuery(String url, String method) async {
    try {
      final result = await _androidChannel.invokeMethod<String>(method, {
        'url': url,
      });
      return result ?? '{}';
    } on PlatformException catch (e) {
      throw YtDlpException(_shortError(e.message ?? 'Onbekende fout'));
    }
  }

  Future<Map<String, dynamic>> _desktopQuery(
    String url,
    List<String> args,
  ) async {
    final ytDlp = await ensureYtDlp();
    for (var attempt = 0; ; attempt++) {
      final result = await Process.run(
        ytDlp,
        args,
        environment: _ytDlpEnvironment,
        // yt-dlp draait als Python-exe; op Windows kan de systeem-codepage
        // niet-UTF8 bytes in titels/output geven. allowMalformed voorkomt een
        // FormatException-crash als PYTHONUTF8 (hieronder) het toch mist.
        stdoutEncoding: const Utf8Codec(allowMalformed: true),
        stderrEncoding: const Utf8Codec(allowMalformed: true),
      );
      if (result.exitCode == 0) {
        return jsonDecode(result.stdout.toString());
      }
      final stderr = result.stderr.toString();
      if (attempt >= _transientRetryDelays.length ||
          !_isTransientYtDlpError(stderr)) {
        throw YtDlpException(_shortError(stderr));
      }
      await Future.delayed(_transientRetryDelays[attempt]);
    }
  }

  Stream<DownloadEvent> download({
    required String url,
    required String outputDir,
    required bool isPlaylist,
    required OutputFormat format,
    String? formatId,
    String? ffmpegDir,
  }) {
    return Platform.isAndroid
        ? _downloadAndroid(
            url: url,
            outputDir: outputDir,
            isPlaylist: isPlaylist,
            format: format,
            formatId: formatId,
          )
        : _downloadDesktop(
            url: url,
            outputDir: outputDir,
            isPlaylist: isPlaylist,
            format: format,
            formatId: formatId,
            ffmpegDir: ffmpegDir,
          );
  }

  Stream<DownloadEvent> _downloadAndroid({
    required String url,
    required String outputDir,
    required bool isPlaylist,
    required OutputFormat format,
    String? formatId,
  }) {
    final controller = StreamController<DownloadEvent>();
    final progressSub = _androidProgressChannel.receiveBroadcastStream().listen(
      (event) {
        final map = Map<String, dynamic>.from(event as Map);
        final line = map['line'] as String? ?? '';
        if (line.contains(_filepathMarker)) {
          final path = _extractFilepath(line);
          if (path != null) controller.add(FileDownloadedEvent(path));
          return;
        }
        if (line.isNotEmpty) controller.add(LogEvent(line));
        final progress = map['progress'];
        if (progress is num && progress >= 0) {
          controller.add(ProgressEvent(progress.toDouble()));
        }
        if (line.startsWith('[download] Destination:') ||
            line.startsWith('[ExtractAudio]') ||
            line.startsWith('[Merger]')) {
          controller.add(StatusEvent(line));
        }
      },
    );

    () async {
      try {
        await _androidChannel.invokeMethod('download', {
          'url': url,
          'outputDir': outputDir,
          'isPlaylist': isPlaylist,
          'format': format == OutputFormat.mp3 ? 'mp3' : 'mp4',
          'formatId': formatId,
        });
        controller.add(DownloadDoneEvent(success: true));
      } on PlatformException catch (e) {
        controller.add(LogEvent('FOUT: ${e.message ?? e.toString()}'));
        controller.add(
          DownloadDoneEvent(
            success: false,
            error: _shortError(e.message ?? 'Onbekende fout'),
          ),
        );
      } finally {
        await progressSub.cancel();
        await controller.close();
      }
    }();

    return controller.stream;
  }

  Stream<DownloadEvent> _downloadDesktop({
    required String url,
    required String outputDir,
    required bool isPlaylist,
    required OutputFormat format,
    String? formatId,
    String? ffmpegDir,
  }) async* {
    final ytDlp = await ensureYtDlp();
    final jsArgs = await _ensureJsRuntimeArgs();
    final cookiesArgs = await _cookiesArgs();
    // Relatief -o + -P home/temp: absolute -o negeert --paths volledig,
    // waardoor .part weer op Desktop/OneDrive belandt (WinError 32).
    final tempRoot = Directory(
      p.join((await getTemporaryDirectory()).path, 'ytdlp-temp'),
    );
    await tempRoot.create(recursive: true);
    final args = <String>[
      url,
      '-P',
      'home:$outputDir',
      '-P',
      'temp:${tempRoot.path}',
      '-o',
      '%(title)s.%(ext)s',
      '--windows-filenames',
      '--file-access-retries',
      '15',
      '--newline',
      '--no-mtime',
      '--print',
      'after_move:$_filepathMarker%(filepath)s',
      isPlaylist ? '--yes-playlist' : '--no-playlist',
      // Een oude .part-restant hervatten faalt vaak met HTTP 416: YouTube's
      // ondertekende CDN-URL's zijn maar kort geldig/uniek per aanvraag, dus
      // "verder gaan" op een eerder-mislukte download botst met een nieuwe
      // URL. Altijd opnieuw beginnen is betrouwbaarder dan proberen te hervatten.
      '--no-continue',
      ..._playerClientArgs,
      ...jsArgs,
      ...cookiesArgs,
      ..._concurrencyArgs,
      if (ffmpegDir != null) ...['--ffmpeg-location', ffmpegDir],
    ];

    if (format == OutputFormat.mp3) {
      args.addAll(['-x', '--audio-format', 'mp3', '--audio-quality', '0']);
    } else {
      final id = formatId ?? 'bestvideo+bestaudio/best';
      args.addAll(['-f', id, '--merge-output-format', 'mp4']);
    }

    const lenientUtf8 = Utf8Decoder(allowMalformed: true);

    // Bij een tijdelijke YouTube-blokkade (bot-check/rate-limit, lost
    // meestal vanzelf op) het hele proces na een korte pauze opnieuw
    // starten i.p.v. de gebruiker meteen een foutmelding te tonen. Een
    // reeds voltooide entry in een playlist wordt dan wel opnieuw
    // gedownload (geen --download-archive), maar dat is dezelfde
    // "altijd opnieuw beginnen"-aanpak als --no-continue hierboven.
    for (var attempt = 0; ; attempt++) {
      final process = await Process.start(
        ytDlp,
        args,
        environment: _ytDlpEnvironment,
      );

      final stdoutLines = process.stdout
          .transform(lenientUtf8)
          .transform(const LineSplitter());
      final stderrBuffer = StringBuffer();
      final stderrSub = process.stderr
          .transform(lenientUtf8)
          .transform(const LineSplitter())
          .listen((line) => stderrBuffer.writeln(line));

      await for (final line in stdoutLines) {
        if (line.isNotEmpty) yield LogEvent(line);
        if (line.contains(_filepathMarker)) {
          final path = _extractFilepath(line);
          if (path != null) yield FileDownloadedEvent(path);
          continue;
        }
        final match = _percentRegex.firstMatch(line);
        if (match != null) {
          final pct = double.tryParse(match.group(1)!);
          if (pct != null) yield ProgressEvent(pct);
          continue;
        }
        if (line.startsWith('[download] Destination:') ||
            line.startsWith('[ExtractAudio]') ||
            line.startsWith('[Merger]')) {
          yield StatusEvent(line);
        }
      }

      final exitCode = await process.exitCode;
      await stderrSub.cancel();

      if (exitCode == 0) {
        yield DownloadDoneEvent(success: true);
        return;
      }

      final stderrText = stderrBuffer.toString();
      if (attempt < _transientRetryDelays.length &&
          _isTransientYtDlpError(stderrText)) {
        final delay = _transientRetryDelays[attempt];
        yield LogEvent(
          'Tijdelijke YouTube-blokkade, opnieuw proberen over ${delay.inSeconds}s...',
        );
        await Future.delayed(delay);
        continue;
      }

      for (final line in stderrText.split('\n')) {
        if (line.trim().isNotEmpty) yield LogEvent('FOUT: $line');
      }
      yield DownloadDoneEvent(
        success: false,
        error: _shortError(stderrText),
      );
      return;
    }
  }

  Future<void> openFile(String path) async {
    if (Platform.isAndroid) {
      await _androidChannel.invokeMethod('openFile', {'path': path});
      return;
    }
    // explorer.exe (zelfde als de Chrome-extensie) i.p.v. url_launcher:
    // Uri.file + ShellExecute faalt sneller op rare/lange paden.
    if (!await File(path).exists()) {
      throw YtDlpException('Bestand bestaat niet: $path');
    }
    await Process.start('explorer.exe', [
      path,
    ], mode: ProcessStartMode.detached);
  }

  Future<void> openFolder(String path) async {
    if (Platform.isAndroid) {
      await _androidChannel.invokeMethod('openFolder', {'path': path});
      return;
    }
    await Process.start('explorer.exe', [
      p.dirname(path),
    ], mode: ProcessStartMode.detached);
  }

  String _shortError(String stderr) {
    final lines = stderr.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return 'Onbekende fout';
    return lines.last.replaceFirst(RegExp(r'^ERROR:\s*'), '');
  }
}
