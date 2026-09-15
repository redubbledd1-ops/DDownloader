import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Chrome/Edge Native Messaging host for Downloader.
///
/// Settings komen uit / gaan naar dezelfde shared_preferences.json als de
/// Flutter Windows-app (%APPDATA%\com.example\Downloader\).
///
/// Commands:
///   ping | getSettings | setSettings | formats | download | sendToApp

const String ytDlpPath = r'C:\Program Files\yt-dlpd.exe';
const List<String> playerClientArgs = [
  '--extractor-args',
  'youtube:player_client=default,tv_simply',
];
const List<String> concurrencyArgs = ['--concurrent-fragments', '4'];
const String filepathMarker = 'FILEPATH::';
final RegExp percentRegex = RegExp(r'\[download\]\s+([\d.]+)%');

const String prefsKeyDownloadDir = 'flutter.download_dir';
const String prefsKeyDarkMode = 'flutter.dark_mode';
const String prefsKeyPlaylistMode = 'flutter.playlist_mode';
const String prefsKeyDefaultFormat = 'flutter.default_format';
const String prefsKeyAppExe = 'flutter.app_exe';
const String prefsKeyAutoDownload = 'flutter.auto_download_on_click';
const String prefsKeyPreferredVideoQuality = 'flutter.preferred_video_quality';

// Zelfde resoluties als PreferredVideoQuality in lib/models.dart, zodat een
// direct-download vanuit de extentie dezelfde kwaliteitsvoorkeur respecteert
// als de app wanneer er geen expliciete formatId is gekozen.
const Map<String, int> qualityMaxHeight = {
  'p2160': 2160,
  'p1440': 1440,
  'p1080': 1080,
  'p720': 720,
  'p480': 480,
  'p360': 360,
  'p240': 240,
  'p144': 144,
};

String? formatSelectorFor(String? quality) {
  if (quality == null) return null;
  final h = qualityMaxHeight[quality];
  if (h == null) return null; // 'ask' of onbekend → geen cap
  return 'bestvideo[height<=$h]+bestaudio/best[height<=$h]/best';
}

Future<void> main() async {
  try {
    stdin
      ..echoMode = false
      ..lineMode = false;
  } catch (_) {}

  while (true) {
    final msg = await readMessage();
    if (msg == null) break;
    try {
      await handleMessage(msg);
    } catch (e) {
      await writeMessage({'ok': false, 'error': e.toString()});
    }
  }
}

Future<Map<String, dynamic>?> readMessage() async {
  final lenBuf = await readExact(4);
  if (lenBuf == null) return null;
  final length = ByteData.sublistView(
    Uint8List.fromList(lenBuf),
  ).getUint32(0, Endian.little);
  if (length == 0 || length > 1024 * 1024) {
    throw StateError('Ongeldige Native Messaging lengte: $length');
  }
  final body = await readExact(length);
  if (body == null) return null;
  final decoded = jsonDecode(utf8.decode(body));
  if (decoded is! Map) {
    throw StateError('Bericht moet een JSON-object zijn');
  }
  return decoded.cast<String, dynamic>();
}

Future<List<int>?> readExact(int n) async {
  final out = Uint8List(n);
  var offset = 0;
  while (offset < n) {
    final b = stdin.readByteSync();
    if (b < 0) {
      if (offset == 0) return null;
      throw StateError('Onverwacht einde van stdin');
    }
    out[offset++] = b;
  }
  return out;
}

Future<void> writeMessage(Map<String, dynamic> msg) async {
  final bytes = utf8.encode(jsonEncode(msg));
  final header = ByteData(4)..setUint32(0, bytes.length, Endian.little);
  stdout.add(header.buffer.asUint8List());
  stdout.add(bytes);
  await stdout.flush();
}

