import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'l10n.dart';
import 'models.dart';
import 'settings.dart';
import 'settings_page.dart';
import 'theme.dart';
import 'window_bridge.dart';
import 'ytdlp_service.dart';

const _intentChannel = MethodChannel('downoader/intent');

String? _argValue(List<String> args, String name) {
  final prefix = '--$name=';
  for (final a in args) {
    if (a.startsWith(prefix)) return a.substring(prefix.length);
  }
  final i = args.indexOf('--$name');
  if (i >= 0 && i + 1 < args.length) return args[i + 1];
  return null;
}

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }
  runApp(
    DownoaderApp(
      initialUrl: _argValue(args, 'url'),
      initialFormat: _argValue(args, 'format'),
      initialFormatId: _argValue(args, 'formatId'),
    ),
  );
}

class DownoaderApp extends StatefulWidget {
  final String? initialUrl;
  final String? initialFormat;
  final String? initialFormatId;

  const DownoaderApp({
    super.key,
    this.initialUrl,
    this.initialFormat,
    this.initialFormatId,
  });

  @override
  State<DownoaderApp> createState() => _DownoaderAppState();
}

class _DownoaderAppState extends State<DownoaderApp> {
  ThemeMode _themeMode = ThemeMode.dark;
  AppLanguage _language = AppLanguage.nl;

  @override
  void initState() {
    super.initState();
    _loadDarkMode();
    _loadLanguage();
    if (Platform.isWindows) {
      Settings.setAppExePath(Platform.resolvedExecutable);
    }
  }

  Future<void> _loadDarkMode() async {
    final dark = await Settings.getDarkMode();
    setState(() => _themeMode = dark ? ThemeMode.dark : ThemeMode.light);
  }

  void _toggleDarkMode(bool dark) {
    setState(() => _themeMode = dark ? ThemeMode.dark : ThemeMode.light);
    Settings.setDarkMode(dark);
  }

  Future<void> _loadLanguage() async {
    final language = await Settings.getLanguage();
    setState(() => _language = language);
  }

