import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';

/// Chrome/Edge Native Messaging host for Downloader.
///
/// Settings komen uit / gaan naar dezelfde shared_preferences.json als de
/// Flutter Windows-app (%APPDATA%\com.example\Downloader\).
///
/// Commands:
///   ping | getSettings | setSettings | formats | download | sendToApp |
///   openFolder | openFile | checkFile

// Oudere installaties waarbij de gebruiker yt-dlp zelf naar deze plek had
// gezet blijven werken; nieuwe installaties downloaden yt-dlp automatisch,
// zie resolveYtDlp() hieronder (zelfde aanpak als de Flutter-app).
const String _legacyYtDlpPath = r'C:\Program Files\yt-dlpd.exe';

// yt-dlp's eigen "latest"-release-alias: altijd de nieuwste standalone exe.
const String _ytDlpDownloadUrl =
    'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe';

// Portable, statisch gelinkte Windows-build (GPL, BtbN's altijd-actuele
// "latest" release-tag) — zelfde bron als de Flutter-app gebruikt.
const String _ffmpegDownloadUrl =
    'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip';

// Forceert echte UTF-8-output van yt-dlp (Python-exe) i.p.v. de Windows-
// systeem-codepage, die niet-ASCII tekens in titels/output kan verminken.
final Map<String, String> _ytDlpEnvironment = {
  ...Platform.environment,
  'PYTHONUTF8': '1',
  'PYTHONIOENCODING': 'utf-8',
};

String? _resolvedYtDlpPath;

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
        'ytDlp': _quickYtDlpProbe(),
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
      final downloadFormat =
          msg['format']?.toString() ?? settings['format'] as String;
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
        outputDir:
            msg['outputDir']?.toString() ?? settings['downloadDir'] as String,
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
        await Process.start('explorer.exe', [
          dir,
        ], mode: ProcessStartMode.detached);
        await writeMessage({'ok': true});
      } catch (e) {
        await writeMessage({'ok': false, 'error': e.toString()});
      }
    case 'checkFile':
      final checkPath = msg['path']?.toString() ?? '';
      if (checkPath.isEmpty) {
        await writeMessage({'ok': false, 'error': 'pad ontbreekt'});
        return;
      }
      await writeMessage({'ok': true, 'exists': File(checkPath).existsSync()});
    case 'openFile':
      final filePath = msg['path']?.toString() ?? '';
      if (filePath.isEmpty) {
        await writeMessage({'ok': false, 'error': 'pad ontbreekt'});
        return;
      }
      try {
        // explorer.exe met een bestandspad start het bestand met de
        // standaard-app, net als dubbelklikken.
        await Process.start('explorer.exe', [
          filePath,
        ], mode: ProcessStartMode.detached);
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
    'preferredVideoQuality':
        raw[prefsKeyPreferredVideoQuality]?.toString() ?? 'p1080',
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

Future<List<int>> _downloadBytes(String url) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != 200) {
      throw StateError('Download mislukt (HTTP ${response.statusCode}).');
    }
    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
    }
    return bytes;
  } finally {
    client.close(force: true);
  }
}

// Snelle, niet-downloadende check voor de ping-response (puur informatief).
String _quickYtDlpProbe() {
  if (_resolvedYtDlpPath != null) return _resolvedYtDlpPath!;
  if (File(_legacyYtDlpPath).existsSync()) return _legacyYtDlpPath;
  final bundled = appDataDir().path + r'\yt-dlp\yt-dlp.exe';
  if (File(bundled).existsSync()) return bundled;
  return '(nog niet gedownload)';
}

// yt-dlp hoeft niet meer handmatig geinstalleerd te worden: bij het eerste
// gebruik wordt de nieuwste versie automatisch naar de app-datamap
// gedownload (zelfde patroon als de Flutter-app). Een eerdere handmatige
// installatie op _legacyYtDlpPath blijft ook gewoon werken.
Future<String> resolveYtDlp({void Function(String)? onLog}) async {
  if (_resolvedYtDlpPath != null) return _resolvedYtDlpPath!;

  if (await File(_legacyYtDlpPath).exists()) {
    _resolvedYtDlpPath = _legacyYtDlpPath;
    return _resolvedYtDlpPath!;
  }
  final beside = File(
    File(Platform.resolvedExecutable).parent.path + r'\yt-dlpd.exe',
  );
  if (await beside.exists()) {
    _resolvedYtDlpPath = beside.path;
    return _resolvedYtDlpPath!;
  }

  final target = File(appDataDir().path + r'\yt-dlp\yt-dlp.exe');
  if (await target.exists()) {
    _resolvedYtDlpPath = target.path;
    return _resolvedYtDlpPath!;
  }

  onLog?.call('yt-dlp niet gevonden, laatste versie downloaden...');
  await target.parent.create(recursive: true);
  final bytes = await _downloadBytes(_ytDlpDownloadUrl);
  await target.writeAsBytes(bytes);
  onLog?.call('yt-dlp geinstalleerd.');

  _resolvedYtDlpPath = target.path;
  return _resolvedYtDlpPath!;
}

