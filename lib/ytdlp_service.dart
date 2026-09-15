import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'models.dart';

const String ytDlpPath = r'C:\Program Files\yt-dlpd.exe';

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

// android-client levert sinds YouTube's PO/SABR-wijzigingen alleen nog
// progressive 360p (format 18). default+tv_simply geeft weer alle
// resoluties (tot 4K) zonder PO-token.
const List<String> _playerClientArgs = [
  '--extractor-args',
  'youtube:player_client=default,tv_simply',
];
const List<String> _concurrencyArgs = ['--concurrent-fragments', '4'];

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

  String get unavailableMessage => Platform.isAndroid
      ? 'yt-dlp kon niet worden geïnitialiseerd op dit toestel.'
      : 'yt-dlp.exe niet gevonden op $ytDlpPath';

  Future<bool> exeExists() async {
    if (Platform.isAndroid) {
      if (_androidReady) return true;
      try {
        await _androidChannel.invokeMethod('init');
        _androidReady = true;
        return true;
      } catch (_) {
        return false;
      }
    }
    return File(ytDlpPath).exists();
  }

  String? _bundledFfmpegDir;
  String? _jsRuntimeArg;
  bool _jsRuntimeChecked = false;

  Future<String?> _resolveBundledFfmpegDir() async {
    if (_bundledFfmpegDir != null) return _bundledFfmpegDir;
    final supportDir = await getApplicationSupportDirectory();
    final dir = p.join(supportDir.path, 'ffmpeg');
    if (await File(p.join(dir, 'ffmpeg.exe')).exists()) {
      _bundledFfmpegDir = dir;
      return dir;
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
    if (_jsRuntimeChecked) {
      return _jsRuntimeArg == null ? [] : ['--js-runtimes', _jsRuntimeArg!];
    }
    _jsRuntimeChecked = true;

    final supportDir = await getApplicationSupportDirectory();
    final bundled = File(p.join(supportDir.path, 'deno', 'deno.exe'));
    if (await bundled.exists()) {
      _jsRuntimeArg = 'deno:${bundled.path}';
      return ['--js-runtimes', _jsRuntimeArg!];
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
    final Map<String, dynamic> data = Platform.isAndroid
        ? jsonDecode(await _androidQuery(url, 'probe'))
        : await _desktopQuery(url, [
            '--flat-playlist',
            '-J',
            ..._playerClientArgs,
            ...jsArgs,
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
    final Map<String, dynamic> data = Platform.isAndroid
        ? jsonDecode(await _androidQuery(url, 'formats'))
        : await _desktopQuery(url, [
            '--no-playlist',
            '-J',
            ..._playerClientArgs,
            ...jsArgs,
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
    final result = await Process.run(
      ytDlpPath,
      args,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.exitCode != 0) {
      throw YtDlpException(_shortError(result.stderr.toString()));
    }
    return jsonDecode(result.stdout.toString());
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
          final path = line
              .substring(line.indexOf(_filepathMarker) + _filepathMarker.length)
              .trim();
          if (path.isNotEmpty) controller.add(FileDownloadedEvent(path));
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
    final jsArgs = await _ensureJsRuntimeArgs();
    final outTemplate = p.join(outputDir, '%(title)s.%(ext)s');
    final args = <String>[
      url,
      '-o',
      outTemplate,
      '--newline',
      '--no-mtime',
      '--print',
      'after_move:$_filepathMarker%(filepath)s',
      isPlaylist ? '--yes-playlist' : '--no-playlist',
      ..._playerClientArgs,
      ...jsArgs,
      ..._concurrencyArgs,
      if (ffmpegDir != null) ...['--ffmpeg-location', ffmpegDir],
    ];

    if (format == OutputFormat.mp3) {
      args.addAll(['-x', '--audio-format', 'mp3', '--audio-quality', '0']);
    } else {
      final id = formatId ?? 'bestvideo+bestaudio/best';
      args.addAll(['-f', id, '--merge-output-format', 'mp4']);
    }

    final process = await Process.start(ytDlpPath, args);

    final stdoutLines = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    final stderrBuffer = StringBuffer();
    final stderrSub = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => stderrBuffer.writeln(line));

    await for (final line in stdoutLines) {
      if (line.isNotEmpty) yield LogEvent(line);
      if (line.contains(_filepathMarker)) {
        final path = line
            .substring(line.indexOf(_filepathMarker) + _filepathMarker.length)
            .trim();
        if (path.isNotEmpty) {
          yield FileDownloadedEvent(path);
        }
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

    if (exitCode != 0) {
      for (final line in stderrBuffer.toString().split('\n')) {
        if (line.trim().isNotEmpty) yield LogEvent('FOUT: $line');
      }
      yield DownloadDoneEvent(
        success: false,
        error: _shortError(stderrBuffer.toString()),
      );
    } else {
      yield DownloadDoneEvent(success: true);
    }
  }

  Future<void> openFile(String path) async {
    if (Platform.isAndroid) {
      await _androidChannel.invokeMethod('openFile', {'path': path});
      return;
    }
    final ok = await launchUrl(Uri.file(path));
    if (!ok)
      throw YtDlpException(
        'Geen standaardprogramma gevonden om dit bestand te openen.',
      );
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
