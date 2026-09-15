import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'models.dart';

const String ytDlpPath = r'C:\Program Files\yt-dlpd.exe';

final RegExp _percentRegex = RegExp(r'\[download\]\s+([\d.]+)%');
const String _filepathMarker = 'FILEPATH::';

class YtDlpException implements Exception {
  final String message;
  YtDlpException(this.message);
  @override
  String toString() => message;
}

class PlaylistProbeResult {
  final bool isPlaylist;
  final int entryCount;
  PlaylistProbeResult({required this.isPlaylist, required this.entryCount});
}

class YtDlpService {
  Future<bool> exeExists() => File(ytDlpPath).exists();

  Future<PlaylistProbeResult> probePlaylist(String url) async {
    final result = await Process.run(
      ytDlpPath,
      ['--flat-playlist', '-J', url],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.exitCode != 0) {
      throw YtDlpException(_shortError(result.stderr.toString()));
    }
    final Map<String, dynamic> data = jsonDecode(result.stdout.toString());
    final entries = data['entries'];
    final isPlaylist = data['_type'] == 'playlist' || entries is List;
    final count = entries is List ? entries.length : 1;
    return PlaylistProbeResult(isPlaylist: isPlaylist, entryCount: count);
  }

  Future<List<FormatInfo>> fetchFormats(String url) async {
    final result = await Process.run(
      ytDlpPath,
      ['--no-playlist', '-J', url],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.exitCode != 0) {
      throw YtDlpException(_shortError(result.stderr.toString()));
    }
    final Map<String, dynamic> data = jsonDecode(result.stdout.toString());
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

  Stream<DownloadEvent> download({
    required String url,
    required String outputDir,
    required bool isPlaylist,
    required OutputFormat format,
    String? formatId,
  }) async* {
    final outTemplate = p.join(outputDir, '%(title)s.%(ext)s');
    final args = <String>[
      url,
      '-o', outTemplate,
      '--newline',
      '--no-mtime',
      '--print', 'after_move:$_filepathMarker%(filepath)s',
      isPlaylist ? '--yes-playlist' : '--no-playlist',
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
      if (line.contains(_filepathMarker)) {
        final path = line.substring(line.indexOf(_filepathMarker) + _filepathMarker.length).trim();
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
      yield DownloadDoneEvent(success: false, error: _shortError(stderrBuffer.toString()));
    } else {
      yield DownloadDoneEvent(success: true);
    }
  }

  String _shortError(String stderr) {
    final lines = stderr.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return 'Onbekende fout';
    return lines.last.replaceFirst(RegExp(r'^ERROR:\s*'), '');
  }
}