Future<List<Map<String, dynamic>>> fetchFormats(String url) async {
  final exe = await resolveYtDlp();
  final jsArgs = await resolveJsRuntimeArgs();
  final result = await Process.run(
    exe,
    ['--no-playlist', '-J', ...playerClientArgs, ...jsArgs, url],
    environment: _ytDlpEnvironment,
    // yt-dlp draait als Python-exe; op Windows kan de systeem-codepage
    // niet-UTF8 bytes in titels/output geven. allowMalformed voorkomt een
    // FormatException-crash als PYTHONUTF8 (hierboven) het toch mist.
    stdoutEncoding: const Utf8Codec(allowMalformed: true),
    stderrEncoding: const Utf8Codec(allowMalformed: true),
  );
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
    final hasVideo = vcodec == null || (vcodec != 'none' && vcodec.isNotEmpty);
    if (!hasVideo) continue;
    final acodec = f['acodec']?.toString();
    final hasAudio = acodec == null || (acodec != 'none' && acodec.isNotEmpty);
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

// ffmpeg hoeft niet meer handmatig geinstalleerd te worden: als het niet
// aanwezig is (in de gedeelde app-datamap of op PATH) wordt het bij eerste
// gebruik automatisch gedownload en uitgepakt (zelfde bron/patroon als de
// Flutter-app). Retourneert de map voor --ffmpeg-location, of null als
// systeem-ffmpeg (PATH) volstaat.
Future<String?> ensureFfmpegDir({void Function(String)? onLog}) async {
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

  onLog?.call('ffmpeg niet gevonden, portable versie downloaden...');
  final targetDir = Directory(appDataDir().path + r'\ffmpeg');
  await targetDir.create(recursive: true);
  final bytes = await _downloadBytes(_ffmpegDownloadUrl);

  onLog?.call('ffmpeg uitpakken...');
  final archive = ZipDecoder().decodeBytes(bytes);
  var foundFfmpeg = false;
  var foundFfprobe = false;
  for (final file in archive.files) {
    if (!file.isFile) continue;
    final name = file.name.replaceAll('\\', '/');
    if (name.endsWith('/bin/ffmpeg.exe')) {
      await File(
        '${targetDir.path}\\ffmpeg.exe',
      ).writeAsBytes(file.content as List<int>);
      foundFfmpeg = true;
    } else if (name.endsWith('/bin/ffprobe.exe')) {
      await File(
        '${targetDir.path}\\ffprobe.exe',
      ).writeAsBytes(file.content as List<int>);
      foundFfprobe = true;
    }
  }
  if (!foundFfmpeg || !foundFfprobe) {
    throw StateError('ffmpeg.exe/ffprobe.exe niet gevonden in download.');
  }
  onLog?.call('ffmpeg geinstalleerd.');
  return targetDir.path;
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
  void onLog(String line) {
    writeMessage({'ok': true, 'line': line});
  }

  final String exe;
  final String? ffmpegDir;
  try {
    exe = await resolveYtDlp(onLog: onLog);
    ffmpegDir = await ensureFfmpegDir(onLog: onLog);
  } catch (e) {
    await writeMessage({'ok': false, 'done': true, 'error': e.toString()});
    return;
  }

  await Directory(outputDir).create(recursive: true);
  final outTemplate = '$outputDir${Platform.pathSeparator}%(title)s.%(ext)s';
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

  final process = await Process.start(
    exe,
    args,
    environment: _ytDlpEnvironment,
  );
  String? lastPath;
  final stderrBuf = StringBuffer();

  const lenientUtf8 = Utf8Decoder(allowMalformed: true);
  final stderrSub = process.stderr
      .transform(lenientUtf8)
      .transform(const LineSplitter())
      .listen((line) => stderrBuf.writeln(line));

  await for (final line
      in process.stdout
          .transform(lenientUtf8)
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