Future<void> handleMessage(Map<String, dynamic> msg) async {
  final cmd = msg['cmd']?.toString() ?? '';
  switch (cmd) {
    case 'ping':
      final settings = await readSettings();
      await writeMessage({
        'ok': true,
        'version': '1.1.0',
        'ytDlp': await resolveYtDlp(),
        'prefsPath': prefsFile().path,
        'appExe': settings['appExe'],
      });
    case 'getSettings':
      await writeMessage({'ok': true, 'settings': await readSettings()});
    case 'setSettings':
      final patch = msg['settings'];
      if (patch is! Map) {
        await writeMessage({'ok': false, 'error': 'settings ontbreekt'});
        return;
      }
      final updated = await writeSettings(patch.cast<String, dynamic>());
      // Push naar draaiende app zodat SharedPreferences synchroon blijft.
      appendToInbox({
        'type': 'settings',
        'settings': updated,
        'ts': DateTime.now().millisecondsSinceEpoch,
      });
      await writeMessage({'ok': true, 'settings': updated});
    case 'formats':
      final url = msg['url']?.toString() ?? '';
      if (url.isEmpty) {
        await writeMessage({'ok': false, 'error': 'URL ontbreekt'});
        return;
      }
      final formats = await fetchFormats(url);
      await writeMessage({'ok': true, 'formats': formats});
    case 'download':
      final url = msg['url']?.toString() ?? '';
      if (url.isEmpty) {
        await writeMessage({'ok': false, 'error': 'URL ontbreekt'});
        return;
      }
      final settings = await readSettings();
      final downloadFormat = msg['format']?.toString() ?? settings['format'] as String;
      var downloadFormatId = msg['formatId']?.toString();
      if ((downloadFormatId == null || downloadFormatId.isEmpty) &&
          downloadFormat != 'mp3') {
        // Geen expliciete kwaliteit gekozen (bv. icoon-klik auto-download):
        // val terug op de app-voorkeur i.p.v. altijd de beste/willekeurige.
        downloadFormatId = formatSelectorFor(
          settings['preferredVideoQuality'] as String?,
        );
      }
      await runDownload(
        url: url,
        format: downloadFormat,
        formatId: downloadFormatId,
        isPlaylist: msg['isPlaylist'] == true
            ? true
            : settings['playlistMode'] == 'playlist',
        outputDir: msg['outputDir']?.toString() ?? settings['downloadDir'] as String,
      );
    case 'sendToApp':
      final url = msg['url']?.toString() ?? '';
      if (url.isEmpty) {
        await writeMessage({'ok': false, 'error': 'URL ontbreekt'});
        return;
      }
      final settings = await readSettings();
      final format =
          msg['format']?.toString() ?? settings['format'] as String? ?? 'mp4';
      final formatId = msg['formatId']?.toString();
      final settingsPatch = <String, dynamic>{
        'downloadDir': msg['downloadDir'] ?? settings['downloadDir'],
        'format': format,
        'playlistMode': msg['playlistMode'] ?? settings['playlistMode'],
      };
      // Schrijf ook naar prefs voor als de app nog niet draait.
      await writeSettings(settingsPatch);
      final launched = await sendToApp(
        url: url,
        format: format,
        formatId: formatId,
        appExe: settings['appExe'] as String?,
        settings: settingsPatch,
      );
      await writeMessage({
        'ok': true,
        'done': true,
        'queued': true,
        'launched': launched,
      });
    case 'openFolder':
      final path = msg['path']?.toString() ?? '';
      if (path.isEmpty) {
        await writeMessage({'ok': false, 'error': 'pad ontbreekt'});
        return;
      }
      try {
        final dir = File(path).parent.path;
        await Process.start(
          'explorer.exe',
          [dir],
          mode: ProcessStartMode.detached,
        );
        await writeMessage({'ok': true});
      } catch (e) {
        await writeMessage({'ok': false, 'error': e.toString()});
      }
    case 'openFile':
      final filePath = msg['path']?.toString() ?? '';
      if (filePath.isEmpty) {
        await writeMessage({'ok': false, 'error': 'pad ontbreekt'});
        return;
      }
      try {
        // explorer.exe met een bestandspad start het bestand met de
        // standaard-app, net als dubbelklikken.
        await Process.start(
          'explorer.exe',
          [filePath],
          mode: ProcessStartMode.detached,
        );
        await writeMessage({'ok': true});
      } catch (e) {
        await writeMessage({'ok': false, 'error': e.toString()});
      }
    default:
      await writeMessage({'ok': false, 'error': 'Onbekend cmd: $cmd'});
  }
}