  void _changeLanguage(AppLanguage language) {
    setState(() => _language = language);
    Settings.setLanguage(language);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Downloader',
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: _themeMode,
      home: HomePage(
        key: const ValueKey('home'),
        isDarkMode: _themeMode == ThemeMode.dark,
        onToggleDarkMode: _toggleDarkMode,
        language: _language,
        onChangeLanguage: _changeLanguage,
        initialUrl: widget.initialUrl,
        initialFormat: widget.initialFormat,
        initialFormatId: widget.initialFormatId,
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  final bool isDarkMode;
  final ValueChanged<bool> onToggleDarkMode;
  final AppLanguage language;
  final ValueChanged<AppLanguage> onChangeLanguage;
  final String? initialUrl;
  final String? initialFormat;
  final String? initialFormatId;

  const HomePage({
    super.key,
    required this.isDarkMode,
    required this.onToggleDarkMode,
    required this.language,
    required this.onChangeLanguage,
    this.initialUrl,
    this.initialFormat,
    this.initialFormatId,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _urlController = TextEditingController();
  final _service = YtDlpService();

  OutputFormat _format = OutputFormat.mp4;
  PreferredVideoQuality _videoQuality = PreferredVideoQuality.p1080;
  bool _autoDownloadOnClick = false;
  PlaylistMode _playlistMode = PlaylistMode.ask;
  CookiesBrowser _cookiesBrowser = CookiesBrowser.none;
  String _downloadDir = '';
  bool _busy = false;
  double _progress = 0;
  String _status = '';
  final List<DownloadedItem> _downloaded = [];
  String? _activePlaylistId;
  final Set<String> _expandedPlaylistIds = {};

  final _searchController = TextEditingController();
  String _searchQuery = '';
  FileFilter _fileFilter = FileFilter.all;

  final List<String> _logs = [];
  // Logpaneel leeft nu in Settings (aparte route); een simpele teller-
  // notifier laat dat scherm herbouwen zonder de hele HomePage te raken.
  final ValueNotifier<int> _logsTick = ValueNotifier(0);
  bool _showLogs = false;
  Timer? _inboxTimer;
  Timer? _completedTimer;
  StreamSubscription<FileSystemEvent>? _completedWatch;
  String? _pendingFormatId;
  bool _inboxPolling = false;
  bool _completedMerging = false;

  L10n get t => L10n(widget.language);

  void _addLog(String message) {
    _logs.add(message);
    if (_logs.length > 5000) _logs.removeAt(0);
    _logsTick.value++;
  }

  IconData get _playlistModeIcon {
    switch (_playlistMode) {
      case PlaylistMode.playlist:
        return Icons.playlist_play;
      case PlaylistMode.single:
        return Icons.filter_1;
      case PlaylistMode.ask:
        return Icons.help_outline;
    }
  }

  String get _playlistModeTooltip => t.playlistModeTooltip(_playlistMode);

  void _cyclePlaylistMode() {
    const order = [
      PlaylistMode.ask,
      PlaylistMode.playlist,
      PlaylistMode.single,
    ];
    final next = order[(order.indexOf(_playlistMode) + 1) % order.length];
    setState(() => _playlistMode = next);
    Settings.setPlaylistMode(next);
  }

  List<DownloadedItem> get _filteredDownloaded {
    return _downloaded.where((item) {
      if (_fileFilter == FileFilter.video && item.format != OutputFormat.mp4)
        return false;
      if (_fileFilter == FileFilter.audio && item.format != OutputFormat.mp3)
        return false;
      if (_searchQuery.isNotEmpty &&
          !item.fileName.toLowerCase().contains(_searchQuery.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();
  }

  // Groepeert playlist-items met dezelfde playlistId tot één rij; alleen
  // actief zonder filter/zoekopdracht, anders zou het eerste nummer kunnen
  // wegfilteren terwijl de rest van de groep nog matcht.
  List<Object> get _displayRows {
    final items = _filteredDownloaded;
    final grouped = _fileFilter == FileFilter.all && _searchQuery.isEmpty;
    if (!grouped) return items;

    final rows = <Object>[];
    final seenGroups = <String>{};
    for (final item in items) {
      final gid = item.playlistId;
      if (gid == null) {
        rows.add(item);
        continue;
      }
      if (!seenGroups.add(gid)) continue;
      final groupItems = items.where((i) => i.playlistId == gid).toList()
        ..sort(
          (a, b) => (a.playlistIndex ?? 0).compareTo(b.playlistIndex ?? 0),
        );
      rows.add(_PlaylistGroupRow(gid, groupItems));
    }
    return rows;
  }

  Widget _buildDownloadedTile(DownloadedItem item, {bool indented = false}) {
    return ListTile(
      contentPadding: indented
          ? const EdgeInsets.only(left: 32, right: 16)
          : null,
      leading: Icon(
        item.isPlaylist
            ? Icons.playlist_play
            : (item.format == OutputFormat.mp3
                  ? Icons.audiotrack
                  : Icons.movie_outlined),
      ),
      title: Text(item.fileName),
      subtitle: item.isPlaylist && item.playlistId == null
          ? Text(t.partOfPlaylist)
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.folder_open, size: 18),
            tooltip: t.openFolderTooltip,
            onPressed: () => _openItemFolder(item.path),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            tooltip: t.deleteTooltip,
            onPressed: () => _deleteItem(item),
          ),
        ],
      ),
      onTap: () => _openFile(item.path),
    );
  }

  Widget _buildPlaylistGroupTile(_PlaylistGroupRow group) {
    final head = group.items.first;
    final expanded = _expandedPlaylistIds.contains(group.id);
    final downloading = group.id == _activePlaylistId;
    void toggle() => setState(() {
      if (expanded) {
        _expandedPlaylistIds.remove(group.id);
      } else {
        _expandedPlaylistIds.add(group.id);
      }
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: downloading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(expanded ? Icons.expand_less : Icons.expand_more),
          title: Text(head.fileName),
          subtitle: Text(
            t.playlistProgress(group.items.length, head.playlistTotal),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.play_arrow, size: 20),
            tooltip: t.playFileTooltip,
            onPressed: () => _openFile(head.path),
          ),
          onTap: toggle,
        ),
        if (expanded)
          for (final item in group.items.skip(1))
            _buildDownloadedTile(item, indented: true),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    // Extentie-sync meteen starten — niet wachten op prefs-loads die op
    // Windows soms blokkeren; anders blijven downloads onzichtbaar tot restart.
    if (Platform.isWindows) {
      _completedTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        _mergeExtensionDownloads();
      });
      _inboxTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        _pollExtensionInbox();
      });
      _startCompletedFileWatch();
      unawaited(_mergeExtensionDownloads());
      unawaited(_pollExtensionInbox());
    }
    if (Platform.isAndroid) {
      // Python/ffmpeg uitpakken nu vast starten. Deed de Download-knop dat
      // zelf, dan viel dat zware werk samen met het starten van het
      // yt-dlp-kindproces en schoot Android het app-proces af.
      unawaited(_service.warmUp(onLog: _addLog));
    }
    _bootstrap();
  }

  @override
  void dispose() {
    if (Platform.isAndroid && _busy) unawaited(_service.cancelDownload());
    _inboxTimer?.cancel();
    _completedTimer?.cancel();
    _completedWatch?.cancel();
    _urlController.dispose();
    _searchController.dispose();
    _logsTick.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await Future.wait([
      _loadDir(),
      _loadDownloaded(),
      _loadPlaylistMode(),
      _loadFormat(),
      _loadVideoQuality(),
      _loadAutoDownloadOnClick(),
      _loadCookiesBrowser(),
    ]);
    if (widget.initialFormat != null) {
      final f = OutputFormat.values.where((e) => e.name == widget.initialFormat);
      if (f.isNotEmpty) {
        setState(() => _format = f.first);
        await Settings.setDefaultFormat(f.first);
      }
    }
    if (widget.initialFormatId != null && widget.initialFormatId!.isNotEmpty) {
      _pendingFormatId = widget.initialFormatId;
    }
    if (widget.initialUrl != null && widget.initialUrl!.isNotEmpty) {
      _urlController.text = widget.initialUrl!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startDownload(formatIdOverride: _pendingFormatId);
      });
    }
    if (Platform.isAndroid) {
      _listenAndroidIntents();
    }
  }

  void _listenAndroidIntents() {
    _intentChannel.setMethodCallHandler((call) async {
      if (call.method == 'incomingUrl') {
        _handleIncomingFromAndroid(call.arguments);
      }
    });
    _intentChannel.invokeMethod<dynamic>('getInitialUrl').then((args) {
      if (!mounted || args == null) return;
      if (widget.initialUrl != null && widget.initialUrl!.isNotEmpty) return;
      _handleIncomingFromAndroid(args);
    }).catchError((_) {});
  }

  Future<void> _handleIncomingFromAndroid(dynamic args) async {
    String? url;
    String? formatName;
    Map? settingsPatch;
    if (args is String) {
      url = args;
    } else if (args is Map) {
      url = args['url']?.toString();
      formatName = args['format']?.toString();
      // Op Android heeft de extentie geen native messaging, dus geen inbox.
      // De gedeelde instellingen reizen daarom mee in de downoader://-link;
      // zo veranderen extentie en app daar ook samen.
      settingsPatch = args;
    }
    if (url == null || url.isEmpty) return;
    if (settingsPatch != null) {
      await _applyInboxSettings(settingsPatch);
      if (!mounted) return;
    }
    setState(() {
      _urlController.text = url!;
      if (formatName != null) {
        final match = OutputFormat.values.where((e) => e.name == formatName);
        if (match.isNotEmpty) _format = match.first;
      }
    });
    if (!_busy) _startDownload();
  }

  DownloadedItem _itemFromInboxMap(Map job) {
    final formatName = job['format']?.toString();
    final formatMatch = OutputFormat.values.where((e) => e.name == formatName);
    return DownloadedItem(
      path: job['path']?.toString() ?? '',
      isPlaylist: job['isPlaylist'] == true,
      format: formatMatch.isNotEmpty ? formatMatch.first : OutputFormat.mp4,
      playlistId: job['playlistId']?.toString(),
      playlistIndex: (job['playlistIndex'] as num?)?.toInt(),
      playlistTotal: (job['playlistTotal'] as num?)?.toInt(),
    );
  }

  Future<void> _startCompletedFileWatch() async {
    try {
      final file = await Settings.extensionCompletedFile();
      await file.parent.create(recursive: true);
      if (!await file.exists()) {
        await file.writeAsString('');
      }
      await _completedWatch?.cancel();
      // Directe melding zodra de host een regel append — sneller dan alleen pollen.
      _completedWatch = file.watch(events: FileSystemEvent.modify).listen((_) {
        _mergeExtensionDownloads();
        _pollExtensionInbox();
      }, onError: (_) {});
    } catch (e) {
      _addLog('Extentie file-watch niet gestart: $e');
    }
  }

  Future<void> _rememberDownloadedItem(DownloadedItem item) async {
    if (!mounted || item.path.isEmpty) return;
    if (_downloaded.any((i) => i.path == item.path)) return;
    // UI bijwerken zonder de app naar voren te trekken (Windows focus-steal).
    await WindowBridge.withoutStealingFocus(() async {
      if (!mounted) return;
      if (_downloaded.any((i) => i.path == item.path)) return;
      setState(() => _downloaded.insert(0, item));
      _addLog('Extentie: bestand gedownload (${item.path})');
    });
    final snapshot = List<DownloadedItem>.of(_downloaded);
    unawaited(Future(() async {
      try {
        await Settings.setDownloadedItems(snapshot);
        await Settings.addDownloadHistoryItem(item);
        await Settings.addFolderHistory(p.dirname(item.path));
      } catch (e) {
        if (mounted) _addLog('Extentie: lijst opslaan mislukt ($e)');
      }
    }));
  }

  Future<void> _mergeExtensionDownloads() async {
    if (!mounted || !Platform.isWindows || _completedMerging) return;
    _completedMerging = true;
    try {
      final batch = await Settings.readExtensionCompleted();
      for (final item in batch.items) {
        await _rememberDownloadedItem(item);
      }
      if (batch.items.isNotEmpty) {
        await Settings.markExtensionCompletedOffset(batch.offset);
      }
    } catch (e) {
      _addLog('Extentie-merge fout: $e');
    } finally {
      _completedMerging = false;
    }
  }

  Future<void> _applyInboxSettings(Map patch) async {
    final downloadDir = patch['downloadDir']?.toString();
    if (downloadDir != null && downloadDir.isNotEmpty) {
      await Settings.setDownloadDir(downloadDir);
      await Settings.addFolderHistory(downloadDir);
      setState(() => _downloadDir = downloadDir);
    }
    final playlistMode = patch['playlistMode']?.toString();
    if (playlistMode != null) {
      final mode = PlaylistMode.values.where((e) => e.name == playlistMode);
      if (mode.isNotEmpty) {
        await Settings.setPlaylistMode(mode.first);
        setState(() => _playlistMode = mode.first);
      }
    }
    final formatName = patch['format']?.toString();
    if (formatName != null) {
      final match = OutputFormat.values.where((e) => e.name == formatName);
      if (match.isNotEmpty) {
        await Settings.setDefaultFormat(match.first);
        setState(() => _format = match.first);
      }
    }
    final qualityName = patch['preferredVideoQuality']?.toString();
    if (qualityName != null) {
      final match = PreferredVideoQuality.values.where(
        (e) => e.name == qualityName,
      );
      if (match.isNotEmpty) {
        await Settings.setPreferredVideoQuality(match.first);
        setState(() => _videoQuality = match.first);
      }
    }
    final autoDownload = patch['autoDownloadOnClick'];
    if (autoDownload is bool) {
      await Settings.setAutoDownloadOnClick(autoDownload);
      setState(() => _autoDownloadOnClick = autoDownload);
    }
    final cookiesBrowser = patch['cookiesBrowser']?.toString();
    if (cookiesBrowser != null) {
      final match = CookiesBrowser.values.where(
        (e) => e.name == cookiesBrowser,
      );
      if (match.isNotEmpty) {
        await Settings.setCookiesBrowser(match.first);
        setState(() => _cookiesBrowser = match.first);
      }
    }
  }

  Future<void> _pollExtensionInbox() async {
    if (!mounted || _inboxPolling) return;
    _inboxPolling = true;
    final deferredUrls = <Map<String, dynamic>>[];
    try {
      while (mounted) {
        final job = await Settings.takeExtensionInbox();
        if (job == null) break;

        final type = job['type']?.toString();
        if (type == 'downloaded') {
          await _rememberDownloadedItem(_itemFromInboxMap(job));
          continue;
        }

        final patch = job['settings'];
        if (patch is Map) {
          await _applyInboxSettings(patch);
        }
        if (type == 'settings') {
          _addLog('Extentie: app-instellingen bijgewerkt');
          continue;
        }

        final url = job['url']?.toString() ?? '';
        if (url.isEmpty) continue;

        // URL-jobs uitstellen i.p.v. de wachtrij te stoppen — anders blijven
        // latere "downloaded"-meldingen hangen tot een herstart.
        if (_busy) {
          deferredUrls.add(job);
          continue;
        }

        setState(() {
          _urlController.text = url;
          final formatName = job['format']?.toString();
          if (formatName != null) {
            final match = OutputFormat.values.where((e) => e.name == formatName);
            if (match.isNotEmpty) _format = match.first;
          }
        });
        final formatName = job['format']?.toString();
        if (formatName != null) {
          final match = OutputFormat.values.where((e) => e.name == formatName);
          if (match.isNotEmpty) await Settings.setDefaultFormat(match.first);
        }
        final formatId = job['formatId']?.toString();
        _addLog('Extentie: download gestart voor $url');
        _startDownload(formatIdOverride: formatId);
        break;
      }
    } catch (e) {
      _addLog('Extentie-inbox fout: $e');
    } finally {
      for (final job in deferredUrls.reversed) {
        try {
          await Settings.prependExtensionInbox(job);
        } catch (_) {}
      }
      _inboxPolling = false;
    }
  }

  Future<void> _loadFormat() async {
    final format = await Settings.getDefaultFormat();
    setState(() => _format = format);
  }

  Future<void> _loadVideoQuality() async {
    final q = await Settings.getPreferredVideoQuality();
    setState(() => _videoQuality = q);
  }

  Future<void> _loadAutoDownloadOnClick() async {
    final value = await Settings.getAutoDownloadOnClick();
    setState(() => _autoDownloadOnClick = value);
  }

  Future<void> _loadCookiesBrowser() async {
    final value = await Settings.getCookiesBrowser();
    setState(() => _cookiesBrowser = value);
  }

  Future<void> _loadPlaylistMode() async {
    final mode = await Settings.getPlaylistMode();
    setState(() => _playlistMode = mode);
  }

  Future<void> _loadDir() async {
    final dir = await Settings.getDownloadDir();
    setState(() => _downloadDir = dir);
    if (dir.isNotEmpty) await Settings.addFolderHistory(dir);
  }

  Future<void> _loadDownloaded() async {
    final items = await Settings.getDownloadedItems(reload: true);
    final existing = items.where((i) => File(i.path).existsSync()).toList();
    setState(() {
      _downloaded.clear();
      _downloaded.addAll(existing);
    });
    if (existing.length != items.length) {
      await Settings.setDownloadedItems(existing);
    }
  }

  Future<void> _startDownload({String? formatIdOverride}) async {
    if (_busy) return;

    var url = _urlController.text.trim();
    if (url.isEmpty) {
      final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
      final clipboardText = clipboard?.text?.trim() ?? '';
      // Alleen overnemen als het klembord echt een link bevat. Zonder deze
      // check belandde bijvoorbeeld een net gekopieerd logblok in het veld en
      // probeerde yt-dlp dat als URL te downloaden.
      if (_looksLikeUrl(clipboardText)) {
        url = clipboardText;
        _urlController.text = url;
      }
    }
    if (url.isEmpty) return;
    if (!_isPlausibleUrl(url)) {
      _showError(t.errInvalidUrl);
      return;
    }

    setState(() => _busy = true);
    try {
      // Android: initialiseert youtubedl-android. Desktop: yt-dlp.exe.
      await _service.ensureYtDlp(onLog: _addLog);
    } catch (e) {
      setState(() => _busy = false);
      _addLog('FOUT: $e');
      _showError(t.errInstallYtDlp('$e'));
      return;
    }
    String? ffmpegDir;
    if (!Platform.isAndroid) {
      try {
        ffmpegDir = await _service.ensureFfmpeg(onLog: _addLog);
      } catch (e) {
        setState(() => _busy = false);
        _addLog('FOUT: $e');
        _showError(t.errInstallFfmpeg('$e'));
        return;
      }
    }

    try {
      await Directory(_downloadDir).create(recursive: true);
    } catch (e) {
      setState(() => _busy = false);
      _addLog('FOUT: map aanmaken mislukt: $e');
      _showError(t.downloadFailed('$e'));
      return;
    }

    await _ensureFreshYtDlp();

    setState(() {
      _busy = true;
      _progress = 0;
      _status = 'Controleren of het een playlist is...';
    });
    _addLog('----- Download gestart: $url -----');

    bool isPlaylist = false;
    PlaylistProbeResult probe;
    try {
      probe = await _service.probePlaylist(url);
      if (probe.isPlaylist && probe.entryCount > 1) {
        switch (_playlistMode) {
          case PlaylistMode.playlist:
            isPlaylist = true;
          case PlaylistMode.single:
            isPlaylist = false;
          case PlaylistMode.ask:
            final choice = await _askPlaylistChoice();
            if (choice == null) {
              setState(() {
                _busy = false;
                _status = '';
              });
              return;
            }
            isPlaylist = choice;
        }
      }
    } catch (e) {
      setState(() {
        _busy = false;
        _status = '';
      });
      _addLog('FOUT: $e');
      _showError(t.errCheckUrl('$e'));
      return;
    }

    String? formatId = formatIdOverride;
    if (_format == OutputFormat.mp4 && formatId == null) {
      if (_videoQuality != PreferredVideoQuality.ask) {
        formatId = _videoQuality.formatSelector;
      } else {
        List<FormatInfo> formats;
        try {
          if (probe.isPlaylist) {
            setState(() => _status = 'Kwaliteiten ophalen...');
            formats = await _service.fetchFormats(url);
          } else {
            // Niet-playlist URL: de probe-call heeft de volledige info al
            // opgehaald, dus geen tweede yt-dlp-aanroep nodig.
            formats = _service.parseFormats(probe.data);
          }
        } catch (e) {
          setState(() {
            _busy = false;
            _status = '';
          });
          _addLog('FOUT: $e');
          _showError(t.errFetchQualities('$e'));
          return;
        }
        if (formats.isEmpty) {
          setState(() {
            _busy = false;
            _status = '';
          });
          _showError(t.noFormatsFound);
          return;
        }
        final chosen = await _askQuality(formats);
        if (chosen == null) {
          setState(() {
            _busy = false;
            _status = '';
          });
          return;
        }
        formatId = chosen.hasAudio
            ? chosen.formatId
            : '${chosen.formatId}+bestaudio/best';
      }
    }

    setState(() {
      _progress = 0;
      _status = 'Downloaden...';
    });

    final playlistId = isPlaylist
        ? DateTime.now().microsecondsSinceEpoch.toString()
        : null;
    final playlistTotal = isPlaylist ? probe.entryCount : null;
    if (playlistId != null) {
      setState(() => _activePlaylistId = playlistId);
    }
    var playlistIndex = 0;
    try {
      await for (final event in _service.download(
        url: url,
        outputDir: _downloadDir,
        isPlaylist: isPlaylist,
        format: _format,
        formatId: formatId,
        ffmpegDir: ffmpegDir,
      )) {
        if (event is ProgressEvent) {
          setState(() => _progress = event.percent / 100);
        } else if (event is FileDownloadedEvent) {
          final downloadedItem = DownloadedItem(
            path: event.path,
            isPlaylist: isPlaylist,
            format: _format,
            playlistId: playlistId,
            playlistIndex: isPlaylist ? playlistIndex : null,
            playlistTotal: playlistTotal,
          );
          playlistIndex++;
          setState(() {
            _downloaded.insert(0, downloadedItem);
          });
          Settings.setDownloadedItems(_downloaded);
          Settings.addDownloadHistoryItem(downloadedItem);
          Settings.addFolderHistory(p.dirname(event.path));
        } else if (event is StatusEvent) {
          setState(() => _status = event.message);
        } else if (event is LogEvent) {
          _addLog(event.message);
        } else if (event is DownloadDoneEvent) {
          if (!event.success) {
            _addLog('FOUT: ${event.error}');
            _showError(t.downloadFailed('${event.error}'));
          } else {
            _addLog('Download voltooid.');
          }
        }
      }
    } catch (e) {
      _addLog('FOUT: $e');
      _showError(t.downloadFailed('$e'));
    }

    setState(() {
      _busy = false;
      _progress = 0;
      _status = '';
      if (_activePlaylistId == playlistId) _activePlaylistId = null;
    });
  }

  Future<bool?> _askPlaylistChoice() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.playlistDetectedTitle),
        content: Text(t.playlistDetectedContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t.onlyThisVideo),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.wholePlaylist),
          ),
        ],
      ),
    );
  }

  Future<FormatInfo?> _askQuality(List<FormatInfo> formats) {
    return showDialog<FormatInfo>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.chooseQualityTitle),
        content: SizedBox(
          width: 360,
          height: 400,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: formats.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final f = formats[i];
              return ListTile(
                title: Text(f.label),
                subtitle: Text(f.hasAudio ? t.videoAndAudio : t.videoOnly),
                onTap: () => Navigator.pop(ctx, f),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t.cancel),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  void _showInfo(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _saveLogs() async {
    if (_logs.isEmpty) {
      _showError(t.noLogsToSave);
      return;
    }
    try {
      final dir = _downloadDir.isNotEmpty
          ? _downloadDir
          : (await getTemporaryDirectory()).path;
      await Directory(dir).create(recursive: true);
      final fileName =
          'downloader_log_${DateTime.now().millisecondsSinceEpoch}.txt';
      final file = File('$dir${Platform.pathSeparator}$fileName');
      await file.writeAsString(_logs.join('\n'));
      _showInfo(t.logSaved(file.path));
      if (Platform.isAndroid) {
        // Niet openFolder(): dat is ACTION_VIEW met "resource/folder", waar
        // geen enkele app iets mee kan, en de terugval opent een .txt in een
        // lijst willekeurige apps. De deelsheet geeft wel echte bestemmingen
        // (mail, Drive, Nearby Share, koppeling met de PC).
        await _service.shareFile(file.path);
      } else {
        await _service.openFolder(file.path);
      }
    } catch (e) {
      _showError(t.errSaveLog('$e'));
    }
  }

  /// Haalt de nieuwste yt-dlp op. Geeft de nieuwe versie terug, of null.
  /// Streng: gebruikt voor klembord-inhoud die we ongevraagd overnemen.
  bool _looksLikeUrl(String text) {
    if (!_isPlausibleUrl(text)) return false;
    final uri = Uri.tryParse(text);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  /// Soepel: laat 'youtube.com/watch?v=x' zonder schema door, maar houdt
  /// meerregelige tekst en plakfouten tegen.
  bool _isPlausibleUrl(String text) {
    if (text.isEmpty || text.length > 2048) return false;
    return !text.contains(RegExp(r'\s'));
  }

  /// yt-dlp verouderdt snel: een build van maanden oud geeft op YouTube
  /// "HTTP Error 403" of "Requested format is not available". De versiestring
  /// is een datum (2025.11.12), dus de leeftijd is direct af te lezen.
  Future<void> _ensureFreshYtDlp() async {
    if (!Platform.isAndroid) return;
    final version = await _service.androidYtDlpVersion();
    if (version == null) return;
    final parts = version.split('.');
    if (parts.length < 3) return;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2].split('-').first);
    if (year == null || month == null || day == null) return;
    final age = DateTime.now().difference(DateTime(year, month, day)).inDays;
    if (age < 30) return;
    setState(() => _status = 'yt-dlp bijwerken...');
    _addLog('yt-dlp $version is $age dagen oud, bijwerken...');
    try {
      final result = await _service.updateAndroidYtDlp();
      await Settings.setYtDlpUpdateCheck(DateTime.now().millisecondsSinceEpoch);
      _addLog(
        result.updated
            ? 'yt-dlp bijgewerkt naar ${result.version ?? "nieuwste"}.'
            : 'yt-dlp was al de nieuwste versie ($version).',
      );
    } catch (e) {
      _addLog('FOUT: yt-dlp bijwerken mislukt: $e');
    }
  }

  Future<String?> _updateYtDlp() async {
    try {
      final result = await _service.updateAndroidYtDlp();
      final version = result.version;
      if (result.updated && version != null) {
        _addLog('yt-dlp bijgewerkt naar $version.');
        _showInfo(t.ytDlpUpdated(version));
      } else {
        _showInfo(t.ytDlpAlreadyLatest);
      }
      await Settings.setYtDlpUpdateCheck(DateTime.now().millisecondsSinceEpoch);
      return version;
    } catch (e) {
      _addLog('FOUT: yt-dlp bijwerken mislukt: $e');
      _showError(t.errUpdateYtDlp('$e'));
      return null;
    }
  }

  Future<void> _shareLogs() async {
    if (_logs.isEmpty) {
      _showError(t.noLogsToSave);
      return;
    }
    final text = _logs.join('\n');
    try {
      if (Platform.isAndroid) {
        await _service.shareText(text, subject: 'Downloader logs');
      } else {
        await Clipboard.setData(ClipboardData(text: text));
        _showInfo(t.logsCopied);
      }
    } catch (e) {
      _showError(t.errSaveLog('\$e'));
    }
  }

  Future<void> _openFile(String path) async {
    try {
      await _service.openFile(path);
    } catch (e) {
      _showError(t.errOpenFile('$e'));
    }
  }

  Future<void> _openItemFolder(String path) async {
    try {
      await _service.openFolder(path);
    } catch (e) {
      _showError(t.errOpenFolder('$e'));
    }
  }

  Future<void> _openDownloadFolder() async {
    if (_downloadDir.isEmpty || Platform.isAndroid) return;
    try {
      await Process.start('explorer.exe', [
        _downloadDir,
      ], mode: ProcessStartMode.detached);
    } catch (e) {
      _showError(t.errOpenFolder('$e'));
    }
  }

  Future<bool> _confirmDialog(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(t.deleteConfirmButton),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _deleteItem(DownloadedItem item) async {
    final confirmed = await _confirmDialog(
      t.deleteFileTitle,
      t.deleteFileMessage(item.fileName),
    );
    if (!confirmed) return;
    try {
      final file = File(item.path);
      if (await file.exists()) await file.delete();
    } catch (e) {
      _showError(t.errDeleteFile('$e'));
      return;
    }
    setState(() => _downloaded.remove(item));
    await Settings.setDownloadedItems(_downloaded);
    _addLog('Verwijderd: ${item.fileName}');
  }

  Future<void> _deleteAllItems() async {
    if (_downloaded.isEmpty) return;
    final confirmed = await _confirmDialog(
      t.deleteAllTitle,
      t.deleteAllMessage(_downloaded.length),
    );
    if (!confirmed) return;
    final items = List<DownloadedItem>.from(_downloaded);
    var failed = 0;
    for (final item in items) {
      try {
        final file = File(item.path);
        if (await file.exists()) await file.delete();
      } catch (_) {
        failed++;
      }
    }
    setState(() => _downloaded.clear());
    await Settings.setDownloadedItems(_downloaded);
    _addLog('Alle bestanden verwijderd${failed > 0 ? ' ($failed mislukt)' : ''}.');
    if (failed > 0) {
      _showError(t.errDeleteSome(failed));
    }
  }

  @override
  Widget build(BuildContext context) {
    // canPop: false → Android-back op root finish’t de activity niet
    // (dat oogt als minimaliseren + herladen). Home-knop blijft gewoon werken.
    return PopScope(
      canPop: false,
      child: Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const _AppBarTitle(),
        actions: [
          IconButton(
            icon: Icon(_playlistModeIcon),
            tooltip: _playlistModeTooltip,
            onPressed: _cyclePlaylistMode,
          ),
          if (!Platform.isAndroid)
            IconButton(
              icon: const Icon(Icons.folder_open),
              tooltip: t.openDownloadFolderTooltip,
              onPressed: _downloadDir.isEmpty ? null : _openDownloadFolder,
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: t.settingsTooltip,
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsPage(
                    isDarkMode: widget.isDarkMode,
                    onToggleDarkMode: widget.onToggleDarkMode,
                    language: widget.language,
                    onChangeLanguage: widget.onChangeLanguage,
                    downloadDir: _downloadDir,
                    onChangeDownloadDir: (dir) =>
                        setState(() => _downloadDir = dir),
                    autoDownloadOnClick: _autoDownloadOnClick,
                    onChangeAutoDownloadOnClick: (value) {
                      setState(() => _autoDownloadOnClick = value);
                      Settings.setAutoDownloadOnClick(value);
                    },
                    cookiesBrowser: _cookiesBrowser,
                    onChangeCookiesBrowser: (value) {
                      setState(() => _cookiesBrowser = value);
                      Settings.setCookiesBrowser(value);
                    },
                    showLogs: _showLogs,
                    onToggleShowLogs: (value) =>
                        setState(() => _showLogs = value),
                    onSaveLogs: _saveLogs,
                    onShareLogs: _shareLogs,
                    onUpdateYtDlp: _updateYtDlp,
                    ytDlpVersion: _service.androidYtDlpVersion,
                    logs: _logs,
                    logsTick: _logsTick,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _urlController,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.done,
                      autocorrect: false,
                      enableSuggestions: false,
                      smartDashesType: SmartDashesType.disabled,
                      smartQuotesType: SmartQuotesType.disabled,
                      decoration: InputDecoration(
                        labelText: t.urlLabel,
                        border: const OutlineInputBorder(),
                      ),
                      enabled: !_busy,
                      // Geen auto-download op toetsenbord-actie: sommige IME’s
                      // sturen bij spatie/enter een submit → zware init →
                      // activity weg + herladen.
                      onSubmitted: (_) => FocusScope.of(context).unfocus(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _busy ? null : _startDownload,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download),
                    label: Text(t.downloadButton),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(t.formatLabel),
                  const SizedBox(width: 8),
                  SegmentedButton<OutputFormat>(
                    segments: const [
                      ButtonSegment(
                        value: OutputFormat.mp4,
                        label: Text('MP4'),
                        icon: Icon(Icons.movie),
                      ),
                      ButtonSegment(
                        value: OutputFormat.mp3,
                        label: Text('MP3'),
                        icon: Icon(Icons.audiotrack),
                      ),
                    ],
                    selected: {_format},
                    onSelectionChanged: _busy
                        ? null
                        : (s) {
                            final next = s.first;
                            setState(() => _format = next);
                            Settings.setDefaultFormat(next);
                          },
                  ),
                ],
              ),
              if (_format == OutputFormat.mp4) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(t.mp4QualityLabel),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<PreferredVideoQuality>(
                        value: _videoQuality,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        items: PreferredVideoQuality.values
                            .map(
                              (q) => DropdownMenuItem(
                                value: q,
                                child: Text(t.qualityLabel(q)),
                              ),
                            )
                            .toList(),
                        onChanged: _busy
                            ? null
                            : (q) {
                                if (q == null) return;
                                setState(() => _videoQuality = q);
                                Settings.setPreferredVideoQuality(q);
                              },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _videoQuality == PreferredVideoQuality.ask
                      ? t.qualityAskHint
                      : t.qualityDirectHint(t.qualityLabel(_videoQuality)),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 16),
              if (_busy) ...[
                LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                ),
                const SizedBox(height: 6),
                Text(_status, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 16),
              ],
              Row(
                children: [
                  Expanded(child: Text(t.downloadedFilesHeader)),
                  IconButton(
                    icon: const Icon(Icons.delete_sweep_outlined),
                    tooltip: t.deleteAllTooltip,
                    onPressed: _downloaded.isEmpty ? null : _deleteAllItems,
                    style: ButtonStyle(
                      // Altijd vol zwart/wit, alleen grijs bij hover — ook
                      // in disabled-stand (niets te verwijderen) geen dim.
                      foregroundColor: WidgetStateProperty.resolveWith((
                        states,
                      ) {
                        if (states.contains(WidgetState.hovered)) {
                          return Colors.grey;
                        }
                        return Theme.of(context).colorScheme.onSurface;
                      }),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: t.searchHint,
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
              const SizedBox(height: 8),
              SegmentedButton<FileFilter>(
                segments: [
                  ButtonSegment(value: FileFilter.all, label: Text(t.filterAll)),
                  ButtonSegment(
                    value: FileFilter.video,
                    label: Text(t.filterVideo),
                    icon: const Icon(Icons.movie),
                  ),
                  ButtonSegment(
                    value: FileFilter.audio,
                    label: Text(t.filterAudio),
                    icon: const Icon(Icons.audiotrack),
                  ),
                ],
                selected: {_fileFilter},
                onSelectionChanged: (s) =>
                    setState(() => _fileFilter = s.first),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Builder(
                  builder: (context) {
                    final rows = _displayRows;
                    if (_downloaded.isEmpty) {
                      return Center(
                        child: Text(
                          t.nothingDownloadedYet,
                          style: const TextStyle(color: Colors.grey),
                        ),
                      );
                    }
                    if (rows.isEmpty) {
                      return Center(
                        child: Text(
                          t.noResults,
                          style: const TextStyle(color: Colors.grey),
                        ),
                      );
                    }
                    return ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (_, i) {
                        final row = rows[i];
                        if (row is _PlaylistGroupRow) {
                          return _buildPlaylistGroupTile(row);
                        }
                        return _buildDownloadedTile(row as DownloadedItem);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}

class _PlaylistGroupRow {
  final String id;
  final List<DownloadedItem> items;
  _PlaylistGroupRow(this.id, this.items);
}

class _AppBarTitle extends StatelessWidget {
  const _AppBarTitle();

  static const _iconAsset = 'Download.icoon.png';
  // Ruimte voor icoon (28) + gap (10) + "Downloader" (~95) ≈ 135.
  static const _minWidthForText = 140.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showText =
            !Platform.isAndroid && constraints.maxWidth >= _minWidthForText;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.asset(
                _iconAsset,
                width: 28,
                height: 28,
                fit: BoxFit.cover,
              ),
            ),
            if (showText) ...[
              const SizedBox(width: 10),
              const Text('Downloader'),
            ],
          ],
        );
      },
    );
  }
}