Directory appDataDir() {
  final roaming = Platform.environment['APPDATA'] ?? '';
  final dir = Directory('$roaming\\com.example\\Downloader');
  dir.createSync(recursive: true);
  return dir;
}

File prefsFile() => File('${appDataDir().path}\\shared_preferences.json');

File inboxFile() => File('${appDataDir().path}\\extension_inbox.json');

// De inbox is een JSON-array (wachtrij), niet één slot: anders kan een
// settings-melding en een download-opdracht die vlak na elkaar geschreven
// worden elkaar overschrijven voordat de app ze heeft gelezen (elke
// popup-actie start een nieuw host-proces, dus dit is een echte
// inter-process race, geen in-memory state).
void appendToInbox(Map<String, dynamic> job) {
  final file = inboxFile();
  final jobs = <dynamic>[];
  if (file.existsSync()) {
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is List) {
        jobs.addAll(decoded);
      } else if (decoded is Map) {
        jobs.add(decoded);
      }
    } catch (_) {}
  }
  jobs.add(job);
  file.writeAsStringSync(jsonEncode(jobs));
}

Map<String, dynamic> loadPrefsRaw() {
  final merged = <String, dynamic>{};
  // Oude builds schreven naar com.example\downoader; huidige ProductName is Downloader.
  final roaming = Platform.environment['APPDATA'] ?? '';
  for (final name in ['downoader', 'Downloader']) {
    final file = File('$roaming\\com.example\\$name\\shared_preferences.json');
    if (!file.existsSync()) continue;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is Map) {
        for (final e in decoded.entries) {
          final v = e.value;
          if (v == null || (v is String && v.isEmpty)) continue;
          merged[e.key.toString()] = v;
        }
      }
    } catch (_) {}
  }
  return merged;
}

void savePrefsRaw(Map<String, dynamic> data) {
  // Altijd naar de canonieke Downloader-map schrijven.
  final file = prefsFile();
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
}

// Direct-downloaden vanuit de extentie draait buiten de Windows-app om, dus
// de exe weet er niets van. Schrijf het bestand daarom zelf in dezelfde
// downloaded_items-lijst (zichtbaar zodra de app start) en zet een
// inbox-melding klaar zodat een al draaiende app 'm meteen live toont.
void recordDownloadedItem({
  required String path,
  required String format,
  required bool isPlaylist,
}) {
  final raw = loadPrefsRaw();
  final list = <dynamic>[];
  final existingRaw = raw['flutter.downloaded_items'];
  if (existingRaw is String && existingRaw.isNotEmpty) {
    try {
      final decoded = jsonDecode(existingRaw);
      if (decoded is List) list.addAll(decoded);
    } catch (_) {}
  }
  list.insert(0, {'path': path, 'isPlaylist': isPlaylist, 'format': format});
  raw['flutter.downloaded_items'] = jsonEncode(list);
  savePrefsRaw(raw);

  try {
    appendToInbox({
      'type': 'downloaded',
      'path': path,
      'format': format,
      'isPlaylist': isPlaylist,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
  } catch (_) {}
}

Future<Map<String, dynamic>> readSettings() async {
  final raw = loadPrefsRaw();
  final profile = Platform.environment['USERPROFILE'] ?? 'C:\\';
  final downloadDir = raw[prefsKeyDownloadDir]?.toString();
  return {
    'downloadDir': (downloadDir == null || downloadDir.isEmpty)
        ? '$profile\\Downloads'
        : downloadDir,
    'darkMode': raw[prefsKeyDarkMode] == true,
    'playlistMode': raw[prefsKeyPlaylistMode]?.toString() ?? 'ask',
    'format': raw[prefsKeyDefaultFormat]?.toString() ?? 'mp4',
    'appExe': raw[prefsKeyAppExe]?.toString() ?? '',
    'autoDownloadOnClick': raw[prefsKeyAutoDownload] == true,
    'preferredVideoQuality': raw[prefsKeyPreferredVideoQuality]?.toString() ?? 'p1080',
  };
}

Future<Map<String, dynamic>> writeSettings(Map<String, dynamic> patch) async {
  final raw = loadPrefsRaw();
  if (patch.containsKey('downloadDir')) {
    final v = patch['downloadDir']?.toString() ?? '';
    if (v.isNotEmpty) raw[prefsKeyDownloadDir] = v;
  }
  if (patch.containsKey('darkMode')) {
    raw[prefsKeyDarkMode] = patch['darkMode'] == true;
  }
  if (patch.containsKey('playlistMode')) {
    final v = patch['playlistMode']?.toString() ?? 'ask';
    if (['ask', 'playlist', 'single'].contains(v)) {
      raw[prefsKeyPlaylistMode] = v;
    }
  }
  if (patch.containsKey('format')) {
    final v = patch['format']?.toString() ?? 'mp4';
    if (v == 'mp4' || v == 'mp3') raw[prefsKeyDefaultFormat] = v;
  }
  if (patch.containsKey('appExe')) {
    final v = patch['appExe']?.toString() ?? '';
    if (v.isNotEmpty) raw[prefsKeyAppExe] = v;
  }
  if (patch.containsKey('autoDownloadOnClick')) {
    raw[prefsKeyAutoDownload] = patch['autoDownloadOnClick'] == true;
  }
  if (patch.containsKey('preferredVideoQuality')) {
    final v = patch['preferredVideoQuality']?.toString() ?? '';
    if (v == 'ask' || v == 'max' || qualityMaxHeight.containsKey(v)) {
      raw[prefsKeyPreferredVideoQuality] = v;
    }
  }
  savePrefsRaw(raw);
  return readSettings();
}

Future<bool> sendToApp({
  required String url,
  required String format,
  String? formatId,
  String? appExe,
  Map<String, dynamic>? settings,
}) async {
  final payload = <String, dynamic>{
    'url': url,
    'format': format,
    if (formatId != null && formatId.isNotEmpty) 'formatId': formatId,
    if (settings != null) 'settings': settings,
    'ts': DateTime.now().millisecondsSinceEpoch,
  };
  appendToInbox(payload);

  if (await isDownoaderRunning()) {
    return true;
  }

  final exe = (appExe != null && appExe.isNotEmpty)
      ? appExe
      : await guessAppExe();
  if (exe == null || !File(exe).existsSync()) {
    return false;
  }
  await Process.start(exe, [
    '--url=$url',
    if (format.isNotEmpty) '--format=$format',
    if (formatId != null && formatId.isNotEmpty) '--formatId=$formatId',
  ], mode: ProcessStartMode.detached);
  return true;
}

Future<bool> isDownoaderRunning() async {
  try {
    final result = await Process.run('tasklist', [
      '/FI',
      'IMAGENAME eq downoader.exe',
      '/NH',
    ]);
    return result.stdout.toString().toLowerCase().contains('downoader.exe');
  } catch (_) {
    return false;
  }
}

Future<String?> guessAppExe() async {
  final hostDir = File(Platform.resolvedExecutable).parent.path;
  final candidates = <String>[
    '$hostDir\\downoader.exe',
    '$hostDir\\..\\downoader.exe',
    '$hostDir\\..\\..\\Release\\downoader.exe',
    '$hostDir\\..\\..\\..\\build\\windows\\x64\\runner\\Release\\downoader.exe',
  ];
  for (final c in candidates) {
    final file = File(c);
    if (await file.exists()) return file.absolute.path;
  }
  return null;
}

Future<String> resolveYtDlp() async {
  if (await File(ytDlpPath).exists()) return ytDlpPath;
  final beside = File(
    '${File(Platform.resolvedExecutable).parent.path}\\yt-dlpd.exe',
  );
  if (await beside.exists()) return beside.path;
  return ytDlpPath;
}

Future<List<Map<String, dynamic>>> fetchFormats(String url) async {
  final exe = await resolveYtDlp();
  final jsArgs = await resolveJsRuntimeArgs();
  final result = await Process.run(exe, [
    '--no-playlist',
    '-J',
    ...playerClientArgs,
    ...jsArgs,
    url,
  ], stdoutEncoding: utf8, stderrEncoding: utf8);
  if (result.exitCode != 0) {
    throw StateError(shortError(result.stderr.toString()));
  }
  final data = jsonDecode(result.stdout.toString()) as Map<String, dynamic>;
  final formats = (data['formats'] as List?) ?? [];
  final infos = <Map<String, dynamic>>[];
  for (final raw in formats) {
    if (raw is! Map) continue;
    final f = raw.cast<String, dynamic>();
    final vcodec = f['vcodec']?.toString();
    final hasVideo =
        vcodec == null || (vcodec != 'none' && vcodec.isNotEmpty);
    if (!hasVideo) continue;
    final acodec = f['acodec']?.toString();
    final hasAudio =
        acodec == null || (acodec != 'none' && acodec.isNotEmpty);
    final height = f['height'];
    final note = f['format_note']?.toString() ?? '';
    final noteMatch = RegExp(r'(\d{3,4})p').firstMatch(note);
    final labelRes = noteMatch != null
        ? '${noteMatch.group(1)}p'
        : (height is num
            ? '${height.toInt()}p'
            : (note.isEmpty ? '${f['format_id']}' : note));
    final filesize = f['filesize'];
    final filesizeApprox = f['filesize_approx'];
    infos.add({
      'formatId': f['format_id']?.toString() ?? 'best',
      'ext': f['ext']?.toString() ?? '',
      'height': height is num ? height.toInt() : null,
      'note': note,
      'label': labelRes,
      'hasAudio': hasAudio,
      'filesize': filesize is num
          ? filesize.toInt()
          : (filesizeApprox is num ? filesizeApprox.toInt() : null),
    });
  }
  infos.sort(
    (a, b) =>
        ((b['height'] as int?) ?? 0).compareTo((a['height'] as int?) ?? 0),
  );
  return infos;
}

Future<String?> resolveFfmpegDir() async {
  final roaming = Platform.environment['APPDATA'] ?? '';
  final candidates = <String>[
    '$roaming\\com.example\\Downloader\\ffmpeg',
    '$roaming\\com.example\\downoader\\ffmpeg',
  ];
  for (final dir in candidates) {
    if (File('$dir\\ffmpeg.exe').existsSync() &&
        File('$dir\\ffprobe.exe').existsSync()) {
      return dir;
    }
  }
  try {
    final result = await Process.run('ffmpeg', ['-version']);
    if (result.exitCode == 0) return null; // op PATH
  } catch (_) {}
  return null;
}

// yt-dlp lost YouTube's "n"-throttling (nsig) sinds kort niet meer intern op:
// zonder externe JS-runtime worden hoge resoluties stilzwijgend overgeslagen
// en blijft alleen 144p/240p over. De Windows-app downloadt bij eerste gebruik
// een portable Deno naar dezelfde app-datamap; die hergebruiken we hier zodat
// de extensie niet zelf iets hoeft te installeren.
Future<List<String>> resolveJsRuntimeArgs() async {
  final roaming = Platform.environment['APPDATA'] ?? '';
  final candidates = <String>[
    '$roaming\\com.example\\Downloader\\deno\\deno.exe',
    '$roaming\\com.example\\downoader\\deno\\deno.exe',
  ];
  for (final path in candidates) {
    if (File(path).existsSync()) {
      return ['--js-runtimes', 'deno:$path'];
    }
  }
  try {
    final result = await Process.run('deno', ['--version']);
    if (result.exitCode == 0) return ['--js-runtimes', 'deno'];
  } catch (_) {}
  return [];
}

Future<void> runDownload({
  required String url,
  required String format,
  String? formatId,
  required bool isPlaylist,
  required String outputDir,
}) async {
  final exe = await resolveYtDlp();
  await Directory(outputDir).create(recursive: true);
  final outTemplate = '$outputDir${Platform.pathSeparator}%(title)s.%(ext)s';
  final ffmpegDir = await resolveFfmpegDir();
  final jsArgs = await resolveJsRuntimeArgs();

  final args = <String>[
    url,
    '-o',
    outTemplate,
    '--newline',
    '--no-mtime',
    '--print',
    'after_move:$filepathMarker%(filepath)s',
    isPlaylist ? '--yes-playlist' : '--no-playlist',
    // Een oude .part-restant hervatten faalt vaak met HTTP 416: YouTube's
    // ondertekende CDN-URL's zijn maar kort geldig/uniek per aanvraag, dus
    // "verder gaan" op een eerder-mislukte download botst met een nieuwe
    // URL. Altijd opnieuw beginnen is betrouwbaarder dan proberen te hervatten.
    '--no-continue',
    ...playerClientArgs,
    ...jsArgs,
    ...concurrencyArgs,
    if (ffmpegDir != null) ...['--ffmpeg-location', ffmpegDir],
  ];

  if (format == 'mp3') {
    args.addAll(['-x', '--audio-format', 'mp3', '--audio-quality', '0']);
  } else {
    final id = (formatId == null || formatId.isEmpty)
        ? 'bestvideo+bestaudio/best'
        : formatId;
    args.addAll(['-f', id, '--merge-output-format', 'mp4']);
  }

  if (ffmpegDir == null) {
    // Laatste check: zonder ffmpeg faalt merge/postprocess vaak.
    try {
      final probe = await Process.run('ffprobe', ['-version']);
      if (probe.exitCode != 0) {
        await writeMessage({
          'ok': false,
          'done': true,
          'error':
              'ffmpeg/ffprobe niet gevonden. Open eerst de Windows-app één keer (die bundelt ffmpeg), of installeer ffmpeg op PATH.',
        });
        return;
      }
    } catch (_) {
      await writeMessage({
        'ok': false,
        'done': true,
        'error':
            'ffmpeg/ffprobe niet gevonden. Open eerst de Windows-app één keer (die bundelt ffmpeg), of installeer ffmpeg op PATH.',
      });
      return;
    }
  }

  final process = await Process.start(exe, args);
  String? lastPath;
  final stderrBuf = StringBuffer();

  final stderrSub = process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) => stderrBuf.writeln(line));

  await for (final line in process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())) {
    if (line.contains(filepathMarker)) {
      lastPath = line
          .substring(line.indexOf(filepathMarker) + filepathMarker.length)
          .trim();
      await writeMessage({
        'ok': true,
        'line': line,
        if (lastPath.isNotEmpty) 'path': lastPath,
      });
      continue;
    }
    final match = percentRegex.firstMatch(line);
    if (match != null) {
      final pct = double.tryParse(match.group(1)!);
      await writeMessage({
        'ok': true,
        if (pct != null) 'progress': pct,
        'line': line,
      });
      continue;
    }
    if (line.isNotEmpty) {
      await writeMessage({'ok': true, 'line': line});
    }
  }

  final code = await process.exitCode;
  await stderrSub.cancel();

  if (code != 0) {
    await writeMessage({
      'ok': false,
      'done': true,
      'error': shortError(stderrBuf.toString()),
    });
    return;
  }
  final finalPath = lastPath;
  if (finalPath != null && finalPath.isNotEmpty) {
    recordDownloadedItem(
      path: finalPath,
      format: format == 'mp3' ? 'mp3' : 'mp4',
      isPlaylist: isPlaylist,
    );
  }
  await writeMessage({
    'ok': true,
    'done': true,
    if (lastPath != null && lastPath.isNotEmpty) 'path': lastPath,
  });
}

String shortError(String stderr) {
  final lines = stderr.split('\n').where((l) => l.trim().isNotEmpty).toList();
  if (lines.isEmpty) return 'Onbekende fout';
  return lines.last.replaceFirst(RegExp(r'^ERROR:\s*'), '');
}
